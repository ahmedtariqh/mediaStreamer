import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/download_task.dart';
import '../models/stream_info_item.dart';
import '../services/youtube_service.dart';
import '../widgets/download_progress_tile.dart';
import '../widgets/format_picker_sheet.dart';

class HomeScreen extends StatefulWidget {
  final TextEditingController? urlController;

  const HomeScreen({super.key, this.urlController});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TextEditingController _urlController;
  final _youtubeService = YoutubeService();
  bool _isFetching = false;
  bool _isDownloading = false;
  DownloadTask? _activeDownload;
  String? _errorMessage;

  // Download stats
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  double _downloadSpeed = 0;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _urlController = widget.urlController ?? TextEditingController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    if (widget.urlController == null) _urlController.dispose();
    _youtubeService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void setUrl(String url) {
    _urlController.text = url;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _urlController.text = data!.text!;
    }
  }

  Future<void> _fetchAndPickFormat() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Please enter a YouTube URL');
      return;
    }

    setState(() {
      _isFetching = true;
      _errorMessage = null;
    });

    try {
      final (video, streams) = await _youtubeService.getAvailableStreams(url);

      if (!mounted) return;
      setState(() => _isFetching = false);

      // Show format picker
      final selected = await showModalBottomSheet<StreamInfoItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => FormatPickerSheet(
          videoTitle: video.title,
          thumbnailUrl: video.thumbnails.highResUrl,
          streams: streams,
        ),
      );

      if (selected != null && mounted) {
        _startDownload(url, selected);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetching = false;
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _startDownload(String url, StreamInfoItem stream) async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _downloadedBytes = 0;
      _totalBytes = stream.sizeBytes;
      _downloadSpeed = 0;
      _activeDownload = DownloadTask(
        videoId: '',
        title: 'Downloading...',
        thumbnailUrl: '',
        youtubeUrl: url,
        status: DownloadStatus.downloading,
      );
    });

    try {
      final task = await _youtubeService.downloadStream(
        url,
        stream,
        onProgress: (progress, downloaded, total, speed) {
          if (mounted) {
            setState(() {
              _activeDownload = _activeDownload?..progress = progress;
              _downloadedBytes = downloaded;
              _totalBytes = total;
              _downloadSpeed = speed;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _activeDownload = task;
          _isDownloading = false;
        });

        if (task.status == DownloadStatus.completed) {
          _urlController.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded: ${task.title}'),
              backgroundColor: Colors.green.shade700,
            ),
          );
        } else if (task.status == DownloadStatus.failed) {
          setState(
            () => _errorMessage = task.errorMessage ?? 'Download failed',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBusy = _isFetching || _isDownloading;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              ).createShader(bounds),
              child: const Icon(Icons.stream, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 10),
            const Text('MediaStreamer'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            // Hero section
            Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) =>
                    Transform.scale(scale: _pulseAnimation.value, child: child),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.download_rounded,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Download & Stream',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Paste a YouTube link to choose format\nand download in your preferred quality',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white54,
              ),
            ),

            const SizedBox(height: 32),

            // URL input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: 'Paste YouTube URL...',
                      prefixIcon: Icon(
                        Icons.link,
                        color: theme.colorScheme.primary,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste),
                        onPressed: _pasteFromClipboard,
                        tooltip: 'Paste from clipboard',
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Fetch / Download button
            ElevatedButton.icon(
              onPressed: isBusy ? null : _fetchAndPickFormat,
              icon: isBusy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(
                _isFetching
                    ? 'Fetching formats...'
                    : _isDownloading
                    ? 'Downloading...'
                    : 'Fetch & Choose Format',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            // Error message
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Active download progress
            if (_activeDownload != null &&
                _activeDownload!.status == DownloadStatus.downloading) ...[
              const SizedBox(height: 20),
              DownloadProgressTile(
                title: _activeDownload!.title,
                progress: _activeDownload!.progress,
                downloadedBytes: _downloadedBytes,
                totalBytes: _totalBytes,
                speed: _downloadSpeed,
              ),
            ],

            const SizedBox(height: 40),

            // Quick tips section
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tips_and_updates,
                        color: theme.colorScheme.secondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Quick Tips',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _tipItem(
                    Icons.share,
                    'Share a YouTube link from the YouTube app to download here',
                  ),
                  const SizedBox(height: 8),
                  _tipItem(
                    Icons.high_quality,
                    'Choose between audio-only, 720p, 1080p, and more',
                  ),
                  const SizedBox(height: 8),
                  _tipItem(
                    Icons.cast,
                    'Stream to other devices via the Stream tab',
                  ),
                  const SizedBox(height: 8),
                  _tipItem(
                    Icons.note_add,
                    'Save notes after watching — video auto-deletes',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white54),
          ),
        ),
      ],
    );
  }
}
