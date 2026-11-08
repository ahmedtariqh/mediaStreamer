class MediaEntry {
  final String uri, title, artist, album, genre, contentUri, sourceUrl;
  final bool audio;
  final int duration, size, added;
  const MediaEntry({
    required this.uri,
    required this.title,
    this.audio = false,
    this.duration = 0,
    this.size = 0,
    this.added = 0,
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.contentUri = '',
    this.sourceUrl = '',
  });
  factory MediaEntry.fromMap(Map m) => MediaEntry(
    uri: (m['uri'] ?? m['path'] ?? '').toString(),
    title: (m['title'] ?? m['name'] ?? 'Media').toString(),
    audio: m['audio'] == true || m['isVideo'] == false,
    duration: (m['duration'] as num?)?.toInt() ?? 0,
    size: (m['size'] as num?)?.toInt() ?? 0,
    added: (m['added'] as num?)?.toInt() ?? 0,
    artist: (m['artist'] ?? '').toString(),
    album: (m['album'] ?? '').toString(),
    genre: (m['genre'] ?? '').toString(),
    contentUri: (m['contentUri'] ?? '').toString(),
    sourceUrl: (m['sourceUrl'] ?? '').toString(),
  );
  Map<String, dynamic> toMap() => {
    'uri': uri,
    'title': title,
    'audio': audio,
    'duration': duration,
    'size': size,
    'added': added,
    'artist': artist,
    'album': album,
    'genre': genre,
    'contentUri': contentUri,
    'sourceUrl': sourceUrl,
  };
  String get filename =>
      Uri.tryParse(uri)?.pathSegments.lastOrNull ?? uri.split('/').last;
  String get folder =>
      uri.contains('/') ? uri.substring(0, uri.lastIndexOf('/')) : '';
  static bool isAudio(String path) => RegExp(
    r'\.(mp3|m4a|aac|wav|flac|ogg|wma|opus|amr|aiff)(\?|$)',
    caseSensitive: false,
  ).hasMatch(path);
}

String mediaTime(int ms) {
  final s = (ms.clamp(0, 1 << 53) / 1000).floor();
  return s >= 3600
      ? '${s ~/ 3600}:${((s ~/ 60) % 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}'
      : '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

int? parseMediaTime(String text) {
  final parts = text.trim().split(':');
  if (parts.isEmpty ||
      parts.length > 3 ||
      parts.any((p) => !RegExp(r'^\d+$').hasMatch(p))) {
    return null;
  }
  final parsed = parts.map(int.tryParse).toList();
  if (parsed.any((v) => v == null)) return null;
  final values = parsed.cast<int>();
  if (values.any((v) => v > 2147483647)) return null;
  if (values.skip(1).any((n) => n >= 60)) return null;
  final seconds = values.fold<int>(0, (a, b) => a * 60 + b);
  return seconds <= 2147483647 ? seconds * 1000 : null;
}

List<MediaEntry> parsePlaylist(String text, {String? baseUri}) {
  final lines = text.replaceAll('\r', '').split('\n');
  final entries = <MediaEntry>[];
  String? title;
  final pls = <int, Map<String, String>>{};
  for (var line in lines) {
    line = line.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTINF:')) {
      title = line.substring(line.indexOf(',') + 1);
      continue;
    }
    if (line.startsWith('#') || line.startsWith('[')) continue;
    final match = RegExp(
      r'^(File|Title)(\d+)=(.*)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) {
      (pls[int.parse(match[2]!)] ??= {})[match[1]!.toLowerCase()] = match[3]!;
      continue;
    }
    if (line.contains('=') && !line.contains('://')) continue;
    _playlistEntry(entries, line, title, baseUri);
    title = null;
  }
  for (final key in pls.keys.toList()..sort()) {
    final m = pls[key]!;
    if (m['file'] != null) {
      _playlistEntry(entries, m['file']!, m['title'], baseUri);
    }
  }
  return entries;
}

void _playlistEntry(
  List<MediaEntry> entries,
  String value,
  String? title,
  String? base,
) {
  Uri? uri = Uri.tryParse(value);
  if (uri == null) return;
  if (!uri.hasScheme && !value.startsWith('/')) {
    final parent = base?.startsWith('/') == true
        ? Uri.file(base!)
        : Uri.tryParse(base ?? '');
    if (parent == null || !parent.hasScheme || parent.scheme == 'content') {
      return;
    }
    uri = parent.resolve(value);
    value = uri.toString();
  }
  if (uri.hasScheme &&
      !{
        'http',
        'https',
        'rtsp',
        'rtmp',
        'rtp',
        'udp',
        'smb',
        'ftp',
        'sftp',
        'nfs',
        'file',
        'content',
      }.contains(uri.scheme)) {
    return;
  }
  entries.add(
    MediaEntry(
      uri: value,
      title: (title?.isNotEmpty == true
          ? title!
          : uri.pathSegments.lastOrNull ?? value),
      audio: MediaEntry.isAudio(value),
    ),
  );
}

String exportM3u(List<MediaEntry> items) =>
    '#EXTM3U\n${items.map((m) => '#EXTINF:${m.duration ~/ 1000},${m.title.replaceAll(RegExp(r'[\r\n]'), ' ')}\n${m.uri.replaceAll(RegExp(r'[\r\n]'), '')}').join('\n')}\n';
