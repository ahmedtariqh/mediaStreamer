import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_history.dart';
import '../models/download_task.dart';
import '../models/stream_info_item.dart';
import 'download_notification_service.dart';
import 'youtube_service.dart';

class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final YoutubeService _youtubeService = YoutubeService();
  final Map<String, DownloadTask> _activeDownloads = {};
  final Map<String, StreamSubscription<List<int>>> _subscriptions = {};
  final Map<String, IOSink> _sinks = {};

  List<DownloadHistoryItem> _history = [];

  List<DownloadHistoryItem> get history => _history;
  List<DownloadTask> get activeTasks => _activeDownloads.values.toList();

  Future<void> init() async {
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyList = prefs.getStringList('download_history') ?? [];
    _history = historyList
        .map((e) => DownloadHistoryItem.fromJson(jsonDecode(e)))
        .toList();

    // Check if files still exist
    for (var item in _history) {
      item.fileExists = await File(item.filePath).exists();
    }
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyList = _history.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList('download_history', historyList);
  }

  void _addToHistory(DownloadTask task) {
    // If it already exists in history, we might want to update or move it to front.
    _history.removeWhere((item) => item.youtubeUrl == task.youtubeUrl);
    final historyItem = DownloadHistoryItem(
      id: task.id,
      videoId: task.videoId,
      title: task.title,
      youtubeUrl: task.youtubeUrl,
      thumbnailUrl: task.thumbnailUrl,
      filePath: task.filePath,
      downloadDate: DateTime.now(),
      fileExists: true,
    );
    _history.insert(0, historyItem);
    _saveHistory();
    notifyListeners();
  }

  void removeHistoryItem(String id) {
    _history.removeWhere((item) => item.id == id);
    _saveHistory();
    notifyListeners();
  }

  Future<void> startLegacyDownload(String url) async {
    final (_, streams) = await _youtubeService.getAvailableStreams(url);
    final muxed = streams.where((s) => s.type == StreamType.muxed).toList();
    if (muxed.isEmpty) {
      throw Exception('No muxed streams available for download');
    }
    await startDownload(url, muxed.first);
  }

  Future<void> startDownload(String url, StreamInfoItem selectedStream) async {
    // Check for duplicates
    final existingHistory = _history
        .where((item) => item.youtubeUrl == url)
        .toList();
    if (existingHistory.isNotEmpty) {
      final item = existingHistory.first;
      if (item.fileExists) {
        throw Exception('File already downloaded.');
      }
    }

    // if task is already downloading
    if (_activeDownloads.values.any(
      (task) =>
          task.youtubeUrl == url &&
          task.status != DownloadStatus.failed &&
          task.status != DownloadStatus.cancelled,
    )) {
      throw Exception('Already downloading this video.');
    }

    final video = await _youtubeService.getVideoInfo(url);
    final streamData = _youtubeService
        .getYoutubeExplode()
        .videos
        .streamsClient
        .get(selectedStream.streamInfo);

    final videosDir = Directory(YoutubeService.publicDownloadDir);
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }

    final ext = selectedStream.type == StreamType.audioOnly
        ? '.${selectedStream.container}'
        : '.mp4';

    final sanitizedTitle = video.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .substring(0, video.title.length.clamp(0, 80));
    final filePath = '${videosDir.path}/${video.id}_$sanitizedTitle$ext';
    final file = File(filePath);
    final fileSink = file.openWrite();

    final task = DownloadTask(
      videoId: video.id.value,
      title: video.title,
      thumbnailUrl: video.thumbnails.highResUrl,
      youtubeUrl: url,
      filePath: filePath,
      status: DownloadStatus.downloading,
    );
    task.totalBytes = selectedStream.sizeBytes;

    _activeDownloads[task.id] = task;
    _sinks[task.id] = fileSink;
    notifyListeners();

    var lastSpeedCalcTime = DateTime.now();
    var lastSpeedCalcBytes = 0;

    final sub = streamData.listen(
      (chunk) {
        fileSink.add(chunk);
        task.downloadedBytes += chunk.length;
        task.progress = task.downloadedBytes / task.totalBytes;

        final now = DateTime.now();
        final elapsed = now.difference(lastSpeedCalcTime).inMilliseconds;
        if (elapsed >= 500) {
          final bytesSinceLastCalc = task.downloadedBytes - lastSpeedCalcBytes;
          task.currentSpeed = bytesSinceLastCalc / (elapsed / 1000);
          lastSpeedCalcTime = now;
          lastSpeedCalcBytes = task.downloadedBytes;

          DownloadNotificationService.showProgress(
            id: task.id.hashCode,
            title: task.title,
            progress: (task.progress * 100).toInt(),
            body:
                '${(task.currentSpeed / 1024 / 1024).toStringAsFixed(2)} MB/s',
          );
          notifyListeners();
        }
      },
      onDone: () async {
        await fileSink.flush();
        await fileSink.close();
        _sinks.remove(task.id);
        _subscriptions.remove(task.id);

        task.status = DownloadStatus.completed;
        task.progress = 1.0;

        DownloadNotificationService.showComplete(
          id: task.id.hashCode,
          title: task.title,
          filePath: task.filePath,
        );
        YoutubeService.scanMediaStore(task.filePath);

        _addToHistory(task);
        _activeDownloads.remove(task.id);
        notifyListeners();
      },
      onError: (e) async {
        await fileSink.flush();
        await fileSink.close();
        _sinks.remove(task.id);
        _subscriptions.remove(task.id);

        task.status = DownloadStatus.failed;
        task.errorMessage = e.toString();

        DownloadNotificationService.showFailed(
          id: task.id.hashCode,
          title: task.title,
          error: e.toString(),
        );
        notifyListeners();
      },
      cancelOnError: true,
    );

    _subscriptions[task.id] = sub;
  }

  Future<void> startGenericDownload(String url, String fileName) async {
    // Check for duplicates
    if (_activeDownloads.values.any(
      (task) =>
          task.youtubeUrl == url &&
          task.status != DownloadStatus.failed &&
          task.status != DownloadStatus.cancelled,
    )) {
      throw Exception('Already downloading this file.');
    }

    final videosDir = Directory(YoutubeService.publicDownloadDir);
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }

    final sanitizedTitle = fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .substring(0, fileName.length.clamp(0, 80));
    final filePath = '${videosDir.path}/$sanitizedTitle';
    final file = File(filePath);
    final fileSink = file.openWrite();

    final task = DownloadTask(
      videoId: 'generic_${DateTime.now().millisecondsSinceEpoch}',
      title: sanitizedTitle,
      thumbnailUrl: '', // No thumbnail for generic files
      youtubeUrl: url,
      filePath: filePath,
      status: DownloadStatus.downloading,
    );

    _activeDownloads[task.id] = task;
    _sinks[task.id] = fileSink;
    notifyListeners();

    try {
      final request = await HttpClient().getUrl(Uri.parse(url));
      final response = await request.close();
      task.totalBytes = response.contentLength > 0 ? response.contentLength : 0;

      var lastSpeedCalcTime = DateTime.now();
      var lastSpeedCalcBytes = 0;

      final sub = response.listen(
        (chunk) {
          fileSink.add(chunk);
          task.downloadedBytes += chunk.length;
          if (task.totalBytes > 0) {
            task.progress = task.downloadedBytes / task.totalBytes;
          }

          final now = DateTime.now();
          final elapsed = now.difference(lastSpeedCalcTime).inMilliseconds;
          if (elapsed >= 500) {
            final bytesSinceLastCalc =
                task.downloadedBytes - lastSpeedCalcBytes;
            task.currentSpeed = bytesSinceLastCalc / (elapsed / 1000);
            lastSpeedCalcTime = now;
            lastSpeedCalcBytes = task.downloadedBytes;

            DownloadNotificationService.showProgress(
              id: task.id.hashCode,
              title: task.title,
              progress: task.totalBytes > 0
                  ? (task.progress * 100).toInt()
                  : -1,
              body:
                  '${(task.currentSpeed / 1024 / 1024).toStringAsFixed(2)} MB/s',
            );
            notifyListeners();
          }
        },
        onDone: () async {
          await fileSink.flush();
          await fileSink.close();
          _sinks.remove(task.id);
          _subscriptions.remove(task.id);

          task.status = DownloadStatus.completed;
          task.progress = 1.0;

          DownloadNotificationService.showComplete(
            id: task.id.hashCode,
            title: task.title,
            filePath: task.filePath,
          );
          YoutubeService.scanMediaStore(task.filePath);

          _addToHistory(task);
          _activeDownloads.remove(task.id);
          notifyListeners();
        },
        onError: (e) async {
          await fileSink.flush();
          await fileSink.close();
          _sinks.remove(task.id);
          _subscriptions.remove(task.id);

          task.status = DownloadStatus.failed;
          task.errorMessage = e.toString();

          DownloadNotificationService.showFailed(
            id: task.id.hashCode,
            title: task.title,
            error: e.toString(),
          );
          notifyListeners();
        },
        cancelOnError: true,
      );

      _subscriptions[task.id] = sub;
    } catch (e) {
      await fileSink.flush();
      await fileSink.close();
      _sinks.remove(task.id);

      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();

      DownloadNotificationService.showFailed(
        id: task.id.hashCode,
        title: task.title,
        error: e.toString(),
      );
      notifyListeners();
    }
  }

  void pauseDownload(String id) {
    if (_subscriptions.containsKey(id)) {
      _subscriptions[id]?.pause();
      if (_activeDownloads.containsKey(id)) {
        _activeDownloads[id]!.status = DownloadStatus.paused;
        DownloadNotificationService.showProgress(
          id: id.hashCode,
          title: _activeDownloads[id]!.title,
          progress: (_activeDownloads[id]!.progress * 100).toInt(),
          body: 'Paused',
        );
        notifyListeners();
      }
    }
  }

  void resumeDownload(String id) {
    if (_subscriptions.containsKey(id)) {
      _subscriptions[id]?.resume();
      if (_activeDownloads.containsKey(id)) {
        _activeDownloads[id]!.status = DownloadStatus.downloading;
        notifyListeners();
      }
    }
  }

  Future<void> cancelDownload(String id) async {
    if (_subscriptions.containsKey(id)) {
      await _subscriptions[id]?.cancel();
      _subscriptions.remove(id);
    }
    if (_sinks.containsKey(id)) {
      await _sinks[id]?.close();
      _sinks.remove(id);
    }
    if (_activeDownloads.containsKey(id)) {
      final task = _activeDownloads[id]!;
      task.status = DownloadStatus.cancelled;
      DownloadNotificationService.cancel(task.id.hashCode);

      // Remove partial file
      final file = File(task.filePath);
      if (await file.exists()) {
        await file.delete();
      }

      _activeDownloads.remove(id);
      notifyListeners();
    }
  }

  Future<void> deleteHistoryFile(String id) async {
    final itemIndex = _history.indexWhere((item) => item.id == id);
    if (itemIndex != -1) {
      final item = _history[itemIndex];
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      item.fileExists = false;
      await _saveHistory();
      notifyListeners();
    }
  }

  Future<void> checkExistingFiles() async {
    bool changed = false;
    for (var item in _history) {
      bool exists = await File(item.filePath).exists();
      if (item.fileExists != exists) {
        item.fileExists = exists;
        changed = true;
      }
    }
    if (changed) {
      await _saveHistory();
      notifyListeners();
    }
  }
}
