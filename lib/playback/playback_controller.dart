import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import '../services/database_service.dart';
import 'media_entry.dart';
import 'media_preferences.dart';

class PlaybackController extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = PlaybackController._();
  PlaybackController._();
  static const channel = MethodChannel('com.mediastreamer/player');
  Map<String, dynamic> state = {};
  bool pip = false, _busy = false, _foreground = true;
  Timer? _poller;
  int _lastSave = 0, _pollTicks = 0;
  String? actionError;
  Map<String, dynamic>? _queueState;
  List<MediaEntry> _queueCache = const [];
  List<MediaEntry> get queue {
    if (!identical(_queueState, state)) {
      _queueCache = ((state['queue'] as List?) ?? [])
          .map((x) => MediaEntry.fromMap(x as Map))
          .toList(growable: false);
      _queueState = state;
    }
    return _queueCache;
  }

  int get index => (state['index'] as num?)?.toInt() ?? 0;
  MediaEntry? get current => queue.elementAtOrNull(index);
  bool get playing => state['playing'] == true;
  bool get visible => state['visible'] == true && current != null;
  bool get audioOnly => state['audioOnly'] == true || current?.audio == true;
  int get position => (state['position'] as num?)?.toInt() ?? 0;
  int get duration => (state['duration'] as num?)?.toInt() ?? 0;
  double get rate => (state['rate'] as num?)?.toDouble() ?? 1;
  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') {
        pip = call.arguments == true;
        notifyListeners();
      }
    });
    await refresh();
    _poller = Timer.periodic(const Duration(milliseconds: 350), (_) {
      _pollTicks++;
      if ((_foreground || pip) && (visible || _pollTicks % 6 == 0)) {
        unawaited(refresh());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) unawaited(refresh());
  }

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    try {
      final m = await channel.invokeMapMethod<String, dynamic>('snapshot');
      if (m != null) {
        state = m;
        notifyListeners();
      }
      if (visible &&
          duration > 0 &&
          DateTime.now().millisecondsSinceEpoch - _lastSave > 5000) {
        _lastSave = DateTime.now().millisecondsSinceEpoch;
        await DatabaseService.savePlaybackPosition(
          filePath: current!.uri,
          title: current!.title,
          positionMs: position,
          durationMs: duration,
        );
      }
    } catch (e) {
      debugPrint('Playback state: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> command(
    String name, [
    Map<String, dynamic> args = const {},
  ]) async {
    try {
      await channel.invokeMethod(name, args);
      actionError = null;
      await refresh();
    } catch (e) {
      actionError = e is PlatformException ? e.message : e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> open(
    List<MediaEntry> items, {
    int index = 0,
    bool shuffle = false,
  }) async {
    if (items.isEmpty) return;
    index = index.clamp(0, items.length - 1);
    final old = await DatabaseService.getPlaybackPosition(items[index].uri);
    await command('settings', MediaPreferences.instance.controls);
    await command('open', {
      'items': items.map((x) => x.toMap()).toList(),
      'index': index,
      'legacyPosition': old?['positionMs'] ?? 0,
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await command('shuffle', {'value': shuffle});
  }

  Future<List<MediaEntry>> pick([String kind = 'pickMedia']) async =>
      ((await channel.invokeListMethod(kind)) ?? [])
          .map((x) => MediaEntry.fromMap(x as Map))
          .toList();
  Future<void> seek(int ms) => command('seek', {
    'position': ms.clamp(0, duration > 0 ? duration : 1 << 53),
  });
  @override
  void dispose() {
    _poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
