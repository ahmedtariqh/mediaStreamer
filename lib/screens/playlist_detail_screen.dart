import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/playlist_item.dart';
import '../services/database_service.dart';
import 'player_screen.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<PlaylistItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final items = await DatabaseService.getPlaylistItems(widget.playlist.id!);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  Future<void> _removeItem(PlaylistItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Item'),
        content: Text('Remove "${item.title}" from this playlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm == true && item.id != null) {
      await DatabaseService.removeFromPlaylist(item.id!);
      await _loadItems();
    }
  }

  void _playItem(PlaylistItem item) {
    if (item.type == PlaylistItemType.youtubeLink) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('YouTube links need to be downloaded first'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          filePath: item.path,
          title: item.title,
          youtubeUrl: '',
        ),
      ),
    );
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;

    setState(() {
      final item = _items.removeAt(oldIndex);
      _items.insert(newIndex, item);
    });

    final ids = _items.map((i) => i.id!).toList();
    await DatabaseService.reorderPlaylistItems(widget.playlist.id!, ids);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? _buildEmptyState(theme)
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              onReorder: _onReorder,
              itemBuilder: (context, index) {
                final item = _items[index];
                return _buildItemTile(theme, item, key: ValueKey(item.id));
              },
            ),
    );
  }

  Widget _buildItemTile(ThemeData theme, PlaylistItem item, {Key? key}) {
    IconData typeIcon;
    Color typeColor;

    switch (item.type) {
      case PlaylistItemType.localFile:
        typeIcon = Icons.phone_android;
        typeColor = theme.colorScheme.secondary;
        break;
      case PlaylistItemType.download:
        typeIcon = Icons.download;
        typeColor = theme.colorScheme.primary;
        break;
      case PlaylistItemType.youtubeLink:
        typeIcon = Icons.link;
        typeColor = Colors.red;
        break;
    }

    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.drag_handle, color: Colors.white24, size: 20),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(typeIcon, color: typeColor, size: 22),
            ),
          ],
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          _typeLabel(item.type),
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.type != PlaylistItemType.youtubeLink)
              IconButton(
                icon: Icon(
                  Icons.play_circle_fill,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                onPressed: () => _playItem(item),
                tooltip: 'Play',
              ),
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                color: Colors.redAccent,
                size: 22,
              ),
              onPressed: () => _removeItem(item),
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(PlaylistItemType type) {
    switch (type) {
      case PlaylistItemType.localFile:
        return 'Local File';
      case PlaylistItemType.download:
        return 'Downloaded';
      case PlaylistItemType.youtubeLink:
        return 'YouTube Link';
    }
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.queue_music,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Empty Playlist',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add items from the Library or\nLinks tabs using the playlist button.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
