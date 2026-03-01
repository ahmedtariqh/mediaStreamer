import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/youtube_service.dart';
import '../services/local_media_service.dart';
import '../widgets/video_tile.dart';
import '../widgets/add_to_playlist_sheet.dart';
import 'folder_browser_screen.dart';
import 'player_screen.dart';
import 'stream_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Downloads tab
  List<FileSystemEntity> _downloads = [];
  bool _isLoadingDownloads = true;

  // On Device tab
  List<MediaFile> _allLocalMedia = [];
  bool _isLoadingLocal = true;

  // Sort, filter, search state for On Device tab
  MediaSortOption _sort = MediaSortOption.dateNewest;
  MediaFilterOption _filter = MediaFilterOption.all;
  String _searchQuery = '';
  bool _isSearching = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDownloads();
    _loadLocalMedia();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDownloads() async {
    setState(() => _isLoadingDownloads = true);
    final videos = await YoutubeService.getDownloadedVideos();
    if (mounted) {
      setState(() {
        _downloads = videos;
        _isLoadingDownloads = false;
      });
    }
  }

  Future<void> _loadLocalMedia() async {
    setState(() => _isLoadingLocal = true);
    final media = await LocalMediaService.scanAllMedia();
    if (mounted) {
      setState(() {
        _allLocalMedia = media;
        _isLoadingLocal = false;
      });
    }
  }

  List<MediaFile> get _processedMedia {
    var result = LocalMediaService.filterFiles(_allLocalMedia, _filter);
    if (_searchQuery.isNotEmpty) {
      result = LocalMediaService.searchFiles(result, _searchQuery);
    }
    return LocalMediaService.sortFiles(result, _sort);
  }

  String _extractTitle(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final withoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final underscoreIndex = withoutExt.indexOf('_');
    if (underscoreIndex != -1 && underscoreIndex < withoutExt.length - 1) {
      return withoutExt.substring(underscoreIndex + 1);
    }
    return withoutExt;
  }

  Future<void> _deleteDownload(String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Video'),
        content: const Text('Are you sure you want to delete this video?'),
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

    if (confirm == true) {
      await YoutubeService.deleteVideo(path);
      await _loadDownloads();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video deleted')));
      }
    }
  }

  void _addToPlaylist(String title, String path) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddToPlaylistSheet(
        itemTitle: title,
        itemPath: path,
        itemType: AddToPlaylistItemType.download,
      ),
    );
  }

  // ───────── Sort, Search & Filter UI helpers ─────────

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text('Sort By', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._sortOptions.map(
                (e) => ListTile(
                  leading: Icon(
                    _sort == e.value
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: _sort == e.value
                        ? theme.colorScheme.primary
                        : Colors.white24,
                    size: 22,
                  ),
                  title: Text(
                    e.label,
                    style: TextStyle(
                      color: _sort == e.value
                          ? theme.colorScheme.primary
                          : Colors.white70,
                      fontWeight: _sort == e.value
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  onTap: () {
                    setState(() => _sort = e.value);
                    Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static const _sortOptions = [
    (label: 'Name (A → Z)', value: MediaSortOption.nameAsc),
    (label: 'Name (Z → A)', value: MediaSortOption.nameDesc),
    (label: 'Date (Newest)', value: MediaSortOption.dateNewest),
    (label: 'Date (Oldest)', value: MediaSortOption.dateOldest),
    (label: 'Size (Largest)', value: MediaSortOption.sizeLargest),
    (label: 'Size (Smallest)', value: MediaSortOption.sizeSmallest),
  ];

  // ───────── Build ─────────

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
                  hintText: 'Search media files...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Library'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.download), text: 'Downloads'),
            Tab(icon: Icon(Icons.phone_android), text: 'On Device'),
          ],
        ),
        actions: [
          // Search (only for On Device tab)
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
          // Sort
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortMenu,
            tooltip: 'Sort',
          ),
          // Browse folders
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FolderBrowserScreen()),
              );
            },
            tooltip: 'Browse Folders',
          ),
          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadDownloads();
              _loadLocalMedia();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDownloadsTab(theme), _buildLocalMediaTab(theme)],
      ),
    );
  }

  // ───────── Downloads tab (unchanged) ─────────

  Widget _buildDownloadsTab(ThemeData theme) {
    if (_isLoadingDownloads) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_downloads.isEmpty) {
      return _buildEmptyState(
        theme,
        Icons.video_library_outlined,
        'No Downloaded Videos',
        'Go to the Home tab and paste a\nYouTube link to start downloading!',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadDownloads,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _downloads.length,
        itemBuilder: (context, index) {
          final video = _downloads[index];
          final title = _extractTitle(video.path);
          return VideoTile(
            title: title,
            filePath: video.path,
            onPlay: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    filePath: video.path,
                    title: title,
                    youtubeUrl: '',
                  ),
                ),
              ).then((_) => _loadDownloads());
            },
            onStream: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      StreamScreen(filePath: video.path, title: title),
                ),
              );
            },
            onDelete: () => _deleteDownload(video.path),
            onAddToPlaylist: () => _addToPlaylist(title, video.path),
          );
        },
      ),
    );
  }

  // ───────── On Device tab (enhanced) ─────────

  Widget _buildLocalMediaTab(ThemeData theme) {
    if (_isLoadingLocal) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Scanning device for media files...',
              style: TextStyle(color: Colors.white38),
            ),
          ],
        ),
      );
    }

    final media = _processedMedia;

    if (_allLocalMedia.isEmpty) {
      return _buildEmptyState(
        theme,
        Icons.phone_android,
        'No Media Found',
        'No video or audio files found\non this device.',
      );
    }

    return Column(
      children: [
        // Filter chips
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              _filterChip(theme, 'All', MediaFilterOption.all),
              const SizedBox(width: 8),
              _filterChip(theme, 'Video', MediaFilterOption.videoOnly),
              const SizedBox(width: 8),
              _filterChip(theme, 'Audio', MediaFilterOption.audioOnly),
              const Spacer(),
              Text(
                '${media.length} files',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),

        // File list
        Expanded(
          child: media.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'No results for "$_searchQuery"'
                        : 'No matching files',
                    style: const TextStyle(color: Colors.white38),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadLocalMedia,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: media.length,
                    itemBuilder: (context, index) =>
                        _buildLocalMediaTile(theme, media[index]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _filterChip(ThemeData theme, String label, MediaFilterOption opt) {
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

  Widget _buildLocalMediaTile(ThemeData theme, MediaFile media) {
    final isVideo = media.type == MediaFileType.video;
    final dateStr = DateFormat('MMM d, yyyy').format(media.lastModified);

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
          width: 48,
          height: 48,
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
          media.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: Text(
          '${media.formattedSize} • $dateStr',
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
              onPressed: () => _addToPlaylist(media.name, media.path),
              tooltip: 'Add to Playlist',
            ),
            IconButton(
              icon: const Icon(Icons.play_circle_fill, size: 32),
              color: theme.colorScheme.primary,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      filePath: media.path,
                      title: media.name,
                      youtubeUrl: '',
                    ),
                  ),
                );
              },
              tooltip: 'Play',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    ThemeData theme,
    IconData icon,
    String title,
    String subtitle,
  ) {
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
                icon,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
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
