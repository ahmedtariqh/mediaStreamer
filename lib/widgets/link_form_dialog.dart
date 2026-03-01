import 'package:flutter/material.dart';
import '../models/youtube_link.dart';

class LinkFormDialog extends StatefulWidget {
  final YoutubeLink? existingLink;

  const LinkFormDialog({super.key, this.existingLink});

  @override
  State<LinkFormDialog> createState() => _LinkFormDialogState();
}

class _LinkFormDialogState extends State<LinkFormDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  final _formKey = GlobalKey<FormState>();

  bool get isEditing => widget.existingLink != null;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: widget.existingLink?.url ?? '',
    );
    _titleController = TextEditingController(
      text: widget.existingLink?.title ?? '',
    );
    _notesController = TextEditingController(
      text: widget.existingLink?.notes ?? '',
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final link = YoutubeLink(
      id: widget.existingLink?.id,
      url: _urlController.text.trim(),
      title: _titleController.text.trim(),
      notes: _notesController.text.trim(),
      dateAdded: widget.existingLink?.dateAdded ?? DateTime.now(),
    );

    Navigator.pop(context, link);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      isEditing ? Icons.edit : Icons.add_link,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isEditing ? 'Edit Link' : 'Add YouTube Link',
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube URL',
                    hintText: 'https://youtube.com/watch?v=...',
                    prefixIcon: Icon(Icons.link),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'URL is required';
                    }
                    if (!value.contains('youtube.com') &&
                        !value.contains('youtu.be')) {
                      return 'Enter a valid YouTube URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Video title...',
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Title is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Your notes about this video...',
                    prefixIcon: Icon(Icons.note),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  minLines: 2,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _save,
                      icon: Icon(isEditing ? Icons.save : Icons.add),
                      label: Text(isEditing ? 'Save' : 'Add'),
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
}
