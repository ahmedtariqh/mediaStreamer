import 'package:flutter/material.dart';
import '../models/stream_info_item.dart';

class DownloadProgressTile extends StatelessWidget {
  final String title;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final double speed;
  final VoidCallback? onCancel;

  const DownloadProgressTile({
    super.key,
    required this.title,
    required this.progress,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speed = 0,
    this.onCancel,
  });

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '—';
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
    if (bytesPerSec < 1048576) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSec / 1048576).toStringAsFixed(1)} MB/s';
  }

  String _formatEta(int remainingBytes, double bytesPerSec) {
    if (bytesPerSec <= 0) return '—';
    final seconds = (remainingBytes / bytesPerSec).round();
    if (seconds < 60) return '${seconds}s left';
    if (seconds < 3600) return '${seconds ~/ 60}m ${seconds % 60}s left';
    return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m left';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = (progress * 100).toStringAsFixed(1);
    final remaining = totalBytes - downloadedBytes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.download_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onCancel != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onCancel,
                    color: Colors.white54,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Percentage
                Text(
                  '$percentage%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // Size progress
                if (totalBytes > 0)
                  Text(
                    '${StreamInfoItem.formatFileSize(downloadedBytes)} / ${StreamInfoItem.formatFileSize(totalBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white54,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Speed
                Row(
                  children: [
                    Icon(
                      Icons.speed,
                      size: 14,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatSpeed(speed),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
                // ETA
                Text(
                  _formatEta(remaining, speed),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
