import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/stream_info_item.dart';

class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Public download directory visible to all apps.
  static const publicDownloadDir = '/storage/emulated/0/Download/MediaStreamer';

  /// Method channel for MediaStore scanning.
  static const _mediaStoreChannel = MethodChannel(
    'com.mediastreamer/media_store',
  );

  YoutubeExplode getYoutubeExplode() => _yt;

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

  /// Notify Android MediaStore about a new file.
  static void scanMediaStore(String filePath) {
    try {
      _mediaStoreChannel.invokeMethod('scanFile', filePath);
    } catch (e) {
      debugPrint('MediaStore scan failed: $e');
    }
  }

  /// List all downloaded video files from the public folder.
  static Future<List<FileSystemEntity>> getDownloadedVideos() async {
    final videosDir = Directory(publicDownloadDir);
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
