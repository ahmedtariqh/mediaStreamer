import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_task.dart';
import '../models/stream_info_item.dart';

/// Callback with progress (0–1), downloaded bytes, total bytes, and speed (bytes/sec).
typedef DownloadProgressCallback =
    void Function(
      double progress,
      int downloadedBytes,
      int totalBytes,
      double speed,
    );

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Fetch video metadata from a YouTube URL.
  Future<Video> getVideoInfo(String url) async {
    return _yt.videos.get(url);
  }

  /// Fetch all available streams (muxed, video-only, audio-only) with sizes.
  Future<(Video, List<StreamInfoItem>)> getAvailableStreams(String url) async {
    final video = await _yt.videos.get(url);
    final manifest = await _yt.videos.streamsClient.getManifest(video.id);

    final items = <StreamInfoItem>[];

    // Muxed streams (video + audio)
    for (final s in manifest.muxed) {
      items.add(
        StreamInfoItem(
          qualityLabel: s.qualityLabel,
          type: StreamType.muxed,
          codec: s.videoCodec,
          container: s.container.name,
          sizeBytes: s.size.totalBytes,
          fileSize: StreamInfoItem.formatFileSize(s.size.totalBytes),
          streamInfo: s,
        ),
      );
    }

    // Video-only streams
    for (final s in manifest.videoOnly) {
      items.add(
        StreamInfoItem(
          qualityLabel: s.qualityLabel,
          type: StreamType.videoOnly,
          codec: s.videoCodec,
          container: s.container.name,
          sizeBytes: s.size.totalBytes,
          fileSize: StreamInfoItem.formatFileSize(s.size.totalBytes),
          streamInfo: s,
        ),
      );
    }

    // Audio-only streams
    for (final s in manifest.audioOnly) {
      final bitrate = '${(s.bitrate.bitsPerSecond / 1000).round()}kbps';
      items.add(
        StreamInfoItem(
          qualityLabel: bitrate,
          type: StreamType.audioOnly,
          codec: s.audioCodec,
          container: s.container.name,
          sizeBytes: s.size.totalBytes,
          fileSize: StreamInfoItem.formatFileSize(s.size.totalBytes),
          streamInfo: s,
        ),
      );
    }

    // Sort each group by size descending (highest quality first)
    items.sort((a, b) {
      if (a.type != b.type) return a.type.index.compareTo(b.type.index);
      return b.sizeBytes.compareTo(a.sizeBytes);
    });

    return (video, items);
  }

  /// Download with a specific stream selection.
  /// [onProgress] provides progress, downloaded bytes, total bytes, and speed.
  Future<DownloadTask> downloadStream(
    String url,
    StreamInfoItem selectedStream, {
    DownloadProgressCallback? onProgress,
  }) async {
    final video = await _yt.videos.get(url);
    final stream = _yt.videos.streamsClient.get(selectedStream.streamInfo);

    // Prepare local file
    final dir = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${dir.path}/videos');
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }

    // Determine extension from container
    final ext = selectedStream.type == StreamType.audioOnly
        ? '.${selectedStream.container}'
        : '.mp4';

    // Sanitize file name
    final sanitizedTitle = video.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .substring(0, video.title.length.clamp(0, 80));
    final filePath = '${videosDir.path}/${video.id}_$sanitizedTitle$ext';
    final file = File(filePath);
    final fileStream = file.openWrite();

    final totalSize = selectedStream.sizeBytes;
    var downloadedBytes = 0;
    var lastSpeedCalcTime = DateTime.now();
    var lastSpeedCalcBytes = 0;
    var currentSpeed = 0.0;

    final task = DownloadTask(
      videoId: video.id.value,
      title: video.title,
      thumbnailUrl: video.thumbnails.highResUrl,
      youtubeUrl: url,
      filePath: filePath,
      status: DownloadStatus.downloading,
    );

    try {
      await for (final chunk in stream) {
        fileStream.add(chunk);
        downloadedBytes += chunk.length;
        task.progress = downloadedBytes / totalSize;

        // Calculate speed every 500ms
        final now = DateTime.now();
        final elapsed = now.difference(lastSpeedCalcTime).inMilliseconds;
        if (elapsed >= 500) {
          final bytesSinceLastCalc = downloadedBytes - lastSpeedCalcBytes;
          currentSpeed = bytesSinceLastCalc / (elapsed / 1000);
          lastSpeedCalcTime = now;
          lastSpeedCalcBytes = downloadedBytes;
        }

        onProgress?.call(
          task.progress,
          downloadedBytes,
          totalSize,
          currentSpeed,
        );
      }

      await fileStream.flush();
      await fileStream.close();
      task.status = DownloadStatus.completed;
    } catch (e) {
      await fileStream.close();
      if (await file.exists()) await file.delete();
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
    }

    return task;
  }

  /// Legacy download — highest quality muxed stream.
  Future<DownloadTask> downloadVideo(
    String url, {
    ValueChanged<double>? onProgress,
  }) async {
    final (_, streams) = await getAvailableStreams(url);
    final muxed = streams.where((s) => s.type == StreamType.muxed).toList();
    if (muxed.isEmpty) {
      throw Exception('No muxed streams available');
    }
    return downloadStream(
      url,
      muxed.first,
      onProgress: (progress, a, b, c) => onProgress?.call(progress),
    );
  }

  /// List all downloaded video files.
  static Future<List<FileSystemEntity>> getDownloadedVideos() async {
    final dir = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${dir.path}/videos');
    if (!await videosDir.exists()) return [];
    return videosDir
        .listSync()
        .where(
          (f) =>
              f.path.endsWith('.mp4') ||
              f.path.endsWith('.webm') ||
              f.path.endsWith('.m4a'),
        )
        .toList();
  }

  /// Delete a downloaded video file.
  static Future<void> deleteVideo(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  void dispose() {
    _yt.close();
  }
}
