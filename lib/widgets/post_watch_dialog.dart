import 'package:flutter/material.dart';

class PostWatchDialog extends StatefulWidget {
  final String videoTitle;
  final String youtubeUrl;

  const PostWatchDialog({
    super.key,
    required this.videoTitle,
    required this.youtubeUrl,
  });

  @override
  State<PostWatchDialog> createState() => _PostWatchDialogState();
}

class _PostWatchDialogState extends State<PostWatchDialog> {
  final _notesController = TextEditingController();
  bool _showNotesField = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.check_circle_outline,
                    color: theme.colorScheme.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Video Finished', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        widget.videoTitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Notes field (expandable)
            if (_showNotesField) ...[
              TextField(
                controller: _notesController,
                maxLines: 5,
                decoration: const InputDecoration(
                  hintText: 'Write your notes here...',
                  alignLabelWithHint: true,
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).pop({'action': 'save', 'notes': _notesController.text});
                },
                icon: const Icon(Icons.save),
                label: const Text('Save Notes & Delete Video'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _showNotesField = false),
                child: const Text('Cancel'),
              ),
            ] else ...[
              // Two action buttons
              ElevatedButton.icon(
                onPressed: () => setState(() => _showNotesField = true),
                icon: const Icon(Icons.note_add),
                label: const Text('Add Notes & Delete'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop({'action': 'delete'});
                },
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: const Text(
                  'Delete Right Away',
                  style: TextStyle(color: Colors.redAccent),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.redAccent),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Keep Video'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
