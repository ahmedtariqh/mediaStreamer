import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import '../services/local_media_service.dart';
import 'media_entry.dart';

enum CatalogSort { name, filename, duration, added, size }

List<MediaEntry> sortMedia(
  Iterable<MediaEntry> items,
  CatalogSort sort, {
  bool descending = false,
}) {
  final result = items.toList();
  result.sort((a, b) {
    var c = switch (sort) {
      CatalogSort.name => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      CatalogSort.filename => a.filename.toLowerCase().compareTo(
        b.filename.toLowerCase(),
      ),
      CatalogSort.duration => a.duration.compareTo(b.duration),
      CatalogSort.added => a.added.compareTo(b.added),
      CatalogSort.size => a.size.compareTo(b.size),
    };
    if (c == 0) c = a.uri.compareTo(b.uri);
    return descending ? -c : c;
  });
  return result;
}

Map<String, List<MediaEntry>> groupMedia(
  Iterable<MediaEntry> items,
  String group,
) {
  final result = <String, List<MediaEntry>>{};
  for (final m in items) {
    final key = switch (group) {
      'artist' => m.artist,
      'album' => m.album,
      'genre' => m.genre,
      _ => m.folder,
    };
    (result[key.isEmpty || key == '<unknown>' ? 'Unknown' : key] ??= []).add(m);
  }
  return Map.fromEntries(
    result.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
  );
}

class MediaCatalog extends ChangeNotifier {
  static final instance = MediaCatalog._();
  MediaCatalog._();
  List<MediaEntry> items = [];
  bool loading = false;
  String? error;
  DateTime? _loaded;
  Future<void> load({bool force = false}) async {
    if (loading ||
        (!force &&
            _loaded != null &&
            DateTime.now().difference(_loaded!) <
                const Duration(seconds: 30))) {
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (!await LocalMediaService.requestPermissions()) {
        throw StateError(
          'Media access was not granted. Use Open file to select individual files.',
        );
      }
      final result = await const MethodChannel('com.mediastreamer/media_query')
          .invokeListMethod('queryMedia', {
            'includeVideo': true,
            'includeAudio': true,
          });
      items = (result ?? []).map((m) => MediaEntry.fromMap(m as Map)).toList();
      _loaded = DateTime.now();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// Bounded decoded thumbnail cache and two workers, independent of library size.
class ThumbnailCache {
  static final _cache = <String, Future<Uint8List?>>{};
  static final _waiting =
      Queue<({String path, Completer<Uint8List?> result})>();
  static int _active = 0;
  static Future<Uint8List?> get(String path) {
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      return cached;
    }
    final result = Completer<Uint8List?>();
    _cache[path] = result.future;
    while (_cache.length > 96) {
      _cache.remove(_cache.keys.first);
    }
    _waiting.add((path: path, result: result));
    _pump();
    return result.future;
  }

  static void _pump() {
    while (_active < 2 && _waiting.isNotEmpty) {
      final task = _waiting.removeFirst();
      _active++;
      unawaited(() async {
        try {
          task.result.complete(
            await VideoThumbnail.thumbnailData(
              video: task.path,
              imageFormat: ImageFormat.JPEG,
              maxWidth: 320,
              quality: 60,
            ),
          );
        } catch (_) {
          task.result.complete(null);
        } finally {
          _active--;
          _pump();
        }
      }());
    }
  }
}
