import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_history.dart';
import '../models/download_task.dart';
import '../models/stream_info_item.dart';
import 'media_url.dart';
import 'native_download_service.dart';
import 'youtube_service.dart';

/// A view of the native service. Closing Flutter never cancels a download.
class DownloadManager extends ChangeNotifier with WidgetsBindingObserver {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final _native = NativeDownloadService();
  final _tasks = <DownloadTask>[];
  final _nativeHistory = <DownloadHistoryItem>[];
  final _legacyHistory = <DownloadHistoryItem>[];
  Timer? _poller;
  Future<void>? _initialization;
  bool _refreshing = false;
  String? _lastSnapshot;
  List<DownloadTask> get activeTasks => List.unmodifiable(_tasks);
  List<DownloadHistoryItem> get history => List.unmodifiable([
    ..._nativeHistory,
    ..._legacyHistory.where(
      (old) => !_nativeHistory.any((item) => item.filePath == old.filePath),
    ),
  ]);

  Future<void> init() => _initialization ??= _init();

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    for (final value in prefs.getStringList('download_history') ?? <String>[]) {
      try {
        final item = DownloadHistoryItem.fromJson(jsonDecode(value));
        item.fileExists = await File(item.filePath).exists();
        _legacyHistory.add(item);
      } catch (e) {
        debugPrint('Skipping damaged history entry: $e');
      }
    }
    WidgetsBinding.instance.addObserver(this);
    await refresh();
  }

  void _startPolling() {
    _poller?.cancel();
    _poller = Timer.periodic(const Duration(seconds: 1), (_) => refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
      _startPolling();
    } else {
      _poller?.cancel();
    }
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await _native.snapshot();
      final encoded = jsonEncode(snapshot);
      if (encoded == _lastSnapshot) return;
      _lastSnapshot = encoded;
      final tasks = <DownloadTask>[];
      final completed = <DownloadHistoryItem>[];
      for (final raw in snapshot) {
        final data = Map<String, dynamic>.from(raw as Map);
        final task = DownloadTask(
          id: data['id'] as String,
          videoId: data['videoId'] as String? ?? '',
          title: data['title'] as String? ?? 'Video',
          thumbnailUrl: data['thumbnailUrl'] as String? ?? '',
          youtubeUrl: data['url'] as String,
          filePath: data['filePath'] as String? ?? '',
          status: DownloadStatus.values.firstWhere(
            (s) => s.name == data['status'],
            orElse: () => DownloadStatus.failed,
          ),
          progress: ((data['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1),
          errorMessage: data['error'] as String?,
        );
        task.downloadedBytes = (data['downloadedBytes'] as num?)?.toInt() ?? 0;
        task.totalBytes = (data['totalBytes'] as num?)?.toInt() ?? 0;
        task.currentSpeed = (data['speed'] as num?)?.toDouble() ?? 0;
        if (task.status == DownloadStatus.completed) {
          completed.add(
            DownloadHistoryItem(
              id: task.id,
              videoId: task.videoId,
              title: task.title,
              youtubeUrl: task.youtubeUrl,
              thumbnailUrl: task.thumbnailUrl,
              filePath: task.filePath,
              downloadDate: DateTime.fromMillisecondsSinceEpoch(
                (data['completedAt'] as num?)?.toInt() ?? 0,
              ),
              fileExists: data['fileExists'] as bool? ?? true,
            ),
          );
        } else if (task.status != DownloadStatus.cancelled) {
          tasks.add(task);
        }
      }
      completed.sort((a, b) => b.downloadDate.compareTo(a.downloadDate));
      _tasks
        ..clear()
        ..addAll(tasks);
      _nativeHistory
        ..clear()
        ..addAll(completed);
      if (_tasks.any(
        (task) =>
            task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.queued,
      )) {
        if (_poller?.isActive != true) _startPolling();
      } else {
        _poller?.cancel();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Could not refresh downloads: $e');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> startLegacyDownload(String url) async {
    final (_, streams) = await YoutubeService().getAvailableStreams(url);
    await startDownload(url, streams.first);
  }

  Future<void> startDownload(String url, StreamInfoItem stream) async {
    await _native.enqueue({
      'url': MediaUrl.require(url),
      'format': stream.formatId,
      'title': stream.title,
      'videoId': stream.videoId,
      'thumbnailUrl': stream.thumbnailUrl,
    });
    await refresh();
  }

  Future<void> startGenericDownload(String url, String fileName) async {
    await _native.enqueue({
      'url': MediaUrl.require(url),
      'format': 'best',
      'title': fileName,
    });
    await refresh();
  }

  Future<void> _command(String command, String id) async {
    await _native.command(command, id);
    await refresh();
  }

  Future<void> pauseDownload(String id) => _command('pause', id);
  Future<void> resumeDownload(String id) => _command('resume', id);
  Future<void> cancelDownload(String id) => _command('cancel', id);

  Future<void> removeHistoryItem(String id) async {
    if (_legacyHistory.any((item) => item.id == id)) {
      _legacyHistory.removeWhere((item) => item.id == id);
      await _saveLegacyHistory();
      notifyListeners();
    } else {
      await _command('removeHistory', id);
    }
  }

  Future<void> _saveLegacyHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'download_history',
      _legacyHistory.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> deleteHistoryFile(String id) async {
    final legacy = _legacyHistory.where((item) => item.id == id).firstOrNull;
    if (legacy != null) {
      final file = File(legacy.filePath);
      if (await file.exists()) await file.delete();
      legacy.fileExists = false;
      await _saveLegacyHistory();
      notifyListeners();
    } else {
      await _command('deleteFile', id);
    }
  }

  Future<void> checkExistingFiles() async {
    for (final item in _legacyHistory) {
      item.fileExists = await File(item.filePath).exists();
    }
    await refresh();
  }
}
