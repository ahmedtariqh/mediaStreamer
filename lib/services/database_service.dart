import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/video_note.dart';

class DatabaseService {
  static Database? _database;
  static const String _tableName = 'video_notes';

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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            youtubeUrl TEXT NOT NULL,
            title TEXT NOT NULL,
            notes TEXT NOT NULL,
            dateWatched TEXT NOT NULL
          )
        ''');
      },
    );
  }

  static Future<int> saveNote(VideoNote note) async {
    final db = await database;
    return db.insert(_tableName, note.toMap());
  }

  static Future<List<VideoNote>> getNotes() async {
    final db = await database;
    final maps = await db.query(_tableName, orderBy: 'dateWatched DESC');
    return maps.map((map) => VideoNote.fromMap(map)).toList();
  }

  static Future<int> updateNote(VideoNote note) async {
    final db = await database;
    return db.update(
      _tableName,
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  static Future<int> deleteNote(int id) async {
    final db = await database;
    return db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<VideoNote>> searchNotes(String query) async {
    final db = await database;
    final maps = await db.query(
      _tableName,
      where: 'title LIKE ? OR notes LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'dateWatched DESC',
    );
    return maps.map((map) => VideoNote.fromMap(map)).toList();
  }
}
