import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/youtube_link.dart';
import '../services/database_service.dart';
import '../widgets/link_form_dialog.dart';
import '../widgets/add_to_playlist_sheet.dart';

class LinksScreen extends StatefulWidget {
  const LinksScreen({super.key});

  @override
  State<LinksScreen> createState() => _LinksScreenState();
}

class _LinksScreenState extends State<LinksScreen> {
  List<YoutubeLink> _links = [];
  List<YoutubeLink> _filteredLinks = [];
  bool _isLoading = true;
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    setState(() => _isLoading = true);
    final links = await DatabaseService.getLinks();
    if (mounted) {
      setState(() {
        _links = links;
        _filteredLinks = links;
        _isLoading = false;
      });
    }
  }

  void _filterLinks(String query) {
    if (query.isEmpty) {
      setState(() => _filteredLinks = _links);
    } else {
      setState(() {
        _filteredLinks = _links
            .where(
              (l) =>
                  l.title.toLowerCase().contains(query.toLowerCase()) ||
                  l.url.toLowerCase().contains(query.toLowerCase()) ||
                  l.notes.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      });
    }
  }

  Future<void> _addLink() async {
    final result = await showDialog<YoutubeLink>(
      context: context,
      builder: (_) => const LinkFormDialog(),
    );

    if (result != null) {
      await DatabaseService.saveLink(result);
      await _loadLinks();
    }
  }

  Future<void> _editLink(YoutubeLink link) async {
    final result = await showDialog<YoutubeLink>(
      context: context,
      builder: (_) => LinkFormDialog(existingLink: link),
    );

    if (result != null) {
      await DatabaseService.updateLink(result);
      await _loadLinks();
    }
  }

  Future<void> _deleteLink(YoutubeLink link) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Link'),
        content: Text('Delete "${link.title}"?'),
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

    if (confirm == true && link.id != null) {
      await DatabaseService.deleteLink(link.id!);
      await _loadLinks();
    }
  }

  Future<void> _exportJson() async {
    try {
      final json = await DatabaseService.exportNotesAsJson();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/media_streamer_export.json');
      await file.writeAsString(json);

      if (mounted) {
        await Share.shareXFiles([
          XFile(file.path),
        ], subject: 'MediaStreamer Export');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  void _addToPlaylist(YoutubeLink link) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddToPlaylistSheet(
        itemTitle: link.title,
        itemPath: '',
        itemType: AddToPlaylistItemType.youtubeLink,
        linkId: link.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search links...',
                  border: InputBorder.none,
                  fillColor: Colors.transparent,
                  filled: true,
                ),
                onChanged: _filterLinks,
              )
            : const Text('YouTube Links'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _filteredLinks = _links;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportJson,
            tooltip: 'Export JSON',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLink,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredLinks.isEmpty
          ? _buildEmptyState(theme)
          : RefreshIndicator(
              onRefresh: _loadLinks,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _filteredLinks.length,
                itemBuilder: (context, index) {
                  final link = _filteredLinks[index];
                  return _buildLinkTile(theme, link);
                },
              ),
            ),
    );
  }

  Widget _buildLinkTile(ThemeData theme, YoutubeLink link) {
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
            color: Colors.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.play_circle_fill, color: Colors.red),
        ),
        title: Text(
          link.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              link.url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.primary, fontSize: 11),
            ),
            if (link.notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                link.notes,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white54),
          onSelected: (value) {
            switch (value) {
              case 'edit':
                _editLink(link);
                break;
              case 'playlist':
                _addToPlaylist(link);
                break;
              case 'delete':
                _deleteLink(link);
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            const PopupMenuItem(
              value: 'playlist',
              child: Text('Add to Playlist'),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
        onTap: () => _editLink(link),
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
                color: Colors.red.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.link_off,
                size: 64,
                color: Colors.red.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isSearching ? 'No Results Found' : 'No YouTube Links',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isSearching
                  ? 'Try a different search term'
                  : 'Tap + to add a YouTube link\nwith your notes!',
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
