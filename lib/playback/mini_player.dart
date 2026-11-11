import 'package:flutter/material.dart';
import 'playback_controller.dart';
import 'player_screen.dart';
import 'media_entry.dart';

class MiniPlayer extends StatelessWidget {
  final bool safeBottom;
  const MiniPlayer({super.key, this.safeBottom = true});
  @override
  Widget build(BuildContext context) {
    var scaffolds = 0;
    context.visitAncestorElements((element) {
      if (element.widget is Scaffold) scaffolds++;
      return scaffolds < 2;
    });
    if (scaffolds > 1) return const SizedBox.shrink();
    final p = PlaybackController.instance;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        if (!p.visible) {
          return safeBottom
              ? const SafeArea(top: false, child: SizedBox(height: 0))
              : const SizedBox.shrink();
        }
        return SafeArea(
          top: false,
          bottom: safeBottom,
          child: Material(
            color: const Color(0xff202020),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  minHeight: 2,
                  value: p.duration > 0
                      ? (p.position / p.duration).clamp(0, 1)
                      : 0,
                ),
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MediaPlayerScreen(),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Row(
                      children: [
                        Icon(
                          p.audioOnly ? Icons.music_note : Icons.movie_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.current!.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${mediaTime(p.position)} · ${p.rate.toStringAsFixed(2)}×',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: p.playing ? 'Pause' : 'Play',
                          icon: Icon(
                            p.playing
                                ? Icons.pause_circle_outline
                                : Icons.play_circle_outline,
                            size: 34,
                          ),
                          onPressed: () => _command(context, 'toggle'),
                        ),
                        IconButton(
                          tooltip: 'Next',
                          icon: const Icon(Icons.skip_next),
                          onPressed: () => _command(context, 'next'),
                        ),
                        IconButton(
                          tooltip: 'Stop playback',
                          icon: const Icon(Icons.close),
                          onPressed: () => _command(context, 'stop'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _command(BuildContext context, String name) async {
    try {
      await PlaybackController.instance.command(name);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }
}

/// Keeps the session reachable on every existing page, including pushed routes.
class MediaScaffold extends Scaffold {
  MediaScaffold({
    super.key,
    super.appBar,
    super.body,
    super.floatingActionButton,
    super.floatingActionButtonLocation,
    super.floatingActionButtonAnimator,
    super.persistentFooterButtons,
    super.drawer,
    super.endDrawer,
    super.backgroundColor,
    super.resizeToAvoidBottomInset,
    super.primary,
    super.drawerDragStartBehavior,
    super.extendBody,
    super.extendBodyBehindAppBar,
    super.drawerScrimColor,
    super.drawerEdgeDragWidth,
    super.drawerEnableOpenDragGesture,
    super.endDrawerEnableOpenDragGesture,
    super.restorationId,
    Widget? bottomNavigationBar,
  }) : super(
         bottomNavigationBar: Column(
           mainAxisSize: MainAxisSize.min,
           children: [
             MiniPlayer(safeBottom: bottomNavigationBar == null),
             ?bottomNavigationBar,
           ],
         ),
       );
}
