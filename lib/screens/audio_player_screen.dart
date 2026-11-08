import 'package:flutter/material.dart';
import '../playback/media_entry.dart';
import '../playback/player_screen.dart';

class AudioPlayerScreen extends StatelessWidget {
  final String filePath, title;
  const AudioPlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
  });
  @override
  Widget build(BuildContext context) => MediaPlayerScreen(
    items: [MediaEntry(uri: filePath, title: title, audio: true)],
  );
}
