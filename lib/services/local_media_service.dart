import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
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

  static const _rootPath = '/storage/emulated/0';

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

    // Android 11+ — try MANAGE_EXTERNAL_STORAGE first (full access)
    if (await Permission.manageExternalStorage.request().isGranted) {
      return true;
    }

    // Android 13+ granular media permissions
    final videoStatus = await Permission.videos.request();
    final audioStatus = await Permission.audio.request();
    if (videoStatus.isGranted || audioStatus.isGranted) return true;

    // Fallback to legacy
    final storageStatus = await Permission.storage.request();
    return storageStatus.isGranted;
  }

  // ──────────────────────────────────────────────
  //  Full device scan (runs in an isolate)
  // ──────────────────────────────────────────────

  /// Scan the entire internal storage for media files.
  static Future<List<MediaFile>> scanAllMedia({
    bool includeVideo = true,
    bool includeAudio = true,
  }) async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) return [];

    // Heavy I/O — run in a background isolate.
    return Isolate.run(
      () => _scanDirectory(
        _rootPath,
        includeVideo: includeVideo,
        includeAudio: includeAudio,
      ),
    );
  }

  /// Synchronous scan used inside isolates.
  static List<MediaFile> _scanDirectory(
    String rootPath, {
    bool includeVideo = true,
    bool includeAudio = true,
  }) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) return [];

    final files = <MediaFile>[];

    try {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
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
            final parts = entity.path.split(Platform.pathSeparator);
            files.add(
              MediaFile(
                path: entity.path,
                name: parts.last,
                directory: parts
                    .sublist(0, parts.length - 1)
                    .join(Platform.pathSeparator),
                sizeBytes: stat.size,
                lastModified: stat.modified,
                type: type,
              ),
            );
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error scanning $rootPath: $e');
    }

    files.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return files;
  }

  // ──────────────────────────────────────────────
  //  Folder browsing
  // ──────────────────────────────────────────────

  /// List the immediate children of [dirPath].
  /// Returns a record of folders and media files found at that level.
  static Future<({List<FolderItem> folders, List<MediaFile> files})>
  listDirectory(String dirPath) async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) return (folders: <FolderItem>[], files: <MediaFile>[]);

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
          // Skip hidden directories
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

  // ──────────────────────────────────────────────

  static String _getExtension(String path) {
    final lastDot = path.lastIndexOf('.');
    if (lastDot == -1) return '';
    return path.substring(lastDot).toLowerCase();
  }
}
