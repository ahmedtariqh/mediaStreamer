import 'package:flutter/material.dart';
import '../models/stream_info_item.dart';

class FormatPickerSheet extends StatelessWidget {
  final String videoTitle;
  final String thumbnailUrl;
  final List<StreamInfoItem> streams;

  const FormatPickerSheet({
    super.key,
    required this.videoTitle,
    required this.thumbnailUrl,
    required this.streams,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final muxed = streams.where((s) => s.type == StreamType.muxed).toList();
    final videoOnly = streams
        .where((s) => s.type == StreamType.videoOnly)
        .toList();
    final audioOnly = streams
        .where((s) => s.type == StreamType.audioOnly)
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  videoTitle,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose format to download',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white38,
                ),
              ),
              const SizedBox(height: 16),
              // Stream list
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (muxed.isNotEmpty) ...[
                      _sectionHeader(theme, Icons.videocam, 'Video + Audio'),
                      ...muxed.map((s) => _streamTile(context, s, theme)),
                      const SizedBox(height: 16),
                    ],
                    if (videoOnly.isNotEmpty) ...[
                      _sectionHeader(
                        theme,
                        Icons.video_file,
                        'Video Only (no audio)',
                      ),
                      ...videoOnly.map((s) => _streamTile(context, s, theme)),
                      const SizedBox(height: 16),
                    ],
                    if (audioOnly.isNotEmpty) ...[
                      _sectionHeader(theme, Icons.audiotrack, 'Audio Only'),
                      ...audioOnly.map((s) => _streamTile(context, s, theme)),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(ThemeData theme, IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.secondary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _streamTile(
    BuildContext context,
    StreamInfoItem item,
    ThemeData theme,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(context, item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Quality badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _qualityColor(item).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.qualityLabel,
                  style: TextStyle(
                    color: _qualityColor(item),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Codec & container
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.codec,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.container.toUpperCase(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // File size
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.fileSize,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.download, color: theme.colorScheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Color _qualityColor(StreamInfoItem item) {
    if (item.type == StreamType.audioOnly) return Colors.orangeAccent;
    final label = item.qualityLabel.toLowerCase();
    if (label.contains('2160') || label.contains('4k')) return Colors.redAccent;
    if (label.contains('1440')) return Colors.deepOrangeAccent;
    if (label.contains('1080')) return Colors.amber;
    if (label.contains('720')) return Colors.greenAccent;
    return Colors.cyanAccent;
  }
}
