import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/folder_item.dart';
import '../services/local_media_service.dart';
import '../widgets/add_to_playlist_sheet.dart';
import 'player_screen.dart';
import 'stream_screen.dart';

/// A drill-down folder browser for the phone's filesystem.
class FolderBrowserScreen extends StatefulWidget {
  final String initialPath;

  const FolderBrowserScreen({
    super.key,
    this.initialPath = '/storage/emulated/0',
  });

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  late String _currentPath;
  List<FolderItem> _folders = [];
  List<MediaFile> _files = [];
  bool _isLoading = true;

  // Sort & filter state
  MediaSortOption _sort = MediaSortOption.nameAsc;
  MediaFilterOption _filter = MediaFilterOption.all;
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDirectory() async {
    setState(() => _isLoading = true);
    final result = await LocalMediaService.listDirectory(_currentPath);
    if (mounted) {
      setState(() {
        _folders = result.folders;
        _files = result.files;
        _isLoading = false;
      });
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _loadDirectory();
  }

  void _goUp() {
    final parent = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
    if (parent.isEmpty || parent == '/storage/emulated') return;
    _navigateTo(parent);
  }

  List<MediaFile> get _processedFiles {
    var result = LocalMediaService.filterFiles(_files, _filter);
    if (_searchQuery.isNotEmpty) {
      result = LocalMediaService.searchFiles(result, _searchQuery);
    }
    return LocalMediaService.sortFiles(result, _sort);
  }

  List<FolderItem> get _filteredFolders {
    if (_searchQuery.isEmpty) return _folders;
    final lower = _searchQuery.toLowerCase();
    return _folders.where((f) => f.name.toLowerCase().contains(lower)).toList();
  }

  /// Breadcrumb segments from root to current path.
  List<({String label, String path})> get _breadcrumbs {
    const root = '/storage/emulated/0';
    if (_currentPath == root) {
      return [(label: 'Internal Storage', path: root)];
    }
    final relPath = _currentPath.substring(root.length);
    final segments = relPath.split('/').where((s) => s.isNotEmpty).toList();

    final crumbs = <({String label, String path})>[
      (label: 'Internal Storage', path: root),
    ];
    var accumulated = root;
    for (final seg in segments) {
      accumulated = '$accumulated/$seg';
      crumbs.add((label: seg, path: accumulated));
    }
    return crumbs;
  }

  // ──────────────────────────────────────────────
  //  UI builders
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search files & folders...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Browse Files'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchQuery = '';
                  _searchController.clear();
                }
              });
            },
          ),
          PopupMenuButton<MediaSortOption>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: (opt) => setState(() => _sort = opt),
            itemBuilder: (_) => [
              _sortMenuItem(MediaSortOption.nameAsc, 'Name (A → Z)'),
              _sortMenuItem(MediaSortOption.nameDesc, 'Name (Z → A)'),
              _sortMenuItem(MediaSortOption.dateNewest, 'Date (Newest)'),
              _sortMenuItem(MediaSortOption.dateOldest, 'Date (Oldest)'),
              _sortMenuItem(MediaSortOption.sizeLargest, 'Size (Largest)'),
              _sortMenuItem(MediaSortOption.sizeSmallest, 'Size (Smallest)'),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Breadcrumbs
          _buildBreadcrumbs(theme),

          // Filter chips
          _buildFilterChips(theme),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(theme),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<MediaSortOption> _sortMenuItem(
    MediaSortOption opt,
    String label,
  ) {
    return PopupMenuItem(
      value: opt,
      child: Row(
        children: [
          if (_sort == opt)
            const Icon(Icons.check, size: 18)
          else
            const SizedBox(width: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs(ThemeData theme) {
    final crumbs = _breadcrumbs;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: crumbs.length,
        separatorBuilder: (_, _) =>
            const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
        itemBuilder: (_, i) {
          final isLast = i == crumbs.length - 1;
          return Center(
            child: GestureDetector(
              onTap: isLast ? null : () => _navigateTo(crumbs[i].path),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  crumbs[i].label,
                  style: TextStyle(
                    color: isLast ? theme.colorScheme.primary : Colors.white54,
                    fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _chip(theme, 'All', MediaFilterOption.all),
          const SizedBox(width: 8),
          _chip(theme, 'Video', MediaFilterOption.videoOnly),
          const SizedBox(width: 8),
          _chip(theme, 'Audio', MediaFilterOption.audioOnly),
          const Spacer(),
          Text(
            '${_processedFiles.length} files',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, MediaFilterOption opt) {
    final selected = _filter == opt;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: selected ? Colors.white : Colors.white54,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = opt),
      selectedColor: theme.colorScheme.primary.withValues(alpha: 0.3),
      backgroundColor: theme.cardColor,
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: selected ? theme.colorScheme.primary : Colors.white12,
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildContent(ThemeData theme) {
    final folders = _filteredFolders;
    final files = _processedFiles;

    if (folders.isEmpty && files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: 12),
            Text(
              'No media files here',
              style: TextStyle(color: Colors.white38),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDirectory,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // Back button (if not at root)
          if (_currentPath != '/storage/emulated/0')
            ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.arrow_upward, color: Colors.white54),
              ),
              title: const Text('..', style: TextStyle(color: Colors.white54)),
              subtitle: const Text(
                'Parent folder',
                style: TextStyle(color: Colors.white24, fontSize: 12),
              ),
              onTap: _goUp,
            ),

          // Folders
          ...folders.map((folder) => _buildFolderTile(theme, folder)),

          // Divider between folders and files
          if (folders.isNotEmpty && files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Divider(color: Colors.white10),
            ),

          // Files
          ...files.map((file) => _buildFileTile(theme, file)),
        ],
      ),
    );
  }

  Widget _buildFolderTile(ThemeData theme, FolderItem folder) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.folder, color: Colors.amber),
        ),
        title: Text(
          folder.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: () => _navigateTo(folder.path),
      ),
    );
  }

  Widget _buildFileTile(ThemeData theme, MediaFile file) {
    final isVideo = file.type == MediaFileType.video;
    final dateStr = DateFormat('MMM d, yyyy').format(file.lastModified);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color:
                (isVideo
                        ? theme.colorScheme.primary
                        : theme.colorScheme.secondary)
                    .withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isVideo ? Icons.videocam : Icons.audiotrack,
            color: isVideo
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
          ),
        ),
        title: Text(
          file.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          '${file.formattedSize} • $dateStr',
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.playlist_add,
                color: theme.colorScheme.secondary,
                size: 22,
              ),
              onPressed: () => _addToPlaylist(file),
              tooltip: 'Add to Playlist',
            ),
            IconButton(
              icon: Icon(
                Icons.cast,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              onPressed: () => _stream(file),
              tooltip: 'Stream',
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_fill, size: 30),
              color: theme.colorScheme.primary,
              onPressed: () => _play(file),
              tooltip: 'Play',
            ),
          ],
        ),
      ),
    );
  }

  void _play(MediaFile file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PlayerScreen(filePath: file.path, title: file.name, youtubeUrl: ''),
      ),
    );
  }

  void _stream(MediaFile file) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StreamScreen(filePath: file.path, title: file.name),
      ),
    );
  }

  void _addToPlaylist(MediaFile file) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddToPlaylistSheet(
        itemTitle: file.name,
        itemPath: file.path,
        itemType: AddToPlaylistItemType.download,
      ),
    );
  }
}
