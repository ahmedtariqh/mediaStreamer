import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import '../models/video_note.dart';
import '../services/database_service.dart';
import 'library_actions.dart';
import 'media_entry.dart';
import 'media_preferences.dart';
import 'playback_controller.dart';

class MediaPlayerScreen extends StatefulWidget {
  final List<MediaEntry>? items;
  final int startIndex;
  const MediaPlayerScreen({super.key, this.items, this.startIndex = 0});
  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  final p = PlaybackController.instance, prefs = MediaPreferences.instance;
  bool _controls = true,
      _locked = false,
      _landscape = false,
      _handlingEnd = false,
      _opening = false;
  Timer? _hide;
  String? _completed, _hint;
  double _brightness = .6, _oldRate = 1, _gestureVolume = 100;
  int? _scrubMs;
  int _dragStart = 0;
  double _dragDistance = 0;
  @override
  void initState() {
    super.initState();
    _completed = p.state['completedUri'] as String?;
    p.addListener(_changed);
    _autoHide();
    _opening = widget.items != null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (widget.items != null && mounted) {
        try {
          await p.open(widget.items!, index: widget.startIndex);
        } catch (e) {
          if (mounted) LibraryActions.error(context, e);
        } finally {
          if (mounted) setState(() => _opening = false);
        }
      }
    });
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final completed = p.state['completedUri'] as String?;
    if (completed == null) _completed = null;
    if (completed != null && completed != _completed && !_handlingEnd) {
      _completed = completed;
      _handlingEnd = true;
      unawaited(prefs.markWatched(completed));
      final item = p.queue.where((m) => m.uri == completed).firstOrNull;
      if (item != null &&
          !item.audio &&
          p.queue.length == 1 &&
          prefs.controls['askNotes'] != false &&
          p.state['repeat'] != 'one') {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted) await _notes(item);
          _handlingEnd = false;
        });
      } else {
        _handlingEnd = false;
      }
    }
  }

  @override
  void dispose() {
    _hide?.cancel();
    p.removeListener(_changed);
    unawaited(_screenOn(false));
    unawaited(
      PlaybackController.channel
          .invokeMethod<void>('brightness', {'value': -1})
          .catchError((Object _) {}),
    );
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  bool? _lastScreenOn;
  Future<void> _screenOn(bool value) async {
    if (_lastScreenOn == value) return;
    _lastScreenOn = value;
    try {
      await PlaybackController.channel.invokeMethod('screenOn', {
        'value': value,
      });
    } catch (_) {}
  }

  void _autoHide() {
    _hide?.cancel();
    _hide = Timer(
      Duration(seconds: (prefs.controls['autoHide'] as num).toInt()),
      () {
        if (mounted && p.playing) setState(() => _controls = false);
      },
    );
  }

  void _show() {
    setState(() => _controls = true);
    _autoHide();
  }

  Future<void> _cmd(String name, [Map<String, dynamic> args = const {}]) async {
    try {
      await p.command(name, args);
    } catch (e) {
      if (mounted) LibraryActions.error(context, e);
    }
  }

  Future<void> _seek(int ms) async {
    try {
      await p.seek(ms);
    } catch (e) {
      if (mounted) LibraryActions.error(context, e);
    }
  }

  void _flash(String text) {
    setState(() => _hint = text);
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted && _hint == text) setState(() => _hint = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = p.current;
    final audio = p.audioOnly;
    unawaited(_screenOn(p.playing && !audio));
    final controls = !p.pip && (_controls || audio);
    return PopScope(
      canPop: !_locked,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _flash('Unlock controls to go back');
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!audio)
              const _VlcSurface()
            else if (MediaQuery.sizeOf(context).height >= 400)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: (MediaQuery.sizeOf(context).height * .25).clamp(
                          60,
                          220,
                        ),
                        height: (MediaQuery.sizeOf(context).height * .25).clamp(
                          60,
                          220,
                        ),
                        color: const Color(0xff151515),
                        child: Icon(
                          Icons.music_note,
                          size: (MediaQuery.sizeOf(context).height * .15).clamp(
                            36,
                            130,
                          ),
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        m?.title ?? 'No media',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 23),
                      ),
                    ],
                  ),
                ),
              ),
            if (!p.pip)
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (_locked) {
                    _show();
                  } else {
                    setState(() => _controls = !_controls);
                    _autoHide();
                  }
                },
                onDoubleTapDown: !_locked && prefs.controls['gestures'] == true
                    ? (details) {
                        final forward =
                            details.localPosition.dx >
                            MediaQuery.sizeOf(context).width / 2;
                        final seconds = (prefs.controls['skipSeconds'] as num)
                            .toInt();
                        _seek(p.position + (forward ? 1 : -1) * seconds * 1000);
                        _flash('${forward ? '+' : '−'}${seconds}s');
                      }
                    : null,
                onHorizontalDragStart:
                    !_locked && prefs.controls['gestures'] == true
                    ? (_) {
                        _dragStart = p.position;
                        _dragDistance = 0;
                      }
                    : null,
                onHorizontalDragUpdate:
                    !_locked && prefs.controls['gestures'] == true
                    ? (d) {
                        _dragDistance += d.delta.dx;
                        _flash(
                          mediaTime((_dragStart + _dragDistance * 500).round()),
                        );
                      }
                    : null,
                onHorizontalDragEnd:
                    !_locked && prefs.controls['gestures'] == true
                    ? (_) => _seek((_dragStart + _dragDistance * 500).round())
                    : null,
                onVerticalDragStart:
                    !_locked && prefs.controls['gestures'] == true
                    ? (_) {
                        _gestureVolume =
                            (p.state['volume'] as num?)?.toDouble() ?? 100;
                      }
                    : null,
                onVerticalDragUpdate:
                    !_locked && prefs.controls['gestures'] == true
                    ? (d) {
                        if (d.localPosition.dx <
                            MediaQuery.sizeOf(context).width / 2) {
                          _brightness = (_brightness - d.delta.dy / 250).clamp(
                            .01,
                            1,
                          );
                          PlaybackController.channel.invokeMethod(
                            'brightness',
                            {'value': _brightness},
                          );
                          _flash('Brightness ${(_brightness * 100).round()}%');
                        } else {
                          _gestureVolume = (_gestureVolume - d.delta.dy).clamp(
                            0,
                            200,
                          );
                          final v = _gestureVolume.round();
                          _cmd('volume', {'value': v});
                          _flash('Volume $v%');
                        }
                      }
                    : null,
                onLongPressStart: !_locked && prefs.controls['gestures'] == true
                    ? (_) {
                        _oldRate = p.rate;
                        _cmd('temporaryRate', {
                          'rate': prefs.controls['holdSpeed'],
                        });
                        _flash('${prefs.controls['holdSpeed']}×');
                      }
                    : null,
                onLongPressEnd: !_locked && prefs.controls['gestures'] == true
                    ? (_) => _cmd('temporaryRate', {'rate': _oldRate})
                    : null,
              ),
            if (_hint != null && !p.pip)
              Center(
                child: Card(
                  color: Colors.black87,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_hint!, style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            if ((_opening || p.state['buffering'] == true) && !p.pip)
              const Center(child: CircularProgressIndicator()),
            if (p.state['error'] != null && !p.pip)
              Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(p.state['error'].toString()),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _cmd('select', {'index': p.index}),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (controls && !_locked)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            Expanded(
                              child: Text(
                                m?.title ?? 'MediaStreamer',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Playback queue',
                              onPressed: _queue,
                              icon: const Icon(Icons.queue_music),
                            ),
                            IconButton(
                              tooltip: 'More options',
                              onPressed: _menu,
                              icon: const Icon(Icons.more_vert),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16, top: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.speed, size: 20),
                            label: Text('${p.rate.toStringAsFixed(2)}×'),
                            onPressed: _speed,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (controls && _locked)
              Positioned(
                top: 32,
                right: 16,
                child: SafeArea(
                  child: IconButton.filled(
                    tooltip: 'Unlock controls',
                    onPressed: () => setState(() => _locked = false),
                    icon: const Icon(Icons.lock_open),
                  ),
                ),
              ),
            if (controls && !_locked)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (audio)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  tooltip: 'Rewind 10 seconds',
                                  onPressed: () => _seek(p.position - 10000),
                                  icon: const Icon(Icons.replay_10),
                                ),
                                const SizedBox(width: 48),
                                IconButton(
                                  tooltip: 'Forward 10 seconds',
                                  onPressed: () => _seek(p.position + 10000),
                                  icon: const Icon(Icons.forward_10),
                                ),
                              ],
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(mediaTime(_scrubMs ?? p.position)),
                              Text(mediaTime(p.duration)),
                            ],
                          ),
                          Slider(
                            activeColor: Theme.of(context).colorScheme.primary,
                            inactiveColor: Colors.white24,
                            thumbColor: Theme.of(context).colorScheme.primary,
                            value: p.duration > 0
                                ? (_scrubMs ?? p.position)
                                      .clamp(0, p.duration)
                                      .toDouble()
                                : 0,
                            max: p.duration > 0 ? p.duration.toDouble() : 1,
                            onChangeStart: p.duration > 0
                                ? (_) {
                                    _hide?.cancel();
                                    setState(() => _scrubMs = p.position);
                                  }
                                : null,
                            onChanged: p.duration > 0
                                ? (v) => setState(() => _scrubMs = v.round())
                                : null,
                            onChangeEnd: p.duration > 0
                                ? (v) {
                                    _seek(v.round());
                                    setState(() => _scrubMs = null);
                                    _autoHide();
                                  }
                                : null,
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              IconButton(
                                tooltip: audio
                                    ? 'Shuffle'
                                    : 'Audio and subtitles',
                                onPressed: audio
                                    ? () => _cmd('shuffle', {
                                        'value': p.state['shuffle'] != true,
                                      })
                                    : _tracks,
                                icon: Icon(
                                  audio
                                      ? Icons.shuffle
                                      : Icons.subtitles_outlined,
                                  color: audio && p.state['shuffle'] == true
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                              IconButton(
                                tooltip: audio ? 'Previous' : 'Rotate',
                                onPressed: audio
                                    ? () => _cmd('previous')
                                    : _rotate,
                                icon: Icon(
                                  audio
                                      ? Icons.skip_previous
                                      : Icons.screen_rotation,
                                ),
                              ),
                              IconButton(
                                tooltip: p.playing ? 'Pause' : 'Play',
                                iconSize: 62,
                                onPressed: () => _cmd('toggle'),
                                icon: Icon(
                                  p.playing
                                      ? Icons.pause_circle_outline
                                      : Icons.play_circle_outline,
                                ),
                              ),
                              IconButton(
                                tooltip: audio ? 'Next' : 'Video size',
                                onPressed: audio ? () => _cmd('next') : _aspect,
                                icon: Icon(
                                  audio ? Icons.skip_next : Icons.fit_screen,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Repeat ${p.state['repeat'] ?? 'off'}',
                                onPressed: _repeat,
                                icon: Icon(
                                  p.state['repeat'] == 'one'
                                      ? Icons.repeat_one
                                      : Icons.repeat,
                                  color:
                                      p.state['repeat'] != 'off' &&
                                          p.state['repeat'] != null
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _rotate() async {
    _landscape = !_landscape;
    await SystemChrome.setPreferredOrientations(
      _landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
    _show();
  }

  Future<void> _sheet(String title, Widget content) async {
    _hide?.cancel();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xff262626),
      builder: (d) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(d).height * .88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    child: content,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) _autoHide();
  }

  Widget _option(IconData icon, String name, VoidCallback action) => ListTile(
    leading: Icon(icon),
    title: Text(name),
    onTap: () {
      Navigator.pop(context);
      action();
    },
  );
  Future<void> _menu() => _sheet(
    'Playback options',
    Column(
      children: [
        _option(
          Icons.lock_outline,
          'Lock',
          () => setState(() => _locked = true),
        ),
        _option(Icons.bedtime_outlined, 'Sleep timer', _sleep),
        _option(Icons.speed, 'Playback speed', _speed),
        _option(Icons.update, 'Jump to time', _jump),
        _option(Icons.equalizer, 'Equalizer', _equalizer),
        _option(
          Icons.music_note,
          p.audioOnly ? 'Play as video' : 'Play as audio',
          () => _cmd('audioOnly', {'value': !p.audioOnly}),
        ),
        _option(
          Icons.picture_in_picture_alt,
          'Pop-up player',
          () => _cmd('pip'),
        ),
        _option(Icons.repeat, 'Repeat mode', _repeat),
        _option(Icons.info_outline, 'Media information', _info),
        _option(Icons.bookmark_border, 'Bookmarks', _bookmarks),
        _option(Icons.repeat_on, 'A–B repeat', _ab),
        _option(
          Icons.playlist_add,
          'Save playlist',
          () => LibraryActions.savePlaylist(context, p.queue),
        ),
        _option(Icons.queue_music, 'Playback queue', _queue),
        _option(
          Icons.subtitles_outlined,
          'Audio, subtitles & chapters',
          _tracks,
        ),
        _option(Icons.cast, 'Cast to a renderer', _cast),
        _option(
          Icons.note_add_outlined,
          'Notes & finish watching',
          () => _notes(p.current!),
        ),
        _option(
          Icons.share,
          'Share track information',
          () => Share.share(
            '${p.current?.title}\n${p.current?.sourceUrl.isNotEmpty == true ? p.current!.sourceUrl : p.current?.uri}',
          ),
        ),
        _option(Icons.settings, 'Control settings', _settings),
        _option(Icons.tips_and_updates_outlined, 'Player tips', _tips),
      ],
    ),
  );
  Future<void> _sleep() async {
    var minutes = 30.0;
    var finish = false;
    await _sheet(
      'Sleep timer',
      StatefulBuilder(
        builder: (c, set) => Column(
          children: [
            Text(
              '${minutes.round()} minutes',
              style: const TextStyle(fontSize: 24),
            ),
            Slider(
              min: 1,
              max: 180,
              divisions: 179,
              value: minutes,
              onChanged: (v) => set(() => minutes = v),
            ),
            SwitchListTile(
              value: finish,
              onChanged: (v) => set(() => finish = v),
              title: const Text('Finish current track after timer expires'),
            ),
            if ((p.state['sleepUntil'] as num? ?? 0) > 0)
              Text(
                'Active until ${DateTime.fromMillisecondsSinceEpoch((p.state['sleepUntil'] as num).toInt()).toLocal()}',
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _cmd('sleep', {'minutes': 0});
                    Navigator.pop(c);
                  },
                  child: const Text('Cancel timer'),
                ),
                FilledButton(
                  onPressed: () {
                    _cmd('sleep', {
                      'minutes': minutes.round(),
                      'finishTrack': finish,
                    });
                    Navigator.pop(c);
                  },
                  child: const Text('Start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _speed() async {
    var speed = p.rate;
    var global = p.state['globalRate'] != false;
    await _sheet(
      'Playback speed',
      StatefulBuilder(
        builder: (c, set) {
          void apply(double value) {
            set(() => speed = value.clamp(.25, 8));
            _cmd('rate', {'rate': speed, 'global': global});
          }

          return Column(
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('This track')),
                  ButtonSegment(value: true, label: Text('All tracks')),
                ],
                selected: {global},
                onSelectionChanged: (v) {
                  set(() => global = v.first);
                  apply(speed);
                },
              ),
              const SizedBox(height: 20),
              Text(
                global
                    ? 'Apply speed to every track'
                    : 'Remember speed for this track',
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => apply(speed - .05),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    '${speed.toStringAsFixed(2)}×',
                    style: TextStyle(
                      fontSize: 30,
                      color: Theme.of(c).colorScheme.primary,
                    ),
                  ),
                  IconButton(
                    onPressed: () => apply(speed + .05),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Slider(
                value: speed,
                min: .25,
                max: 8,
                divisions: 155,
                onChanged: apply,
              ),
              Wrap(
                spacing: 10,
                children: [.8, 1.0, 1.25, 1.5, 2.0]
                    .map(
                      (v) => ActionChip(
                        label: Text('$v'),
                        onPressed: () => apply(v),
                      ),
                    )
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _jump() async {
    final value = await LibraryActions.text(
      context,
      'Jump to time',
      initial: mediaTime(p.position),
      hint: 'hh:mm:ss or mm:ss',
    );
    if (value == null || !mounted) return;
    final ms = parseMediaTime(value);
    if (ms == null || (p.duration > 0 && ms > p.duration)) {
      LibraryActions.error(
        context,
        'Enter a valid time within the media duration',
      );
      return;
    }
    await _seek(ms);
  }

  Future<void> _repeat() async {
    await _sheet(
      'Repeat mode',
      Column(
        children: ['off', 'one', 'all']
            .map(
              (v) => ListTile(
                title: Text(
                  {
                    'off': 'Off',
                    'one': 'Repeat current track',
                    'all': 'Repeat queue',
                  }[v]!,
                ),
                selected: (p.state['repeat'] ?? 'off') == v,
                trailing: Icon(
                  (p.state['repeat'] ?? 'off') == v
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                onTap: () {
                  _cmd('repeat', {'value': v});
                  Navigator.pop(context);
                },
              ),
            )
            .toList(),
      ),
    );
  }

  Future<void> _aspect() => _sheet(
    'Video size',
    Column(
      children: ['fit', 'fill', 'crop', '16:9', '4:3', '2.35:1', 'original']
          .map(
            (v) => ListTile(
              title: Text(v),
              onTap: () {
                _cmd('aspect', {'value': v});
                Navigator.pop(context);
              },
            ),
          )
          .toList(),
    ),
  );
  Future<void> _equalizer() async {
    var enabled = p.state['eqEnabled'] == true;
    var preamp = (p.state['eqPreamp'] as num?)?.toDouble() ?? 0;
    var bands = ((p.state['eqBands'] as List?) ?? List.filled(10, 0))
        .map((x) => (x as num).toDouble())
        .toList();
    final frequencies =
        (p.state['eqFrequencies'] as List?) ??
        [60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000];
    await _sheet(
      'Equalizer',
      StatefulBuilder(
        builder: (c, set) {
          void apply() {
            _cmd('equalizer', {
              'enabled': enabled,
              'bands': bands,
              'preamp': preamp,
            });
          }

          return Column(
            children: [
              SwitchListTile(
                title: const Text('Enable equalizer'),
                value: enabled,
                onChanged: (v) {
                  set(() => enabled = v);
                  apply();
                },
              ),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'Preset'),
                items: ((p.state['eqPresets'] as List?) ?? [])
                    .asMap()
                    .entries
                    .map(
                      (e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value.toString()),
                      ),
                    )
                    .toList(),
                onChanged: (i) async {
                  if (i == null) return;
                  await _cmd('equalizer', {'enabled': true, 'preset': i});
                  set(() {
                    enabled = true;
                    bands = (p.state['eqBands'] as List)
                        .map((x) => (x as num).toDouble())
                        .toList();
                    preamp = (p.state['eqPreamp'] as num).toDouble();
                  });
                },
              ),
              ListTile(
                title: const Text('Preamp'),
                subtitle: Slider(
                  value: preamp,
                  min: -20,
                  max: 20,
                  label: '${preamp.toStringAsFixed(1)} dB',
                  onChanged: (v) {
                    set(() => preamp = v);
                    apply();
                  },
                ),
              ),
              for (var i = 0; i < bands.length; i++)
                Row(
                  children: [
                    SizedBox(width: 60, child: Text('${frequencies[i]} Hz')),
                    Expanded(
                      child: Slider(
                        value: bands[i],
                        min: -20,
                        max: 20,
                        label: '${bands[i].toStringAsFixed(1)} dB',
                        onChanged: (v) {
                          set(() => bands[i] = v);
                          apply();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(bands[i].toStringAsFixed(1)),
                    ),
                  ],
                ),
              TextButton(
                onPressed: () {
                  set(() {
                    bands = List.filled(10, 0);
                    preamp = 0;
                  });
                  apply();
                },
                child: const Text('Reset'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _bookmarks() async {
    final m = p.current;
    if (m == null) return;
    await _sheet(
      'Bookmarks',
      ListenableBuilder(
        listenable: prefs,
        builder: (c, _) => Column(
          children: [
            FilledButton.icon(
              onPressed: () async {
                final pos = p.position;
                final name = await LibraryActions.text(
                  c,
                  'Bookmark name',
                  initial: mediaTime(pos),
                );
                if (name != null) await prefs.bookmark(m.uri, pos, name);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add current time'),
            ),
            ...(prefs.bookmarks[m.uri] ?? []).asMap().entries.map(
              (e) => ListTile(
                title: Text(e.value['title'].toString()),
                subtitle: Text(mediaTime(e.value['position'] as int)),
                onTap: () {
                  _seek(e.value['position'] as int);
                  Navigator.pop(c);
                },
                trailing: IconButton(
                  tooltip: 'Delete bookmark',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => prefs.removeBookmark(m.uri, e.key),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _ab() => _sheet(
    'A–B repeat',
    ListenableBuilder(
      listenable: p,
      builder: (c, _) => Column(
        children: [
          ListTile(
            title: Text(
              'A: ${(p.state['a'] as num? ?? -1) >= 0 ? mediaTime((p.state['a'] as num).toInt()) : 'Not set'}',
            ),
            trailing: FilledButton(
              onPressed: () => _cmd('ab', {'a': p.position, 'b': -1}),
              child: const Text('Set A'),
            ),
          ),
          ListTile(
            title: Text(
              'B: ${(p.state['b'] as num? ?? -1) >= 0 ? mediaTime((p.state['b'] as num).toInt()) : 'Not set'}',
            ),
            trailing: FilledButton(
              onPressed: () {
                final a = (p.state['a'] as num?)?.toInt() ?? -1;
                if (a < 0 || p.position <= a) {
                  LibraryActions.error(
                    c,
                    'Set A first, then seek to a later time for B',
                  );
                  return;
                }
                _cmd('ab', {'a': a, 'b': p.position});
              },
              child: const Text('Set B'),
            ),
          ),
          TextButton(
            onPressed: () => _cmd('ab', {'a': -1, 'b': -1}),
            child: const Text('Clear loop'),
          ),
        ],
      ),
    ),
  );
  Future<void> _tracks() => _sheet(
    'Tracks, subtitles & chapters',
    ListenableBuilder(
      listenable: p,
      builder: (c, _) => Column(
        children: [
          for (final type in ['audio', 'subtitle', 'video']) ...[
            ListTile(
              title: Text('${type[0].toUpperCase()}${type.substring(1)} track'),
            ),
            ...((p.state['${type}Tracks'] as List?) ?? []).map(
              (t) => ListTile(
                selected: t['id'] == p.state['${type}Track'],
                trailing: Icon(
                  t['id'] == p.state['${type}Track']
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(t['name'].toString()),
                onTap: () => _cmd('track', {'type': type, 'id': t['id']}),
              ),
            ),
          ],
          ListTile(
            leading: const Icon(Icons.file_open),
            title: const Text('Open subtitle file'),
            onTap: () async {
              try {
                final files = await p.pick('pickSubtitle');
                if (files.isNotEmpty) {
                  await _cmd('subtitle', {'uri': files.first.uri});
                }
              } catch (e) {
                if (c.mounted) LibraryActions.error(c, e);
              }
            },
          ),
          for (final type in ['audio', 'subtitle'])
            ListTile(
              title: Text('$type delay: ${p.state['${type}Delay'] ?? 0} ms'),
              onTap: () async {
                final value = await LibraryActions.text(
                  c,
                  '$type delay in milliseconds',
                  initial: '${p.state['${type}Delay'] ?? 0}',
                );
                if (value == null) return;
                final ms = int.tryParse(value);
                if (ms != null) await _cmd('delay', {'type': type, 'ms': ms});
              },
            ),
          ...((p.state['chapters'] as List?) ?? []).map(
            (ch) => ListTile(
              title: Text(ch['name']?.toString() ?? 'Chapter ${ch['index']}'),
              subtitle: Text(mediaTime((ch['time'] as num).toInt())),
              onTap: () => _cmd('chapter', {'index': ch['index']}),
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> _cast() async {
    await _cmd('discover');
    if (!mounted) return;
    await _sheet(
      'Cast to a renderer',
      ListenableBuilder(
        listenable: p,
        builder: (c, _) => Column(
          children: [
            const ListTile(
              subtitle: Text(
                'Keep both devices on the same Wi-Fi. Discovery can take a few seconds. Some formats require transcoding.',
              ),
            ),
            ListTile(
              title: const Text('This device'),
              onTap: () => _cmd('cast', {'id': ''}),
            ),
            if (((p.state['renderers'] as List?) ?? []).isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Searching for compatible renderers…'),
              ),
            ...((p.state['renderers'] as List?) ?? []).map(
              (r) => ListTile(
                leading: const Icon(Icons.cast),
                title: Text(r['name'].toString()),
                onTap: () => _cmd('cast', {'id': r['id']}),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _queue() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .8,
          child: ListenableBuilder(
            listenable: p,
            builder: (c, _) => Column(
              children: [
                ListTile(
                  title: const Text('Playback queue'),
                  trailing: IconButton(
                    tooltip: 'Add media',
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      try {
                        final items = await p.pick();
                        if (items.isNotEmpty) {
                          await _cmd('enqueue', {
                            'items': items.map((x) => x.toMap()).toList(),
                          });
                        }
                      } catch (e) {
                        if (c.mounted) LibraryActions.error(c, e);
                      }
                    },
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: p.queue.length,
                    onReorderItem: (from, to) =>
                        _cmd('move', {'from': from, 'to': to}),
                    itemBuilder: (c, i) {
                      final m = p.queue[i];
                      return ListTile(
                        key: ValueKey('$i:${m.uri}'),
                        leading: Icon(
                          i == p.index
                              ? Icons.equalizer
                              : m.audio
                              ? Icons.music_note
                              : Icons.movie,
                        ),
                        title: Text(
                          m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _cmd('select', {'index': i}),
                        trailing: Padding(
                          padding: const EdgeInsets.only(right: 32),
                          child: IconButton(
                            tooltip: 'Remove from queue',
                            icon: const Icon(Icons.close),
                            onPressed: () => _cmd('remove', {'index': i}),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: () => LibraryActions.savePlaylist(c, p.queue),
                      child: const Text('Save playlist'),
                    ),
                    TextButton(
                      onPressed: () =>
                          LibraryActions.exportPlaylist(c, p.queue),
                      child: const Text('Export M3U'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _info() {
    final m = p.current;
    return _sheet(
      'Media information',
      SelectableText(
        '${m?.title}\n\nLocation: ${m?.uri}\nDuration: ${mediaTime(p.duration)}\nPosition: ${mediaTime(p.position)}\nSize: ${((m?.size ?? 0) / 1048576).toStringAsFixed(1)} MB\nArtist: ${m?.artist}\nAlbum: ${m?.album}\nEngine: LibVLC 3.7.5\nSpeed: ${p.rate}×\nCodec details: ${p.state['mediaDetails']}\nAudio tracks: ${p.state['audioTracks']}\nVideo tracks: ${p.state['videoTracks']}\nSubtitles: ${p.state['subtitleTracks']}',
      ),
    );
  }

  Future<void> _notes(MediaEntry m) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Finish watching'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(m.title),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Your notes',
                  hintText: 'What would you like to remember?',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'keep'),
            child: const Text('Save & keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'delete'),
            child: const Text('Save & delete'),
          ),
        ],
      ),
    );
    if (result == null) {
      Future<void>.delayed(const Duration(seconds: 1), ctrl.dispose);
      return;
    }
    await DatabaseService.saveNote(
      VideoNote(
        youtubeUrl: m.sourceUrl.isNotEmpty ? m.sourceUrl : m.uri,
        title: m.title,
        notes: ctrl.text,
        dateWatched: DateTime.now(),
      ),
    );
    await prefs.markWatched(m.uri);
    if (result == 'delete' && mounted) {
      final deleted = await LibraryActions.delete(context, m);
      if (deleted && mounted) Navigator.pop(context);
    }
    Future<void>.delayed(const Duration(seconds: 1), ctrl.dispose);
  }

  Future<void> _settings() => _sheet(
    'Control settings',
    ListenableBuilder(
      listenable: prefs,
      builder: (c, _) => Column(
        children: [
          SwitchListTile(
            title: const Text('Ask for notes after a single video'),
            value: prefs.controls['askNotes'] != false,
            onChanged: (v) => prefs.settings({'askNotes': v}),
          ),
          SwitchListTile(
            title: const Text('Touch gestures'),
            subtitle: const Text('Seek, volume, brightness and hold for speed'),
            value: prefs.controls['gestures'] == true,
            onChanged: (v) => prefs.settings({'gestures': v}),
          ),
          SwitchListTile(
            title: const Text('Resume each track'),
            value: prefs.controls['resume'] == true,
            onChanged: (v) {
              prefs.settings({'resume': v});
              _cmd('settings', {'resume': v});
            },
          ),
          SwitchListTile(
            title: const Text('Automatic pop-up player'),
            subtitle: const Text(
              'Enter picture-in-picture when leaving the video player',
            ),
            value: prefs.controls['autoPip'] == true,
            onChanged: (v) {
              prefs.settings({'autoPip': v});
              _cmd('settings', {'autoPip': v});
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: (prefs.controls['skipSeconds'] as num).toInt(),
            decoration: const InputDecoration(
              labelText: 'Double-tap seek interval',
            ),
            items: [5, 10, 15, 30, 60]
                .map(
                  (v) => DropdownMenuItem(value: v, child: Text('$v seconds')),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) prefs.settings({'skipSeconds': v});
            },
          ),
          DropdownButtonFormField<double>(
            initialValue: (prefs.controls['holdSpeed'] as num).toDouble(),
            decoration: const InputDecoration(labelText: 'Hold playback speed'),
            items: [1.5, 2.0, 3.0, 4.0]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v×')))
                .toList(),
            onChanged: (v) {
              if (v != null) prefs.settings({'holdSpeed': v});
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: (prefs.controls['autoHide'] as num).toInt(),
            decoration: const InputDecoration(labelText: 'Hide controls after'),
            items: [2, 3, 4, 5, 8, 10]
                .map(
                  (v) => DropdownMenuItem(value: v, child: Text('$v seconds')),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) prefs.settings({'autoHide': v});
            },
          ),
          DropdownButtonFormField<String>(
            initialValue: prefs.controls['hardware'] as String,
            decoration: const InputDecoration(
              labelText: 'Decoder (next track / retry)',
            ),
            items: [
              'auto',
              'hardware',
              'software',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) {
              if (v != null) {
                prefs.settings({'hardware': v});
                _cmd('settings', {'hardware': v});
              }
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: (prefs.controls['networkCaching'] as num).toInt(),
            decoration: const InputDecoration(
              labelText: 'Network buffering (next track / retry)',
            ),
            items: [300, 1000, 1500, 3000, 5000, 10000]
                .map((v) => DropdownMenuItem(value: v, child: Text('$v ms')))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                prefs.settings({'networkCaching': v});
                _cmd('settings', {'networkCaching': v});
              }
            },
          ),
        ],
      ),
    ),
  );
  Future<void> _tips() => _sheet(
    'Player tips',
    const Text(
      '• Tap the video to show or hide controls.\n\n• Double-tap left or right to skip.\n\n• Drag horizontally to seek. Drag vertically on the left for brightness or on the right for volume.\n\n• Hold the video to temporarily increase speed.\n\n• Lock disables accidental touches. Use the unlock button to return.\n\n• Leave the player to keep listening and use the mini player on any page.\n\n• Reorder your queue by holding a row. Bookmarks remember exact times; A–B repeat loops a section.\n\n• Subtitle and audio delay values are milliseconds. Positive values delay the selected track.\n\n• Try software decoding and retry if a file does not play.',
    ),
  );
}

class _VlcSurface extends StatelessWidget {
  const _VlcSurface();
  @override
  Widget build(BuildContext context) => PlatformViewLink(
    viewType: 'mediastreamer/vlc',
    surfaceFactory: (c, controller) => AndroidViewSurface(
      controller: controller as AndroidViewController,
      gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    ),
    onCreatePlatformView: (params) =>
        PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: 'mediastreamer/vlc',
            layoutDirection: TextDirection.ltr,
          )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create(),
  );
}
