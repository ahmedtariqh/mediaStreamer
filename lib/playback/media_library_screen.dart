import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/database_service.dart';
import 'library_actions.dart';
import 'media_catalog.dart';
import 'media_entry.dart';
import 'media_preferences.dart';
import 'mini_player.dart';
import 'playback_controller.dart';

class MediaLibraryScreen extends StatefulWidget {
  final bool audio;
  final List<MediaEntry>? items;
  final String? title;
  const MediaLibraryScreen({
    super.key,
    required this.audio,
    this.items,
    this.title,
  });
  @override
  State<MediaLibraryScreen> createState() => _MediaLibraryScreenState();
}

class _MediaLibraryScreenState extends State<MediaLibraryScreen>
    with WidgetsBindingObserver {
  final catalog = MediaCatalog.instance, prefs = MediaPreferences.instance;
  final selected = <String>{};
  final _relocated = <String, String>{};
  String search = '', group = 'tracks';
  bool list = false, folders = true, favorites = false, descending = false;
  CatalogSort sort = CatalogSort.name;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    catalog.addListener(_changed);
    prefs.addListener(_changed);
    list = prefs.controls['libraryList'] == true;
    folders = prefs.controls['libraryFolders'] != false;
    favorites = prefs.controls['libraryFavorites'] == true;
    descending = prefs.controls['libraryDescending'] == true;
    sort = CatalogSort.values.firstWhere(
      (v) => v.name == prefs.controls['librarySort'],
      orElse: () => CatalogSort.name,
    );
    if (widget.items == null) catalog.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.items == null) {
      catalog.load();
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    catalog.removeListener(_changed);
    prefs.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<MediaEntry> get _items => sortMedia(
    (widget.items ?? catalog.items)
        .map(
          (m) => _relocated.containsKey(m.uri)
              ? MediaEntry.fromMap({...m.toMap(), 'uri': _relocated[m.uri]})
              : m,
        )
        .where((m) => m.audio == widget.audio)
        .where((m) => !favorites || prefs.favorites.contains(m.uri))
        .where(
          (m) => '${m.title} ${m.filename} ${m.artist} ${m.album}'
              .toLowerCase()
              .contains(search.toLowerCase()),
        ),
    sort,
    descending: descending,
  );
  List<MediaEntry> get _selection =>
      _items.where((m) => selected.contains(m.uri)).toList();
  @override
  Widget build(BuildContext context) {
    final items = _items;
    final grouped =
        widget.items == null && (widget.audio ? group != 'tracks' : folders);
    final groups = grouped
        ? groupMedia(items, widget.audio ? group : 'folder').entries.toList()
        : <MapEntry<String, List<MediaEntry>>>[];
    return MediaScaffold(
      appBar: AppBar(
        title: Text(
          selected.isNotEmpty
              ? '${selected.length} selected'
              : widget.title ?? (widget.audio ? 'Audio' : 'Video'),
        ),
        actions: selected.isNotEmpty
            ? [
                IconButton(
                  tooltip: 'Play selection',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => LibraryActions.play(context, _selection),
                ),
                IconButton(
                  tooltip: 'Add to queue',
                  icon: const Icon(Icons.queue_music),
                  onPressed: () => _enqueue(_selection),
                ),
                IconButton(
                  tooltip: 'Save to playlist',
                  icon: const Icon(Icons.playlist_add),
                  onPressed: () =>
                      LibraryActions.savePlaylist(context, _selection),
                ),
                IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(selected.clear),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Open file',
                  icon: const Icon(Icons.file_open_outlined),
                  onPressed: _pick,
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    switch (v) {
                      case 'display':
                        _display();
                      case 'network':
                        LibraryActions.network(context);
                      case 'import':
                        LibraryActions.importPlaylist(context);
                      case 'export':
                        LibraryActions.exportPlaylist(context, items);
                      case 'refresh':
                        catalog.load(force: true);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'display',
                      child: Text('Display settings'),
                    ),
                    PopupMenuItem(
                      value: 'network',
                      child: Text('Open network stream'),
                    ),
                    PopupMenuItem(
                      value: 'import',
                      child: Text('Import playlist'),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: Text('Export visible media'),
                    ),
                    PopupMenuItem(
                      value: 'refresh',
                      child: Text('Refresh library'),
                    ),
                  ],
                ),
              ],
      ),
      floatingActionButton: items.isEmpty
          ? null
          : FloatingActionButton(
              tooltip: 'Play all',
              onPressed: () => LibraryActions.play(context, items),
              child: const Icon(Icons.play_arrow, size: 34),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => search = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search your media',
                isDense: true,
              ),
            ),
          ),
          if (widget.audio && widget.items == null)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['artist', 'album', 'tracks', 'genre']
                    .map(
                      (g) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text(
                            {
                              'artist': 'ARTISTS',
                              'album': 'ALBUMS',
                              'tracks': 'TRACKS',
                              'genre': 'GENRES',
                            }[g]!,
                          ),
                          selected: group == g,
                          onSelected: (_) => setState(() => group = g),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          if (catalog.loading) const LinearProgressIndicator(minHeight: 2),
          if (catalog.error != null && widget.items == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(catalog.error!),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => catalog.load(force: true),
              child: items.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 100),
                        const Icon(
                          Icons.video_library_outlined,
                          size: 64,
                          color: Colors.white38,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            search.isEmpty
                                ? 'No ${widget.audio ? 'audio' : 'videos'} found. Refresh, grant media access or open a file.'
                                : 'No matching media',
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Center(
                          child: FilledButton.icon(
                            onPressed: _pick,
                            icon: const Icon(Icons.file_open),
                            label: const Text('Open file'),
                          ),
                        ),
                      ],
                    )
                  : grouped
                  ? GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 320,
                            childAspectRatio: 1.25,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                          ),
                      itemCount: groups.length,
                      itemBuilder: (c, i) => _group(groups[i]),
                    )
                  : list || widget.audio
                  ? ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: items.length,
                      itemBuilder: (c, i) => _tile(items, i),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 340,
                            childAspectRatio: 1.25,
                            crossAxisSpacing: 20,
                            mainAxisSpacing: 20,
                          ),
                      itemCount: items.length,
                      itemBuilder: (c, i) => _card(items, i),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    try {
      final files = await PlaybackController.instance.pick();
      if (files.isNotEmpty && mounted) {
        await LibraryActions.play(context, files);
      }
    } catch (e) {
      if (mounted) LibraryActions.error(context, e);
    }
  }

  Future<void> _enqueue(List<MediaEntry> items, {bool next = false}) async {
    try {
      await PlaybackController.instance.command(next ? 'playNext' : 'enqueue', {
        'items': items.map((m) => m.toMap()).toList(),
      });
      if (mounted) {
        setState(selected.clear);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Added to queue')));
      }
    } catch (e) {
      if (mounted) LibraryActions.error(context, e);
    }
  }

  void _tap(List<MediaEntry> items, int index) {
    if (selected.isNotEmpty) {
      _select(items[index]);
    } else {
      LibraryActions.play(context, items, index: index);
    }
  }

  void _select(MediaEntry m) => setState(() {
    if (!selected.remove(m.uri)) selected.add(m.uri);
  });
  Widget _group(MapEntry<String, List<MediaEntry>> entry) {
    final label = widget.audio ? entry.key : entry.key.split('/').last;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MediaLibraryScreen(
            audio: widget.audio,
            items: entry.value,
            title: label,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  for (var col = 0; col < 2; col++)
                    Expanded(
                      child: Column(
                        children: [
                          for (var row = 0; row < 2; row++)
                            Expanded(
                              child: col * 2 + row < entry.value.length
                                  ? _thumb(entry.value[col * 2 + row])
                                  : Container(
                                      color: const Color(0xff222222),
                                      child: const Center(
                                        child: Icon(
                                          Icons.folder_outlined,
                                          color: Colors.white24,
                                        ),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18),
          ),
          Text(
            '${entry.value.length} ${widget.audio ? 'tracks' : 'videos'}',
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _thumb(MediaEntry m) {
    if (m.audio) {
      return Container(
        color: const Color(0xff242424),
        child: const Center(
          child: Icon(Icons.music_note, size: 44, color: Colors.white38),
        ),
      );
    }
    return FutureBuilder(
      future: ThumbnailCache.get(m.uri),
      builder: (c, s) => s.data == null
          ? Container(
              color: const Color(0xff242424),
              child: const Center(
                child: Icon(
                  Icons.movie_outlined,
                  size: 38,
                  color: Colors.white24,
                ),
              ),
            )
          : Image.memory(
              s.data!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            ),
    );
  }

  Widget _card(List<MediaEntry> items, int i) {
    final m = items[i];
    return InkWell(
      onTap: () => _tap(items, i),
      onLongPress: () => _select(m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _thumb(m),
                  if (selected.contains(m.uri))
                    Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.orange,
                          size: 40,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Media actions',
                      onPressed: () => _actions(m),
                      icon: const Icon(Icons.more_vert),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black38,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    left: 6,
                    child: Row(
                      children: [
                        if (prefs.favorites.contains(m.uri))
                          const Icon(
                            Icons.favorite,
                            size: 18,
                            color: Colors.orange,
                          ),
                        if (prefs.watched.contains(m.uri))
                          const Icon(
                            Icons.check_circle,
                            size: 18,
                            color: Colors.white70,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            m.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17),
          ),
          Text(
            mediaTime(m.duration),
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _tile(List<MediaEntry> items, int i) {
    final m = items[i];
    return ListTile(
      leading: SizedBox(
        width: 56,
        height: 48,
        child: selected.contains(m.uri)
            ? const Icon(Icons.check_circle, color: Colors.orange)
            : _thumb(m),
      ),
      title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${m.artist.isEmpty ? m.filename : m.artist} · ${mediaTime(m.duration)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Media actions',
        icon: const Icon(Icons.more_vert),
        onPressed: () => _actions(m),
      ),
      onTap: () => _tap(items, i),
      onLongPress: () => _select(m),
    );
  }

  Future<void> _actions(MediaEntry m) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            title: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          ...<({IconData icon, String title, VoidCallback action})>[
            (
              icon: Icons.play_arrow,
              title: 'Play',
              action: () => LibraryActions.play(context, [m]),
            ),
            (
              icon: Icons.playlist_play,
              title: 'Play next',
              action: () => _enqueue([m], next: true),
            ),
            (
              icon: Icons.queue_music,
              title: 'Add to queue',
              action: () => _enqueue([m]),
            ),
            (
              icon: Icons.favorite_border,
              title: prefs.favorites.contains(m.uri)
                  ? 'Remove favorite'
                  : 'Add to favorites',
              action: () => prefs.favorite(m.uri),
            ),
            (
              icon: Icons.check_circle_outline,
              title: 'Mark watched',
              action: () => prefs.markWatched(m.uri),
            ),
            (
              icon: Icons.playlist_add,
              title: 'Add to playlist',
              action: () => LibraryActions.savePlaylist(context, [m]),
            ),
            (
              icon: Icons.info_outline,
              title: 'Information',
              action: () => showDialog<void>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text(m.title),
                  content: SelectableText(
                    '${m.uri}\n\nDuration: ${mediaTime(m.duration)}\nSize: ${(m.size / 1048576).toStringAsFixed(1)} MB\nArtist: ${m.artist}\nAlbum: ${m.album}\nAdded: ${DateTime.fromMillisecondsSinceEpoch(m.added)}',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
            (
              icon: Icons.share,
              title: 'Share file',
              action: () async {
                try {
                  await Share.shareXFiles([XFile(m.uri)], text: m.title);
                } catch (e) {
                  if (mounted) LibraryActions.error(context, e);
                }
              },
            ),
            (
              icon: Icons.edit_outlined,
              title: 'Rename',
              action: () async {
                final name = await LibraryActions.text(
                  context,
                  'File name',
                  initial: m.filename,
                );
                if (name == null ||
                    name.isEmpty ||
                    name.contains('/') ||
                    name.contains('\\')) {
                  return;
                }
                try {
                  final path = await PlaybackController.channel
                      .invokeMethod<String>('renameMedia', {
                        ...m.toMap(),
                        'name': name,
                      });
                  if (path != null && path != m.uri) {
                    await DatabaseService.relocateMedia(m.uri, path);
                    await prefs.relocate(m.uri, path);
                    await PlaybackController.channel.invokeMethod('relocate', {
                      'old': m.uri,
                      'new': path,
                    });
                    _relocated[m.uri] = path;
                  }
                  await catalog.load(force: true);
                } catch (e) {
                  if (mounted) LibraryActions.error(context, e);
                }
              },
            ),
            (
              icon: Icons.delete_outline,
              title: 'Delete',
              action: () async {
                if (await LibraryActions.delete(context, m)) {
                  await catalog.load(force: true);
                }
              },
            ),
          ].map(
            (a) => ListTile(
              leading: Icon(a.icon),
              title: Text(a.title),
              onTap: () {
                Navigator.pop(c);
                a.action();
              },
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> _display() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: StatefulBuilder(
        builder: (c, set) {
          void update(VoidCallback change) {
            setState(change);
            set(() {});
            prefs.settings({
              'libraryList': list,
              'libraryFolders': folders,
              'libraryFavorites': favorites,
              'librarySort': sort.name,
              'libraryDescending': descending,
            });
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Display settings',
                    style: TextStyle(fontSize: 22, color: Colors.orange),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Display in list'),
                  value: list,
                  onChanged: (v) => update(() => list = v),
                ),
                if (!widget.audio && widget.items == null)
                  SwitchListTile(
                    title: const Text('Group videos by folder'),
                    value: folders,
                    onChanged: (v) => update(() => folders = v),
                  ),
                SwitchListTile(
                  title: const Text('Show only favorites'),
                  value: favorites,
                  onChanged: (v) => update(() => favorites = v),
                ),
                const ListTile(
                  title: Text(
                    'Sort by…',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
                for (final value in CatalogSort.values)
                  ListTile(
                    title: Text(
                      {
                        'name': 'Name',
                        'filename': 'File name',
                        'duration': 'Length',
                        'added': 'Insertion date',
                        'size': 'File size',
                      }[value.name]!,
                    ),
                    selected: sort == value,
                    trailing: Icon(
                      sort == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    onTap: () => update(() => sort = value),
                  ),
                SwitchListTile(
                  title: const Text('Descending order'),
                  value: descending,
                  onChanged: (v) => update(() => descending = v),
                ),
                ListTile(
                  leading: const Icon(Icons.shuffle),
                  title: const Text('Shuffle all visible media'),
                  onTap: () {
                    Navigator.pop(c);
                    LibraryActions.play(context, _items, shuffle: true);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    ),
  );
}
