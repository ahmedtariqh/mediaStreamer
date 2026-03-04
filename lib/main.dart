import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/links_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/more_screen.dart';
import 'screens/player_screen.dart';
import 'services/database_service.dart';
import 'services/local_media_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Channel to receive VIEW intents (file URIs) from native Android
  static const _viewIntentChannel = MethodChannel(
    'com.mediastreamer/view_intent',
  );

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

    // Handle file VIEW intent from native side
    _viewIntentChannel.setMethodCallHandler((call) async {
      if (call.method == 'openFile') {
        final filePath = call.arguments as String?;
        if (filePath != null && filePath.isNotEmpty) {
          _openMediaFile(filePath);
        }
      }
    });

    // Check for initial VIEW intent on cold start
    _checkInitialViewIntent();

    // Check if we should show resume dialog
    _checkResumeOnStartup();
  }

  Future<void> _checkResumeOnStartup() async {
    // Small delay to let the UI settle
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final showResume = prefs.getBool('showResumeOnStartup') ?? true;
    if (!showResume) return;

    final lastPlayed = await DatabaseService.getLastPlayedMedia();
    if (lastPlayed == null) return;

    final filePath = lastPlayed['filePath'] as String;
    final title = lastPlayed['title'] as String;
    final positionMs = lastPlayed['positionMs'] as int;
    final durationMs = lastPlayed['durationMs'] as int;

    // Don't show if near the end (>95%)
    if (durationMs <= 0 || positionMs >= durationMs * 0.95) return;

    // Format the position for display
    final pos = Duration(milliseconds: positionMs);
    final dur = Duration(milliseconds: durationMs);
    String fmt(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      final s = d.inSeconds.remainder(60);
      if (h > 0) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
      }
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    final percent = (positionMs / durationMs * 100).toInt();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.play_circle_filled,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Continue Watching?')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: positionMs / durationMs,
                  minHeight: 6,
                  backgroundColor: Colors.white12,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${fmt(pos)} / ${fmt(dur)}  ($percent%)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Dismiss'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _openMediaFile(filePath);
              },
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('Resume'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkInitialViewIntent() async {
    try {
      final filePath = await _viewIntentChannel.invokeMethod<String>(
        'getInitialFile',
      );
      if (filePath != null && filePath.isNotEmpty) {
        // Delay to let the widget tree settle
        Future.delayed(const Duration(milliseconds: 500), () {
          _openMediaFile(filePath);
        });
      }
    } catch (_) {
      // No initial intent — that's fine
    }
  }

  void _openMediaFile(String filePath) {
    if (!mounted) return;

    final fileName = filePath.split('/').last;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PlayerScreen(filePath: filePath, title: fileName, youtubeUrl: ''),
      ),
    );
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

        // Navigate to home and auto-trigger format fetch
        setState(() => _currentIndex = 0);
        // Delay to ensure widget is built
        Future.delayed(const Duration(milliseconds: 300), () {
          _homeKey.currentState?.fetchAndPickFormatFromUrl(url);
        });
        break;
      }

      // Check if it's a local media file path
      if (LocalMediaService.isMediaExtension(
        text.substring(
          text.lastIndexOf('.') < 0 ? text.length : text.lastIndexOf('.'),
        ),
      )) {
        _openMediaFile(text);
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
          const LibraryScreen(),
          const LinksScreen(),
          const PlaylistsScreen(),
          const MoreScreen(),
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
              icon: Icon(Icons.video_library_outlined),
              activeIcon: Icon(Icons.video_library),
              label: 'Library',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.link_outlined),
              activeIcon: Icon(Icons.link),
              label: 'Links',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.playlist_play_outlined),
              activeIcon: Icon(Icons.playlist_play),
              label: 'Playlists',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz_outlined),
              activeIcon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}
