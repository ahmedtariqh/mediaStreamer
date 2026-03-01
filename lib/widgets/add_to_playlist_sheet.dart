import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/playlist_item.dart';
import '../services/database_service.dart';

enum AddToPlaylistItemType { localFile, download, youtubeLink }

class AddToPlaylistSheet extends StatefulWidget {
  final String itemTitle;
  final String itemPath;
  final AddToPlaylistItemType itemType;
  final int? linkId;

  const AddToPlaylistSheet({
    super.key,
    required this.itemTitle,
    required this.itemPath,
    required this.itemType,
    this.linkId,
  });

  @override
  State<AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<AddToPlaylistSheet> {
  List<Playlist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final playlists = await DatabaseService.getPlaylists();
    if (mounted) {
      setState(() {
        _playlists = playlists;
        _isLoading = false;
      });
    }
  }

  PlaylistItemType get _playlistItemType {
    switch (widget.itemType) {
      case AddToPlaylistItemType.localFile:
        return PlaylistItemType.localFile;
      case AddToPlaylistItemType.download:
        return PlaylistItemType.download;
      case AddToPlaylistItemType.youtubeLink:
        return PlaylistItemType.youtubeLink;
    }
  }

  Future<void> _addToPlaylist(Playlist playlist) async {
    final item = PlaylistItem(
      playlistId: playlist.id!,
      type: _playlistItemType,
      path: widget.itemPath,
      linkId: widget.linkId,
      title: widget.itemTitle,
    );

    await DatabaseService.addToPlaylist(item);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added to "${playlist.name}"'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<void> _createAndAdd() async {
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
      final id = await DatabaseService.createPlaylist(
        Playlist(name: name, dateCreated: DateTime.now()),
      );
      final playlist = Playlist(
        id: id,
        name: name,
        dateCreated: DateTime.now(),
      );
      await _addToPlaylist(playlist);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Icon(Icons.playlist_add, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add to Playlist',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _createAndAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '"${widget.itemTitle}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _playlists.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.playlist_play,
                              size: 48,
                              color: Colors.white24,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No playlists yet',
                              style: TextStyle(color: Colors.white38),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _createAndAdd,
                              child: const Text('Create Playlist'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: _playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = _playlists[index];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.playlist_play,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            title: Text(playlist.name),
                            trailing: Icon(
                              Icons.add_circle_outline,
                              color: theme.colorScheme.primary,
                            ),
                            onTap: () => _addToPlaylist(playlist),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
