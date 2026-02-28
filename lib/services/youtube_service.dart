import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_task.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Fetch video metadata from a YouTube URL.
  Future<Video> getVideoInfo(String url) async {
    return _yt.videos.get(url);
  }

  /// Download the video with highest quality muxed stream.
  /// [onProgress] is called with a value 0.0 – 1.0.
  Future<DownloadTask> downloadVideo(
    String url, {
    ValueChanged<double>? onProgress,
  }) async {
    final video = await _yt.videos.get(url);
    final manifest = await _yt.videos.streamsClient.getManifest(video.id);

    // Get the highest quality muxed stream (audio + video combined)
    final streamInfo = manifest.muxed.withHighestBitrate();
    final stream = _yt.videos.streamsClient.get(streamInfo);

    // Prepare local file
    final dir = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${dir.path}/videos');
    if (!await videosDir.exists()) {
      await videosDir.create(recursive: true);
    }

    // Sanitize file name
    final sanitizedTitle = video.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .substring(0, video.title.length.clamp(0, 80));
    final filePath = '${videosDir.path}/${video.id}_$sanitizedTitle.mp4';
    final file = File(filePath);
    final fileStream = file.openWrite();

    final totalSize = streamInfo.size.totalBytes;
    var downloadedBytes = 0;

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
        onProgress?.call(task.progress);
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

  /// List all downloaded video files.
  static Future<List<FileSystemEntity>> getDownloadedVideos() async {
    final dir = await getApplicationDocumentsDirectory();
    final videosDir = Directory('${dir.path}/videos');
    if (!await videosDir.exists()) return [];
    return videosDir.listSync().where((f) => f.path.endsWith('.mp4')).toList();
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
