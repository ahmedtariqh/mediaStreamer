import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../models/video_note.dart';
import '../services/database_service.dart';
import '../services/youtube_service.dart';
import '../widgets/post_watch_dialog.dart';

class PlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final String youtubeUrl;

  const PlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    required this.youtubeUrl,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;

  bool _hasShownDialog = false;
  bool _isPlaying = false;
  bool _isInitialized = false;
  bool _isLocked = false;
  bool _controlsVisible = true;
  double _playbackSpeed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _hideTimer;
  Timer? _positionTimer;

  // Error state
  bool _hasError = false;
  String _errorMessage = '';

  // Gesture state
  bool _isDraggingVolume = false;
  bool _isDraggingBrightness = false;
  bool _isDraggingSeek = false;
  double _dragStartY = 0;
  double _dragStartX = 0;
  double _dragStartValue = 0;
  double _currentVolume = 1.0;
  double _currentBrightness = 0.5;
  Duration _seekTarget = Duration.zero;
  String? _gestureText;
  IconData? _gestureIcon;

  // Double-tap seek
  int _doubleTapSide = 0;
  Timer? _doubleTapTimer;
  int _doubleTapCount = 0;

  static const _speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 3.0];

  // Position save counter (save every ~5 seconds)
  int _positionSaveCounter = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);

    _initPlayer();
    _resetHideTimer();
  }

  void _initPlayer() {
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _isInitialized = false;
    });

    final effectivePath = widget.filePath;

    try {
      if (effectivePath.startsWith('http')) {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(effectivePath),
        );
      } else {
        // Check if the file exists
        final file = File(effectivePath);
        if (!file.existsSync()) {
          setState(() {
            _hasError = true;
            _errorMessage = 'File not found:\n$effectivePath';
          });
          return;
        }
        _controller = VideoPlayerController.file(file);
      }

      _controller!
          .initialize()
          .then((_) async {
            if (!mounted) return;
            setState(() {
              _isInitialized = true;
              _duration = _controller!.value.duration;
            });

            // Check if we should resume from saved position
            final prefs = await SharedPreferences.getInstance();
            final resumeEnabled = prefs.getBool('resumePlayback') ?? true;
            if (resumeEnabled) {
              final saved = await DatabaseService.getPlaybackPosition(
                widget.filePath,
              );
              if (saved != null) {
                final savedPos = Duration(
                  milliseconds: saved['positionMs'] as int,
                );
                final savedDur = Duration(
                  milliseconds: saved['durationMs'] as int,
                );
                // Only resume if not near the end (within 95%)
                if (savedPos.inMilliseconds < savedDur.inMilliseconds * 0.95) {
                  await _controller!.seekTo(savedPos);
                  if (mounted) {
                    setState(() => _position = savedPos);
                  }
                }
              }
            }

            _controller!.play();
            _controller!.addListener(_onPlayerEvent);
            _startPositionPolling();
          })
          .catchError((error) {
            if (mounted) {
              setState(() {
                _hasError = true;
                _errorMessage =
                    'Could not play this file.\n${error.toString()}';
              });
            }
          });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = 'Player error: ${e.toString()}';
      });
    }
  }

  void _startPositionPolling() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || !_isInitialized || _controller == null) return;
      final value = _controller!.value;
      setState(() {
        _position = value.position;
        _isPlaying = value.isPlaying;
      });

      // Save position every ~5 seconds (10 ticks × 500ms)
      _positionSaveCounter++;
      if (_positionSaveCounter >= 10) {
        _positionSaveCounter = 0;
        _saveCurrentPosition();
      }

      // Check for completion
      if (_duration.inSeconds > 0 &&
          value.position.inSeconds >= _duration.inSeconds - 1 &&
          !_hasShownDialog &&
          !value.isPlaying) {
        _hasShownDialog = true;
        _showPostWatchDialog();
      }
    });
  }

  Future<void> _saveCurrentPosition() async {
    if (_controller == null || !_isInitialized) return;
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    if (dur.inMilliseconds <= 0) return;
    await DatabaseService.savePlaybackPosition(
      filePath: widget.filePath,
      positionMs: pos.inMilliseconds,
      durationMs: dur.inMilliseconds,
      title: widget.title,
    );
  }

  void _onPlayerEvent() {
    if (!mounted || _controller == null) return;
    final value = _controller!.value;

    if (value.hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = value.errorDescription ?? 'Unknown playback error';
      });
    }
  }

  void _retryPlayer() {
    _positionTimer?.cancel();
    _controller?.removeListener(_onPlayerEvent);
    _controller?.dispose();
    _controller = null;
    _initPlayer();
    _resetHideTimer();
  }

  @override
  void dispose() {
    // Save position one last time before disposing
    _saveCurrentPosition();
    _hideTimer?.cancel();
    _positionTimer?.cancel();
    _doubleTapTimer?.cancel();
    _controller?.removeListener(_onPlayerEvent);
    _controller?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (_controlsVisible && !_isLocked) {
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isPlaying) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _resetHideTimer();
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _controlsVisible = false;
      } else {
        _controlsVisible = true;
        _resetHideTimer();
      }
    });
  }

  void _togglePlay() {
    if (_controller == null) return;
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() => _isPlaying = !_isPlaying);
    _resetHideTimer();
  }

  Future<void> _seekTo(Duration position) async {
    if (_controller == null) return;
    final clamped = Duration(
      milliseconds: position.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    await _controller!.seekTo(clamped);
    setState(() => _position = clamped);
  }

  void _setSpeed(double speed) {
    if (_controller == null) return;
    setState(() => _playbackSpeed = speed);
    _controller!.setPlaybackSpeed(speed);
  }

  // --- Gesture Handling ---

  void _onVerticalDragStart(DragStartDetails details, double screenWidth) {
    if (_isLocked) return;
    final x = details.globalPosition.dx;
    _dragStartY = details.globalPosition.dy;
    if (x < screenWidth / 2) {
      _isDraggingBrightness = true;
      _dragStartValue = _currentBrightness;
    } else {
      _isDraggingVolume = true;
      _dragStartValue = _currentVolume;
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details, double screenHeight) {
    if (_isLocked || _controller == null) return;
    final dy = _dragStartY - details.globalPosition.dy;
    final delta = dy / (screenHeight * 0.6);

    if (_isDraggingVolume) {
      final newVol = (_dragStartValue + delta).clamp(0.0, 1.0);
      _controller!.setVolume(newVol);
      setState(() {
        _currentVolume = newVol;
        final pct = (newVol * 100).toInt();
        _gestureIcon = newVol == 0
            ? Icons.volume_off
            : newVol < 0.5
            ? Icons.volume_down
            : Icons.volume_up;
        _gestureText = '$pct%';
      });
    } else if (_isDraggingBrightness) {
      final newBright = (_dragStartValue + delta).clamp(0.0, 1.0);
      setState(() {
        _currentBrightness = newBright;
        final pct = (newBright * 100).toInt();
        _gestureIcon = newBright < 0.3
            ? Icons.brightness_low
            : newBright < 0.7
            ? Icons.brightness_medium
            : Icons.brightness_high;
        _gestureText = '$pct%';
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    setState(() {
      _isDraggingVolume = false;
      _isDraggingBrightness = false;
      _gestureText = null;
      _gestureIcon = null;
    });
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (_isLocked) return;
    _isDraggingSeek = true;
    _dragStartX = details.globalPosition.dx;
    _seekTarget = _position;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details, double screenWidth) {
    if (_isLocked || !_isDraggingSeek) return;
    final dx = details.globalPosition.dx - _dragStartX;
    final seekDelta = Duration(
      seconds: (dx / screenWidth * _duration.inSeconds * 0.5).toInt(),
    );
    final target = Duration(
      milliseconds: (_position.inMilliseconds + seekDelta.inMilliseconds).clamp(
        0,
        _duration.inMilliseconds,
      ),
    );
    setState(() {
      _seekTarget = target;
      _gestureIcon = dx > 0 ? Icons.fast_forward : Icons.fast_rewind;
      _gestureText = _formatDuration(_seekTarget);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isDraggingSeek) {
      _seekTo(_seekTarget);
    }
    setState(() {
      _isDraggingSeek = false;
      _gestureText = null;
      _gestureIcon = null;
    });
  }

  void _handleDoubleTap(TapDownDetails details, double screenWidth) {
    if (_isLocked) return;
    final x = details.globalPosition.dx;
    final side = x < screenWidth / 2 ? -1 : 1;

    if (_doubleTapSide == side) {
      _doubleTapCount++;
    } else {
      _doubleTapSide = side;
      _doubleTapCount = 1;
    }

    final seekAmount = Duration(seconds: 10 * _doubleTapCount);
    if (side == -1) {
      _seekTo(_position - seekAmount);
      setState(() {
        _gestureIcon = Icons.fast_rewind;
        _gestureText = '-${seekAmount.inSeconds}s';
      });
    } else {
      _seekTo(_position + seekAmount);
      setState(() {
        _gestureIcon = Icons.fast_forward;
        _gestureText = '+${seekAmount.inSeconds}s';
      });
    }

    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(const Duration(milliseconds: 800), () {
      _doubleTapCount = 0;
      _doubleTapSide = 0;
      if (mounted) {
        setState(() {
          _gestureText = null;
          _gestureIcon = null;
        });
      }
    });
  }

  void _showSpeedPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Playback Speed', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._speeds.map((speed) {
                final isSelected = speed == _playbackSpeed;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : Colors.white24,
                    size: 22,
                  ),
                  title: Text(
                    '${speed}x',
                    style: TextStyle(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : Colors.white70,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: speed == 1.0
                      ? Text(
                          'Normal',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white38,
                          ),
                        )
                      : null,
                  onTap: () {
                    _setSpeed(speed);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Extract YouTube URL from downloaded filename pattern: {videoId}_{title}.ext
  String _resolveYoutubeUrl() {
    if (widget.youtubeUrl.isNotEmpty) return widget.youtubeUrl;
    // Try extracting from filename
    final fileName = widget.filePath.split(Platform.pathSeparator).last;
    final underscoreIndex = fileName.indexOf('_');
    if (underscoreIndex > 0) {
      final videoId = fileName.substring(0, underscoreIndex);
      // YouTube IDs are typically 11 chars
      if (videoId.length >= 10 && videoId.length <= 12) {
        return 'https://youtube.com/watch?v=$videoId';
      }
    }
    return '';
  }

  /// Clean title by stripping videoId prefix and file extension.
  String _resolveTitle() {
    final fileName = widget.filePath.split(Platform.pathSeparator).last;
    // Strip extension
    var clean = fileName.replaceAll(
      RegExp(r'\.(mp4|webm|m4a|mkv|avi)$', caseSensitive: false),
      '',
    );
    // Strip videoId prefix (pattern: videoId_title)
    final underscoreIndex = clean.indexOf('_');
    if (underscoreIndex > 0) {
      final possibleId = clean.substring(0, underscoreIndex);
      if (possibleId.length >= 10 && possibleId.length <= 12) {
        clean = clean.substring(underscoreIndex + 1);
      }
    }
    // If we ended up with something useful, use it; otherwise use original title
    return clean.isNotEmpty ? clean : widget.title;
  }

  Future<void> _showPostWatchDialog() async {
    if (!mounted) return;

    final resolvedUrl = _resolveYoutubeUrl();
    final resolvedTitle = _resolveTitle();

    final result = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          PostWatchDialog(videoTitle: resolvedTitle, youtubeUrl: resolvedUrl),
    );

    if (result == null) return;

    final action = result['action'];
    final notes = result['notes'] ?? '';

    if (action == 'save' || action == 'save_keep') {
      final note = VideoNote(
        youtubeUrl: resolvedUrl,
        title: resolvedTitle,
        notes: notes,
        dateWatched: DateTime.now(),
      );
      await DatabaseService.saveNote(note);

      if (action == 'save') {
        // Save notes AND delete video
        try {
          await YoutubeService.deleteVideo(widget.filePath);
        } catch (e) {
          debugPrint('Delete failed: $e');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notes saved, video deleted')),
          );
          Navigator.pop(context);
        }
      } else {
        // save_keep: Save notes, keep video
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Notes saved')));
        }
      }
    } else if (action == 'delete') {
      try {
        await YoutubeService.deleteVideo(widget.filePath);
      } catch (e) {
        debugPrint('Delete failed: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video deleted')));
        Navigator.pop(context);
      }
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video Player
          if (_controller != null && _isInitialized && !_hasError)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),

          // Error state
          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Playback Error',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.filePath,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Go Back'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: _retryPlayer,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // Gesture detection layer
          if (!_hasError)
            Positioned.fill(
              child: GestureDetector(
                onTap: _isLocked ? null : _toggleControls,
                onDoubleTapDown: (details) =>
                    _handleDoubleTap(details, screenSize.width),
                onDoubleTap: () {},
                onVerticalDragStart: (d) =>
                    _onVerticalDragStart(d, screenSize.width),
                onVerticalDragUpdate: (d) =>
                    _onVerticalDragUpdate(d, screenSize.height),
                onVerticalDragEnd: _onVerticalDragEnd,
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: (d) =>
                    _onHorizontalDragUpdate(d, screenSize.width),
                onHorizontalDragEnd: _onHorizontalDragEnd,
                behavior: HitTestBehavior.translucent,
                child: Container(color: Colors.transparent),
              ),
            ),

          // Gesture overlay indicator
          if (_gestureText != null)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_gestureIcon != null)
                      Icon(_gestureIcon, color: Colors.white, size: 36),
                    const SizedBox(height: 6),
                    Text(
                      _gestureText!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Locked indicator
          if (_isLocked)
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _toggleLock,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, color: Colors.white70, size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Tap to unlock',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Controls overlay
          if (_controlsVisible && !_isLocked && !_hasError)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    stops: const [0.0, 0.2, 0.7, 1.0],
                  ),
                ),
                child: Column(
                  children: [
                    // Top bar
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Speed
                            TextButton(
                              onPressed: _showSpeedPicker,
                              child: Text(
                                '${_playbackSpeed}x',
                                style: TextStyle(
                                  color: _playbackSpeed != 1.0
                                      ? theme.colorScheme.secondary
                                      : Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            // Notes
                            IconButton(
                              icon: const Icon(
                                Icons.note_add,
                                color: Colors.white70,
                              ),
                              onPressed: () {
                                _controller?.pause();
                                _showPostWatchDialog();
                              },
                              tooltip: 'Add notes',
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Center play/pause + seek buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: () =>
                              _seekTo(_position - const Duration(seconds: 10)),
                          icon: const Icon(
                            Icons.replay_10,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 24),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          child: IconButton(
                            onPressed: _togglePlay,
                            iconSize: 52,
                            icon: Icon(
                              _isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        IconButton(
                          onPressed: () =>
                              _seekTo(_position + const Duration(seconds: 10)),
                          icon: const Icon(
                            Icons.forward_10,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),

                    // Bottom bar with seekbar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                              activeTrackColor: theme.colorScheme.primary,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: theme.colorScheme.primary,
                              overlayColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.3),
                            ),
                            child: Slider(
                              value: _duration.inMilliseconds > 0
                                  ? _position.inMilliseconds
                                        .clamp(0, _duration.inMilliseconds)
                                        .toDouble()
                                  : 0,
                              max: _duration.inMilliseconds > 0
                                  ? _duration.inMilliseconds.toDouble()
                                  : 1,
                              onChanged: (value) {
                                _seekTo(Duration(milliseconds: value.toInt()));
                              },
                              onChangeStart: (_) {
                                _hideTimer?.cancel();
                              },
                              onChangeEnd: (_) {
                                _resetHideTimer();
                              },
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                _formatDuration(_position),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                ' / ${_formatDuration(_duration)}',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(
                                  Icons.lock_outline,
                                  color: Colors.white70,
                                  size: 20,
                                ),
                                onPressed: _toggleLock,
                                tooltip: 'Lock controls',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Loading indicator
          if (!_isInitialized && !_hasError)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    'Loading video...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
