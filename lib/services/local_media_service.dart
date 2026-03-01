import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class MediaFile {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime lastModified;
  final MediaFileType type;

  MediaFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.lastModified,
    required this.type,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1048576) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1073741824) {
      return '${(sizeBytes / 1048576).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1073741824).toStringAsFixed(2)} GB';
  }
}

enum MediaFileType { video, audio }

class LocalMediaService {
  static const _videoExtensions = {
    '.mp4',
    '.mkv',
    '.avi',
    '.webm',
    '.3gp',
    '.mov',
    '.flv',
    '.wmv',
  };

  static const _audioExtensions = {
    '.mp3',
    '.m4a',
    '.aac',
    '.wav',
    '.flac',
    '.ogg',
    '.wma',
    '.opus',
  };

  /// Request storage permissions based on Android version.
  static Future<bool> requestPermissions() async {
    // Android 13+ uses granular media permissions
    if (Platform.isAndroid) {
      final videoStatus = await Permission.videos.request();
      final audioStatus = await Permission.audio.request();
      if (videoStatus.isGranted || audioStatus.isGranted) return true;

      // Fall back to legacy storage permission for older Android
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return true;
  }

  /// Scan common directories for video and audio files.
  static Future<List<MediaFile>> scanDeviceMedia({
    bool includeVideo = true,
    bool includeAudio = true,
  }) async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) return [];

    final files = <MediaFile>[];
    final dirsToScan = <String>[];

    if (Platform.isAndroid) {
      const basePath = '/storage/emulated/0';
      dirsToScan.addAll([
        '$basePath/DCIM',
        '$basePath/Movies',
        '$basePath/Download',
        '$basePath/Downloads',
        '$basePath/Music',
        '$basePath/Video',
        '$basePath/Videos',
        '$basePath/Recordings',
        '$basePath/WhatsApp/Media',
      ]);
    }

    for (final dirPath in dirsToScan) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;

          final ext = _getExtension(entity.path);
          MediaFileType? type;

          if (includeVideo && _videoExtensions.contains(ext)) {
            type = MediaFileType.video;
          } else if (includeAudio && _audioExtensions.contains(ext)) {
            type = MediaFileType.audio;
          }

          if (type != null) {
            try {
              final stat = await entity.stat();
              files.add(
                MediaFile(
                  path: entity.path,
                  name: entity.path.split(Platform.pathSeparator).last,
                  sizeBytes: stat.size,
                  lastModified: stat.modified,
                  type: type,
                ),
              );
            } catch (e) {
              debugPrint('Error reading file stat: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('Error scanning $dirPath: $e');
      }
    }

    // Sort by most recent first
    files.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return files;
  }

  static String _getExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1) return '';
    return path.substring(lastDot).toLowerCase();
  }
}
