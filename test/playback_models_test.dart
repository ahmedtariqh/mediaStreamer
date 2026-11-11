import 'package:flutter_test/flutter_test.dart';
import 'package:media_streamer/playback/media_entry.dart';
import 'package:media_streamer/playback/media_catalog.dart';

void main() {
  test('jump to time rejects invalid fields and supports long media', () {
    expect(parseMediaTime('1:02:03'), 3723000);
    expect(parseMediaTime('42:59'), 2579000);
    expect(parseMediaTime('90'), 90000);
    for (final bad in ['-1', '1:60', '1:01:60', '1::2', '1.5', '1:2:3:4', '']) {
      expect(parseMediaTime(bad), isNull, reason: bad);
    }
    expect(mediaTime(3723000), '1:02:03');
    expect(mediaTime(-1), '0:00');
  });
  test(
    'M3U imports titles and resolves relative URLs without treating directives as media',
    () {
      final m = parsePlaylist(
        '#EXTM3U\n#EXTVLCOPT:http-referrer=bad\n#EXTINF:42,درس عربي\nclip.mp4\nhttps://example.org/audio.m4a?token=one\njavascript:alert(1)\n',
        baseUri: 'https://example.org/folder/list.m3u',
      );
      expect(m.length, 2);
      expect(m.first.uri, 'https://example.org/folder/clip.mp4');
      expect(m.first.title, 'درس عربي');
      expect(m.last.audio, isTrue);
    },
  );
  test('content document playlists require resolvable absolute paths', () {
    final m = parsePlaylist(
      'relative.mp4\n/storage/Movies/owned.mp4\nhttps://example.org/file.mp4',
      baseUri: 'content://documents/17',
    );
    expect(m.length, 2);
  });
  test('relative local playlists resolve against a real file path', () {
    expect(
      parsePlaylist('audio.mp3', baseUri: '/Music/list.m3u').single.uri,
      'file:///Music/audio.mp3',
    );
  });
  test('PLS respects numeric ordering, metadata and unsafe scheme filtering', () {
    final m = parsePlaylist(
      '[playlist]\nFile2=https://example.org/two.mp3\nTitle2=Second\nFile1=https://example.org/one.mp4\nTitle1=First\nNumberOfEntries=2\nFile3=data:malicious',
    );
    expect(m.map((x) => x.title), ['First', 'Second']);
    expect(m.last.audio, isTrue);
  });
  test('M3U export strips line injection and round-trips Arabic titles', () {
    const m = MediaEntry(
      uri: '/storage/a.mp4',
      title: 'اختبار\n#EXTVLCOPT:evil',
      duration: 42000,
    );
    final text = exportM3u([m]);
    expect(text.split('\n').where((x) => x.startsWith('#EXTVLCOPT')), isEmpty);
    expect(parsePlaylist(text).single.uri, m.uri);
  });
  test(
    'catalog sorting does not mutate source, supports duration and deterministic ties',
    () {
      final items = [
        const MediaEntry(uri: '/b/2.mp4', title: 'B', duration: 10, added: 2),
        const MediaEntry(uri: '/a/1.mp4', title: 'A', duration: 20, added: 1),
      ];
      expect(sortMedia(items, CatalogSort.duration).first.title, 'B');
      expect(
        sortMedia(items, CatalogSort.added, descending: true).first.title,
        'B',
      );
      expect(sortMedia(items, CatalogSort.name).first.title, 'A');
      expect(items.first.title, 'B');
    },
  );
  test('folder and album grouping retain media identity', () {
    final items = [
      const MediaEntry(uri: '/Movies/a.mp4', title: 'A', album: 'Album'),
      const MediaEntry(uri: '/Movies/b.mp4', title: 'B', album: 'Album'),
      const MediaEntry(uri: '/Download/c.mp4', title: 'C'),
    ];
    expect(groupMedia(items, 'folder')['/Movies']!.length, 2);
    expect(groupMedia(items, 'album')['Album']!.length, 2);
    expect(groupMedia(items, 'artist')['Unknown']!.length, 3);
  });
  test('MediaStore and queue metadata survive serialization', () {
    final m = MediaEntry.fromMap({
      'path': '/a.mp3',
      'name': 'a.mp3',
      'title': 'Title',
      'isVideo': false,
      'duration': 234,
      'contentUri': 'content://media/7',
      'artist': 'Artist',
    });
    final copy = MediaEntry.fromMap(m.toMap());
    expect(copy.audio, isTrue);
    expect(copy.contentUri, 'content://media/7');
    expect(copy.artist, 'Artist');
    expect(copy.duration, 234);
  });
}
