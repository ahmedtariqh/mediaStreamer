import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/folder_item.dart';

class MediaFile {
  final String path;
  final String name;
  final String directory;
  final int sizeBytes;
  final DateTime lastModified;
  final MediaFileType type;

  MediaFile({
    required this.path,
    required this.name,
    required this.directory,
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

  String get extension {
    final lastDot = name.lastIndexOf('.');
    if (lastDot == -1) return '';
    return name.substring(lastDot).toLowerCase();
  }
}

enum MediaFileType { video, audio }

/// Sorting options for media files.
enum MediaSortOption {
  nameAsc,
  nameDesc,
  dateNewest,
  dateOldest,
  sizeLargest,
  sizeSmallest,
}

/// Filter options for media type.
enum MediaFilterOption { all, videoOnly, audioOnly }

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
    '.ts',
    '.m4v',
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
    '.amr',
  };

  static const _mediaChannel = MethodChannel('com.mediastreamer/media_query');

  /// Returns true if the extension is a recognised media file.
  static bool isMediaExtension(String ext) {
    final lower = ext.toLowerCase();
    return _videoExtensions.contains(lower) || _audioExtensions.contains(lower);
  }

  static MediaFileType? typeForExtension(String ext) {
    final lower = ext.toLowerCase();
    if (_videoExtensions.contains(lower)) return MediaFileType.video;
    if (_audioExtensions.contains(lower)) return MediaFileType.audio;
    return null;
  }

  // ──────────────────────────────────────────────
  //  Permissions
  // ──────────────────────────────────────────────

  static Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) return true;

    // Check if we already have permissions
    if (await Permission.videos.isGranted && await Permission.audio.isGranted) {
      return true;
    }
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }
    if (await Permission.storage.isGranted) {
      return true;
    }

    // Android 13+ (API 33+) — request granular media permissions
    final results = await [Permission.videos, Permission.audio].request();

    if (results[Permission.videos]?.isGranted == true ||
        results[Permission.audio]?.isGranted == true) {
      return true;
    }

    // Fallback: try legacy storage permission (Android < 13)
    final storageResult = await Permission.storage.request();
    if (storageResult.isGranted) return true;

    // Last resort: MANAGE_EXTERNAL_STORAGE (shows special settings page)
    final manageResult = await Permission.manageExternalStorage.request();
    return manageResult.isGranted;
  }

  // ──────────────────────────────────────────────
  //  Media scanning via MediaStore (Android)
  // ──────────────────────────────────────────────

  /// Scan for all media files using Android MediaStore API.
  /// This is the correct approach on Android 10+ (scoped storage).
  static Future<List<MediaFile>> scanAllMedia({
    bool includeVideo = true,
    bool includeAudio = true,
  }) async {
    try {
      // Try MediaStore query first (most reliable on modern Android)
      final result = await _mediaChannel.invokeMethod('queryMedia', {
        'includeVideo': includeVideo,
        'includeAudio': includeAudio,
      });

      if (result is List) {
        return result.map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          final path = map['path'] as String;
          final name = map['name'] as String;
          final size = map['size'] as int? ?? 0;
          final modified = map['modified'] as int? ?? 0;
          final isVideo = map['isVideo'] as bool? ?? true;

          return MediaFile(
            path: path,
            name: name,
            directory: path.substring(0, path.lastIndexOf('/')),
            sizeBytes: size,
            lastModified: DateTime.fromMillisecondsSinceEpoch(modified * 1000),
            type: isVideo ? MediaFileType.video : MediaFileType.audio,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint(
        'MediaStore query failed: $e — falling back to filesystem scan',
      );
    }

    // Fallback: filesystem scan
    return _fallbackFilesystemScan(
      includeVideo: includeVideo,
      includeAudio: includeAudio,
    );
  }

  /// Fallback filesystem scan for older Android or when MediaStore fails.
  static Future<List<MediaFile>> _fallbackFilesystemScan({
    bool includeVideo = true,
    bool includeAudio = true,
  }) async {
    final commonPaths = [
      '/storage/emulated/0/DCIM',
      '/storage/emulated/0/Movies',
      '/storage/emulated/0/Music',
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Video',
      '/storage/emulated/0/Recordings',
      '/storage/emulated/0/WhatsApp/Media',
      '/storage/emulated/0/Telegram',
    ];

    final files = <MediaFile>[];

    for (final dirPath in commonPaths) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      try {
        for (final entity in dir.listSync(
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
              final stat = entity.statSync();
              final parts = entity.path.split('/');
              files.add(
                MediaFile(
                  path: entity.path,
                  name: parts.last,
                  directory: parts.sublist(0, parts.length - 1).join('/'),
                  sizeBytes: stat.size,
                  lastModified: stat.modified,
                  type: type,
                ),
              );
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('Error scanning $dirPath: $e');
      }
    }

    files.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return files;
  }

  // ──────────────────────────────────────────────
  //  Folder browsing
  // ──────────────────────────────────────────────

  /// List the immediate children of [dirPath].
  static Future<({List<FolderItem> folders, List<MediaFile> files})>
  listDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return (folders: <FolderItem>[], files: <MediaFile>[]);
    }

    final folders = <FolderItem>[];
    final files = <MediaFile>[];

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is Directory) {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (name.startsWith('.')) continue;
          folders.add(FolderItem(name: name, path: entity.path));
        } else if (entity is File) {
          final ext = _getExtension(entity.path);
          final type = typeForExtension(ext);
          if (type != null) {
            try {
              final stat = await entity.stat();
              final parts = entity.path.split(Platform.pathSeparator);
              files.add(
                MediaFile(
                  path: entity.path,
                  name: parts.last,
                  directory: dirPath,
                  sizeBytes: stat.size,
                  lastModified: stat.modified,
                  type: type,
                ),
              );
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('Error listing $dirPath: $e');
    }

    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    files.sort((a, b) => b.lastModified.compareTo(a.lastModified));

    return (folders: folders, files: files);
  }

  // ──────────────────────────────────────────────
  //  Sorting & Filtering helpers
  // ──────────────────────────────────────────────

  static List<MediaFile> sortFiles(
    List<MediaFile> files,
    MediaSortOption sort,
  ) {
    final sorted = List<MediaFile>.from(files);
    switch (sort) {
      case MediaSortOption.nameAsc:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case MediaSortOption.nameDesc:
        sorted.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
      case MediaSortOption.dateNewest:
        sorted.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      case MediaSortOption.dateOldest:
        sorted.sort((a, b) => a.lastModified.compareTo(b.lastModified));
      case MediaSortOption.sizeLargest:
        sorted.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
      case MediaSortOption.sizeSmallest:
        sorted.sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
    }
    return sorted;
  }

  static List<MediaFile> filterFiles(
    List<MediaFile> files,
    MediaFilterOption filter,
  ) {
    switch (filter) {
      case MediaFilterOption.all:
        return files;
      case MediaFilterOption.videoOnly:
        return files.where((f) => f.type == MediaFileType.video).toList();
      case MediaFilterOption.audioOnly:
        return files.where((f) => f.type == MediaFileType.audio).toList();
    }
  }

  static List<MediaFile> searchFiles(List<MediaFile> files, String query) {
    if (query.isEmpty) return files;
    final lower = query.toLowerCase();
    return files.where((f) => f.name.toLowerCase().contains(lower)).toList();
  }

  static String _getExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1) return '';
    return path.substring(lastDot).toLowerCase();
  }
}
