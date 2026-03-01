import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/video_note.dart';
import '../models/youtube_link.dart';
import '../models/playlist.dart';
import '../models/playlist_item.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'media_streamer.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2Tables(db);
        }
      },
    );
  }

  static Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE video_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        youtubeUrl TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT NOT NULL,
        dateWatched TEXT NOT NULL
      )
    ''');
    await _createV2Tables(db);
  }

  static Future<void> _createV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS youtube_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT NOT NULL DEFAULT '',
        dateAdded TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        dateCreated TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS playlist_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlistId INTEGER NOT NULL,
        type INTEGER NOT NULL,
        path TEXT NOT NULL DEFAULT '',
        linkId INTEGER,
        title TEXT NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (playlistId) REFERENCES playlists(id) ON DELETE CASCADE,
        FOREIGN KEY (linkId) REFERENCES youtube_links(id) ON DELETE SET NULL
      )
    ''');
  }

  // ─── Video Notes ─────────────────────────────────────────────

  static Future<int> saveNote(VideoNote note) async {
    final db = await database;
    return db.insert('video_notes', note.toMap());
  }

  static Future<List<VideoNote>> getNotes() async {
    final db = await database;
    final maps = await db.query('video_notes', orderBy: 'dateWatched DESC');
    return maps.map((map) => VideoNote.fromMap(map)).toList();
  }

  static Future<int> updateNote(VideoNote note) async {
    final db = await database;
    return db.update(
      'video_notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  static Future<int> deleteNote(int id) async {
    final db = await database;
    return db.delete('video_notes', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<VideoNote>> searchNotes(String query) async {
    final db = await database;
    final maps = await db.query(
      'video_notes',
      where: 'title LIKE ? OR notes LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'dateWatched DESC',
    );
    return maps.map((map) => VideoNote.fromMap(map)).toList();
  }

  // ─── YouTube Links ───────────────────────────────────────────

  static Future<int> saveLink(YoutubeLink link) async {
    final db = await database;
    return db.insert('youtube_links', link.toMap());
  }

  static Future<List<YoutubeLink>> getLinks() async {
    final db = await database;
    final maps = await db.query('youtube_links', orderBy: 'dateAdded DESC');
    return maps.map((map) => YoutubeLink.fromMap(map)).toList();
  }

  static Future<int> updateLink(YoutubeLink link) async {
    final db = await database;
    return db.update(
      'youtube_links',
      link.toMap(),
      where: 'id = ?',
      whereArgs: [link.id],
    );
  }

  static Future<int> deleteLink(int id) async {
    final db = await database;
    return db.delete('youtube_links', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<YoutubeLink>> searchLinks(String query) async {
    final db = await database;
    final maps = await db.query(
      'youtube_links',
      where: 'title LIKE ? OR url LIKE ? OR notes LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'dateAdded DESC',
    );
    return maps.map((map) => YoutubeLink.fromMap(map)).toList();
  }

  // ─── Playlists ───────────────────────────────────────────────

  static Future<int> createPlaylist(Playlist playlist) async {
    final db = await database;
    return db.insert('playlists', playlist.toMap());
  }

  static Future<List<Playlist>> getPlaylists() async {
    final db = await database;
    final maps = await db.query('playlists', orderBy: 'dateCreated DESC');
    return maps.map((map) => Playlist.fromMap(map)).toList();
  }

  static Future<int> renamePlaylist(int id, String newName) async {
    final db = await database;
    return db.update(
      'playlists',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> deletePlaylist(int id) async {
    final db = await database;
    // Delete items first, then the playlist
    await db.delete('playlist_items', where: 'playlistId = ?', whereArgs: [id]);
    return db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> getPlaylistItemCount(int playlistId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM playlist_items WHERE playlistId = ?',
      [playlistId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ─── Playlist Items ──────────────────────────────────────────

  static Future<int> addToPlaylist(PlaylistItem item) async {
    final db = await database;
    // Get current max sortOrder
    final result = await db.rawQuery(
      'SELECT MAX(sortOrder) as maxSort FROM playlist_items WHERE playlistId = ?',
      [item.playlistId],
    );
    final maxSort = (result.first['maxSort'] as int?) ?? -1;
    final newItem = item.copyWith(sortOrder: maxSort + 1);
    return db.insert('playlist_items', newItem.toMap());
  }

  static Future<List<PlaylistItem>> getPlaylistItems(int playlistId) async {
    final db = await database;
    final maps = await db.query(
      'playlist_items',
      where: 'playlistId = ?',
      whereArgs: [playlistId],
      orderBy: 'sortOrder ASC',
    );
    return maps.map((map) => PlaylistItem.fromMap(map)).toList();
  }

  static Future<int> removeFromPlaylist(int itemId) async {
    final db = await database;
    return db.delete('playlist_items', where: 'id = ?', whereArgs: [itemId]);
  }

  static Future<void> reorderPlaylistItems(
    int playlistId,
    List<int> itemIds,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (var i = 0; i < itemIds.length; i++) {
      batch.update(
        'playlist_items',
        {'sortOrder': i},
        where: 'id = ?',
        whereArgs: [itemIds[i]],
      );
    }
    await batch.commit(noResult: true);
  }

  // ─── Export ──────────────────────────────────────────────────

  static Future<String> exportNotesAsJson() async {
    final notes = await getNotes();
    final links = await getLinks();

    final data = {
      'exportDate': DateTime.now().toIso8601String(),
      'videoNotes': notes.map((n) => n.toMap()..remove('id')).toList(),
      'youtubeLinks': links.map((l) => l.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }
}
