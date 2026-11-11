import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/playlist.dart';
import '../models/playlist_item.dart';
import '../services/database_service.dart';
import 'media_entry.dart';
import 'media_preferences.dart';
import 'playback_controller.dart';
import 'player_screen.dart';

class LibraryActions {
  static void error(BuildContext c, Object e) {
    if (c.mounted) {
      ScaffoldMessenger.of(
        c,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  static Future<String?> text(
    BuildContext c,
    String title, {
    String initial = '',
    String? hint,
  }) async {
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // A closing dialog can still animate with its controller attached.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return value;
  }

  static Future<void> play(
    BuildContext c,
    List<MediaEntry> items, {
    int index = 0,
    bool shuffle = false,
  }) async {
    if (items.isEmpty) return;
    try {
      await PlaybackController.instance.open(
        items,
        index: index,
        shuffle: shuffle,
      );
      if (c.mounted) {
        await Navigator.push(
          c,
          MaterialPageRoute(builder: (_) => const MediaPlayerScreen()),
        );
      }
    } catch (e) {
      if (c.mounted) error(c, e);
    }
  }

  static Future<void> savePlaylist(
    BuildContext c,
    List<MediaEntry> items,
  ) async {
    if (items.isEmpty) return;
    final playlists = await DatabaseService.getPlaylists();
    if (!c.mounted) return;
    final id = await showModalBottomSheet<int>(
      context: c,
      isScrollControlled: true,
      builder: (d) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Save to playlist')),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New playlist'),
              onTap: () => Navigator.pop(d, -1),
            ),
            ...playlists.map(
              (p) => ListTile(
                title: Text(p.name),
                onTap: () => Navigator.pop(d, p.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (id == null || !c.mounted) return;
    var playlistId = id;
    if (id == -1) {
      final name = await text(c, 'Playlist name');
      if (name == null || name.isEmpty) return;
      playlistId = await DatabaseService.createPlaylist(
        Playlist(name: name, dateCreated: DateTime.now()),
      );
    }
    for (final m in items) {
      await DatabaseService.addToPlaylist(
        PlaylistItem(
          playlistId: playlistId,
          type: PlaylistItemType.localFile,
          path: m.uri,
          title: m.title,
        ),
      );
    }
    if (c.mounted) {
      ScaffoldMessenger.of(
        c,
      ).showSnackBar(const SnackBar(content: Text('Playlist saved')));
    }
  }

  static Future<void> exportPlaylist(
    BuildContext c,
    List<MediaEntry> items,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File(
        '${dir.path}/MediaStreamer-${DateTime.now().millisecondsSinceEpoch}.m3u',
      );
      await f.writeAsString(exportM3u(items));
      await Share.shareXFiles([XFile(f.path)], text: 'MediaStreamer playlist');
    } catch (e) {
      if (c.mounted) error(c, e);
    }
  }

  static Future<void> importPlaylist(BuildContext c) async {
    try {
      final files = await PlaybackController.instance.pick('pickPlaylist');
      if (files.isEmpty) return;
      final text = await PlaybackController.channel.invokeMethod<String>(
        'readText',
        {'uri': files.first.uri},
      );
      final items = parsePlaylist(text ?? '', baseUri: files.first.uri);
      if (!c.mounted) return;
      if (items.isEmpty) {
        throw StateError(
          'No playable locations found. Document playlists need absolute file paths or stream URLs.',
        );
      }
      await savePlaylist(c, items);
    } catch (e) {
      if (c.mounted) error(c, e);
    }
  }

  static Future<void> network(BuildContext c) async {
    final prefs = MediaPreferences.instance;
    await showModalBottomSheet<void>(
      context: c,
      isScrollControlled: true,
      builder: (d) => SafeArea(
        child: ListenableBuilder(
          listenable: prefs,
          builder: (d, _) => ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Network streams & locations'),
                subtitle: Text(
                  'HTTP · HTTPS · RTSP · RTMP · SMB · FTP · NFS · UDP',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Open a location'),
                onTap: () async {
                  final uri = await text(
                    d,
                    'Stream or media URL',
                    hint: 'https://… or smb://server/share/movie.mkv',
                  );
                  if (uri == null || uri.isEmpty || !d.mounted) return;
                  final parsed = Uri.tryParse(uri);
                  if (parsed == null ||
                      !{
                        'http',
                        'https',
                        'rtsp',
                        'rtmp',
                        'rtp',
                        'udp',
                        'smb',
                        'ftp',
                        'sftp',
                        'nfs',
                      }.contains(parsed.scheme)) {
                    error(d, 'Enter a supported stream or media location');
                    return;
                  }
                  final name = await text(
                    d,
                    'Location name',
                    initial: parsed.host,
                  );
                  if (name == null || !d.mounted) return;
                  await prefs.saveLocation(uri, name);
                  if (d.mounted) {
                    Navigator.pop(d);
                    if (c.mounted) {
                      await play(c, [
                        MediaEntry(uri: uri, title: name.isEmpty ? uri : name),
                      ]);
                    }
                  }
                },
              ),
              ...prefs.locations.map(
                (l) => ListTile(
                  leading: const Icon(Icons.public),
                  title: Text(l['name']!),
                  subtitle: Text(
                    Uri.tryParse(l['uri']!)?.replace(userInfo: '').toString() ??
                        '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove location',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => prefs.removeLocation(l['uri']!),
                  ),
                  onTap: () {
                    Navigator.pop(d);
                    play(c, [MediaEntry(uri: l['uri']!, title: l['name']!)]);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<bool> delete(BuildContext c, MediaEntry m) async {
    final ok = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: const Text('Delete media?'),
        content: Text(m.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    try {
      if (PlaybackController.instance.current?.uri == m.uri) {
        await PlaybackController.instance.command('stop');
      }
      await PlaybackController.channel.invokeMethod('deleteMedia', m.toMap());
      await DatabaseService.deletePlaybackPosition(m.uri);
      return true;
    } catch (e) {
      if (c.mounted) error(c, e);
      return false;
    }
  }
}
