import 'dart:io';
import 'package:flutter/material.dart';
import '../services/youtube_service.dart';
import '../widgets/video_tile.dart';
import 'player_screen.dart';
import 'stream_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  List<FileSystemEntity> _videos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    setState(() => _isLoading = true);
    final videos = await YoutubeService.getDownloadedVideos();
    setState(() {
      _videos = videos;
      _isLoading = false;
    });
  }

  String _extractTitle(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    // Remove videoId_ prefix and .mp4 suffix
    final withoutExt = fileName.replaceAll('.mp4', '');
    final underscoreIndex = withoutExt.indexOf('_');
    if (underscoreIndex != -1 && underscoreIndex < withoutExt.length - 1) {
      return withoutExt.substring(underscoreIndex + 1);
    }
    return withoutExt;
  }

  Future<void> _deleteVideo(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Video'),
        content: const Text('Are you sure you want to delete this video?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await YoutubeService.deleteVideo(path);
      await _loadVideos();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video deleted')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloads'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVideos,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
          ? _buildEmptyState(theme)
          : RefreshIndicator(
              onRefresh: _loadVideos,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _videos.length,
                itemBuilder: (context, index) {
                  final video = _videos[index];
                  final title = _extractTitle(video.path);

                  return VideoTile(
                    title: title,
                    filePath: video.path,
                    onPlay: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerScreen(
                            filePath: video.path,
                            title: title,
                            youtubeUrl: '',
                          ),
                        ),
                      ).then((_) => _loadVideos());
                    },
                    onStream: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              StreamScreen(filePath: video.path, title: title),
                        ),
                      );
                    },
                    onDelete: () => _deleteVideo(video.path),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.video_library_outlined,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Downloaded Videos',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Go to the Home tab and paste a YouTube\nlink to start downloading!',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
