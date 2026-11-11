import 'package:flutter/material.dart';
import '../playback/media_entry.dart';
import '../playback/player_screen.dart';

class PlayerScreen extends StatelessWidget {
  final String filePath, title;
  final String? youtubeUrl;
  const PlayerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.youtubeUrl,
  });
  @override
  Widget build(BuildContext context) => MediaPlayerScreen(
    items: [
      MediaEntry(
        uri: filePath,
        title: title,
        audio: MediaEntry.isAudio(filePath),
        sourceUrl: youtubeUrl ?? '',
      ),
    ],
  );
}
