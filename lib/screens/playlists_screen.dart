import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../services/database_service.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  List<Playlist> _playlists = [];
  Map<int, int> _itemCounts = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _isLoading = true);
    final playlists = await DatabaseService.getPlaylists();
    final counts = <int, int>{};
    for (final p in playlists) {
      if (p.id != null) {
        counts[p.id!] = await DatabaseService.getPlaylistItemCount(p.id!);
      }
    }
    if (mounted) {
      setState(() {
        _playlists = playlists;
        _itemCounts = counts;
        _isLoading = false;
      });
    }
  }

  Future<void> _createPlaylist() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name...'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    nameController.dispose();

    if (name != null && name.isNotEmpty) {
      await DatabaseService.createPlaylist(
        Playlist(name: name, dateCreated: DateTime.now()),
      );
      await _loadPlaylists();
    }
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
    final nameController = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New name...'),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    nameController.dispose();

    if (name != null && name.isNotEmpty && playlist.id != null) {
      await DatabaseService.renamePlaylist(playlist.id!, name);
      await _loadPlaylists();
    }
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Delete "${playlist.name}" and all its items?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && playlist.id != null) {
      await DatabaseService.deletePlaylist(playlist.id!);
      await _loadPlaylists();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Playlists')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createPlaylist,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _playlists.isEmpty
          ? _buildEmptyState(theme)
          : RefreshIndicator(
              onRefresh: _loadPlaylists,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final playlist = _playlists[index];
                  final count = _itemCounts[playlist.id] ?? 0;
                  return _buildPlaylistTile(theme, playlist, count);
                },
              ),
            ),
    );
  }

  Widget _buildPlaylistTile(ThemeData theme, Playlist playlist, int itemCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary.withValues(alpha: 0.3),
                theme.colorScheme.secondary.withValues(alpha: 0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.playlist_play,
            color: theme.colorScheme.primary,
            size: 28,
          ),
        ),
        title: Text(
          playlist.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white54),
          onSelected: (value) {
            switch (value) {
              case 'rename':
                _renamePlaylist(playlist);
                break;
              case 'delete':
                _deletePlaylist(playlist);
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
        onTap: () {
          if (playlist.id != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PlaylistDetailScreen(playlist: playlist),
              ),
            ).then((_) => _loadPlaylists());
          }
        },
      ),
    );
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
                Icons.playlist_play,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Playlists Yet',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to create your first playlist!',
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
