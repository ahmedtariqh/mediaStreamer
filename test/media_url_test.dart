import 'package:flutter_test/flutter_test.dart';
import 'package:media_streamer/services/media_url.dart';

void main() {
  test('extracts a URL from multiline YouTube share text', () {
    expect(
      MediaUrl.extract(
        'Watch this!\nhttps://youtu.be/abc123?t=90\nSent from YouTube',
      ),
      'https://youtu.be/abc123?t=90',
    );
    expect(
      MediaUrl.extract('Video (https://m.youtube.com/shorts/abc123).'),
      'https://m.youtube.com/shorts/abc123',
    );
  });
  test('accepts social shortlinks and keeps signed query strings intact', () {
    for (final url in [
      'https://fb.watch/abcd/',
      'https://www.facebook.com/share/v/abc/',
      'https://www.instagram.com/reel/abc/',
      'https://vm.tiktok.com/abc/',
      'https://x.com/name/status/123',
      'https://vimeo.com/123',
    ]) {
      expect(MediaUrl.isSocialVideo(url), isTrue, reason: url);
    }
    expect(
      MediaUrl.require('https://cdn.example/video.mp4?sig=A%2FB&expires=123'),
      'https://cdn.example/video.mp4?sig=A%2FB&expires=123',
    );
  });
  test(
    'rejects invalid input and does not intercept lookalike domains or home pages',
    () {
      expect(MediaUrl.extract('not a link'), isNull);
      expect(
        () => MediaUrl.require('file:///etc/passwd'),
        throwsFormatException,
      );
      expect(
        MediaUrl.extract('https://user:password@example.com/video'),
        isNull,
      );
      for (final url in [
        'https://youtube.com.evil.example/watch?v=abc',
        'https://www.youtube.com/',
        'https://www.facebook.com/',
        'https://example.com/youtube.com/watch?v=abc',
      ]) {
        expect(MediaUrl.isSocialVideo(url), isFalse, reason: url);
      }
    },
  );
}
