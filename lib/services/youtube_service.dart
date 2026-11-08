import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/stream_info_item.dart';
import 'media_url.dart';
import 'native_download_service.dart';

class MediaDetails {
  final String id;
  final String title;
  final String thumbnailUrl;
  const MediaDetails({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
  });
}

/// Original name retained for player/library integrations. Android extraction
/// and downloading use the same yt-dlp engine for every supported platform.
class YoutubeService {
  static const publicDownloadDir = '/storage/emulated/0/Download/MediaStreamer';
  final _native = NativeDownloadService();

  Future<(MediaDetails, List<StreamInfoItem>)> getAvailableStreams(
    String input,
  ) async {
    final data = await _native.extract(MediaUrl.require(input));
    final video = MediaDetails(
      id: data['id'] as String? ?? '',
      title: data['title'] as String? ?? 'Video',
      thumbnailUrl: data['thumbnail'] as String? ?? '',
    );
    final items = (data['formats'] as List? ?? []).map((value) {
      final map = Map<String, dynamic>.from(value as Map);
      final size = (map['size'] as num?)?.toInt() ?? 0;
      return StreamInfoItem(
        qualityLabel: map['label'] as String,
        type: map['audioOnly'] == true
            ? StreamType.audioOnly
            : StreamType.muxed,
        codec: map['codec'] as String? ?? '',
        container: map['container'] as String? ?? '',
        sizeBytes: size,
        fileSize: StreamInfoItem.formatFileSize(size),
        formatId: map['id'] as String,
        title: video.title,
        thumbnailUrl: video.thumbnailUrl,
        videoId: video.id,
      );
    }).toList();
    if (items.isEmpty) {
      throw StateError('No downloadable video or audio was found.');
    }
    return (video, items);
  }

  static Future<void> scanMediaStore(String filePath) async {
    try {
      await const MethodChannel(
        'com.mediastreamer/media_store',
      ).invokeMethod('scanFile', filePath);
    } catch (e) {
      debugPrint('MediaStore scan failed: $e');
    }
  }

  static Future<List<FileSystemEntity>> getDownloadedVideos() async {
    final directory = Directory(publicDownloadDir);
    if (!await directory.exists()) return [];
    return directory
        .list()
        .where(
          (file) => RegExp(
            r'\.(mp4|mkv|webm|m4a|mp3|opus)$',
            caseSensitive: false,
          ).hasMatch(file.path),
        )
        .toList();
  }

  static Future<void> deleteVideo(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  void dispose() {}
}
