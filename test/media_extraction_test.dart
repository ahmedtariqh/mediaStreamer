import 'package:flutter_test/flutter_test.dart';
import 'package:media_streamer/models/stream_info_item.dart';
import 'package:media_streamer/services/native_download_service.dart';
import 'package:media_streamer/services/youtube_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeDownloadService.channel, null);
  });
  test(
    'maps social metadata and separate audio formats from the native engine',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeDownloadService.channel, (
            call,
          ) async {
            expect(call.method, 'extract');
            expect((call.arguments as Map)['url'], 'https://fb.watch/123/');
            return {
              'id': '123',
              'title': 'Facebook clip',
              'thumbnail': '',
              'formats': [
                {
                  'id': 'best',
                  'label': 'Best quality',
                  'audioOnly': false,
                  'container': 'MP4 / MKV',
                  'size': 0,
                },
                {
                  'id': 'audio-mp3',
                  'label': 'MP3 audio',
                  'audioOnly': true,
                  'container': 'MP3',
                  'size': 0,
                },
              ],
            };
          });
      final (video, formats) = await YoutubeService().getAvailableStreams(
        'Check this https://fb.watch/123/',
      );
      expect(video.title, 'Facebook clip');
      expect(formats[1].type, StreamType.audioOnly);
      expect(formats[1].formatId, 'audio-mp3');
      expect(formats[1].title, 'Facebook clip');
      expect(formats[0].fileSize, 'Size varies');
    },
  );
  test(
    'empty extractor responses fail visibly instead of opening an empty picker',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            NativeDownloadService.channel,
            (_) async => {'formats': []},
          );
      await expectLater(
        YoutubeService().getAvailableStreams('https://youtu.be/123'),
        throwsStateError,
      );
    },
  );
  test(
    'enqueue forwards a selected audio format without needing Flutter to own the task',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeDownloadService.channel, (
            call,
          ) async {
            expect(call.method, 'enqueue');
            expect((call.arguments as Map)['format'], 'audio-m4a');
            return null;
          });
      await NativeDownloadService().enqueue({
        'url': 'https://youtu.be/123',
        'format': 'audio-m4a',
      });
    },
  );
}
