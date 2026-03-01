import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/notes_screen.dart';
import 'screens/stream_screen.dart';
import 'screens/receiver_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const MediaStreamerApp());
}

class MediaStreamerApp extends StatelessWidget {
  const MediaStreamerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediaStreamer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  late StreamSubscription _intentSub;

  @override
  void initState() {
    super.initState();

    // Handle share intent when app is already running
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> files) {
        _handleSharedFiles(files);
      },
      onError: (err) {
        debugPrint('Share intent stream error: $err');
      },
    );

    // Handle share intent when app is launched via share
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleSharedFiles(files);
    });
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    for (final file in files) {
      final text = file.path;
      // Check if the shared text contains a YouTube URL
      if (text.contains('youtube.com') ||
          text.contains('youtu.be') ||
          text.contains('youtube')) {
        // Extract URL from shared text (may contain extra text)
        final urlMatch = RegExp(
          r'(https?://(?:www\.)?(?:youtube\.com|youtu\.be)[^\s]+)',
        ).firstMatch(text);
        final url = urlMatch?.group(0) ?? text;

        // Navigate to home and set URL
        setState(() => _currentIndex = 0);
        // Delay to ensure widget is built
        Future.delayed(const Duration(milliseconds: 300), () {
          _homeKey.currentState?.setUrl(url);
        });
        break;
      }
    }
  }

  @override
  void dispose() {
    _intentSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          HomeScreen(key: _homeKey),
          const DownloadsScreen(),
          const NotesScreen(),
          const StreamScreen(),
          const ReceiverScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.download_outlined),
              activeIcon: Icon(Icons.download),
              label: 'Downloads',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.note_outlined),
              activeIcon: Icon(Icons.note),
              label: 'Notes',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.cast_outlined),
              activeIcon: Icon(Icons.cast_connected),
              label: 'Stream',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.download_for_offline_outlined),
              activeIcon: Icon(Icons.download_for_offline),
              label: 'Receive',
            ),
          ],
        ),
      ),
    );
  }
}
