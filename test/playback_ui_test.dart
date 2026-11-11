import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_streamer/app_theme.dart';
import 'package:media_streamer/playback/media_entry.dart';
import 'package:media_streamer/playback/media_library_screen.dart';
import 'package:media_streamer/playback/media_preferences.dart';
import 'package:media_streamer/playback/mini_player.dart';
import 'package:media_streamer/playback/playback_controller.dart';
import 'package:media_streamer/playback/player_screen.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MediaPreferences.instance.load();
    PlaybackController.instance.state = {};
  });
  testWidgets(
    'library searches Arabic titles and displays sort controls without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(709, 1536);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaLibraryScreen(
            audio: true,
            items: List.generate(
              220,
              (i) => MediaEntry(
                uri: '/Music/$i.m4a',
                title: i == 0 ? 'درس عربي' : 'Track $i',
                audio: true,
                duration: 840000,
                artist: 'Artist $i',
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'درس');
      await tester.pumpAndSettle();
      expect(find.text('درس عربي'), findsOneWidget);
      expect(find.text('Track 1'), findsNothing);
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Display settings'));
      await tester.pumpAndSettle();
      expect(find.text('Show only favorites'), findsOneWidget);
      expect(find.text('Insertion date'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'a persistent session shows exactly one mini player on nested tab pages',
    (tester) async {
      PlaybackController.instance.state = {
        'queue': [
          const MediaEntry(
            uri: '/a.mp3',
            title: 'Sample media',
            audio: true,
          ).toMap(),
        ],
        'index': 0,
        'visible': true,
        'playing': false,
        'position': 49000,
        'duration': 200000,
        'rate': 1.5,
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaScaffold(
            body: MediaScaffold(body: const Text('Browse')),
            bottomNavigationBar: const SizedBox(height: 60),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Sample media'), findsOneWidget);
      expect(find.text('0:49 · 1.50×'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('audio player renders and exposes VLC style playback options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(709, 1536);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    PlaybackController.instance.state = {
      'queue': [
        const MediaEntry(
          uri: '/a.m4a',
          title: 'انتحار مالي في العقارات وما هي البدائل؟',
          audio: true,
        ).toMap(),
      ],
      'index': 0,
      'visible': true,
      'playing': false,
      'audioOnly': true,
      'position': 27000,
      'duration': 853000,
      'rate': 1.5,
      'repeat': 'off',
    };
    if (Platform.environment['MEDIA_QA_DIR'] != null) {
      await tester.runAsync(() async {
        final text = FontLoader('TestText')
          ..addFont(
            Future.value(
              ByteData.sublistView(
                File(
                  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
                ).readAsBytesSync(),
              ),
            ),
          );
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await text.load();
        await icons.load();
      });
    }
    final theme = Platform.environment['MEDIA_QA_DIR'] != null
        ? AppTheme.darkTheme.copyWith(
            textTheme: AppTheme.darkTheme.textTheme.apply(
              fontFamily: 'TestText',
            ),
            primaryTextTheme: AppTheme.darkTheme.primaryTextTheme.apply(
              fontFamily: 'TestText',
            ),
          )
        : AppTheme.darkTheme;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RepaintBoundary(key: key, child: const MediaPlayerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1.50×'), findsOneWidget);
    expect(tester.takeException(), isNull);
    if (Platform.environment['MEDIA_QA_DIR'] != null) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '${Platform.environment['MEDIA_QA_DIR']}/audio-player.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    for (final title in [
      'Sleep timer',
      'Playback speed',
      'Equalizer',
      'Bookmarks',
      'A–B repeat',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets('seek scrubbing commits once and compact landscape audio fits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final p = PlaybackController.instance;
    p.state = {
      'queue': [
        const MediaEntry(
          uri: '/a.m4a',
          title: 'Long audio title',
          audio: true,
        ).toMap(),
      ],
      'index': 0,
      'visible': false,
      'audioOnly': true,
      'playing': false,
      'duration': 853000,
      'position': 27000,
      'rate': 1.5,
      'repeat': 'off',
    };
    final seeks = <int>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PlaybackController.channel,
      (call) async {
        if (call.method == 'seek') {
          seeks.add((call.arguments as Map)['position'] as int);
        }
        return call.method == 'snapshot' ? p.state : null;
      },
    );
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.darkTheme, home: const MediaPlayerScreen()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final slider = find.byType(Slider);
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    expect(seeks, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(seeks.length, 1);
    expect(seeks.single, inInclusiveRange(0, 853000));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      PlaybackController.channel,
      null,
    );
  });
  testWidgets('pages retain the bottom system inset without an active player', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 24)),
          child: MediaScaffold(body: const Text('Notes')),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MiniPlayer)).height, 24);
    expect(tester.takeException(), isNull);
  });
}
