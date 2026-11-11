import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MediaPreferences extends ChangeNotifier {
  static final instance = MediaPreferences._();
  MediaPreferences._();
  late SharedPreferences _prefs;
  Set<String> favorites = {}, watched = {};
  Map<String, dynamic> controls = {
    'gestures': true,
    'skipSeconds': 10,
    'holdSpeed': 2.0,
    'autoHide': 4,
    'autoPip': false,
    'resume': true,
    'hardware': 'auto',
    'networkCaching': 1500,
  };
  Map<String, List<Map<String, dynamic>>> bookmarks = {};
  List<Map<String, String>> locations = [];
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    controls['resume'] = _prefs.getBool('resumePlayback') ?? true;
    favorites = (_prefs.getStringList('mediaFavorites') ?? []).toSet();
    watched = (_prefs.getStringList('mediaWatched') ?? []).toSet();
    try {
      controls.addAll(jsonDecode(_prefs.getString('playerControls') ?? '{}'));
      final b = jsonDecode(_prefs.getString('mediaBookmarks') ?? '{}') as Map;
      bookmarks = b.map(
        (k, v) => MapEntry(
          k.toString(),
          (v as List).map((x) => Map<String, dynamic>.from(x)).toList(),
        ),
      );
      locations =
          (jsonDecode(_prefs.getString('networkLocations') ?? '[]') as List)
              .map((m) => Map<String, String>.from(m))
              .toList();
    } catch (_) {}
  }

  Future<void> favorite(String uri) async {
    if (!favorites.remove(uri)) favorites.add(uri);
    await _prefs.setStringList('mediaFavorites', favorites.toList());
    notifyListeners();
  }

  Future<void> markWatched(String uri) async {
    watched.add(uri);
    await _prefs.setStringList('mediaWatched', watched.toList());
    notifyListeners();
  }

  Future<void> settings(Map<String, dynamic> values) async {
    controls.addAll(values);
    await _prefs.setString('playerControls', jsonEncode(controls));
    if (values.containsKey('resume')) {
      await _prefs.setBool('resumePlayback', controls['resume'] as bool);
    }
    notifyListeners();
  }

  Future<void> bookmark(String uri, int position, String title) async {
    (bookmarks[uri] ??= []).add({'position': position, 'title': title});
    bookmarks[uri]!.sort(
      (a, b) => (a['position'] as int).compareTo(b['position'] as int),
    );
    await saveBookmarks();
  }

  Future<void> removeBookmark(String uri, int i) async {
    bookmarks[uri]?.removeAt(i);
    await saveBookmarks();
  }

  Future<void> saveBookmarks() async {
    await _prefs.setString('mediaBookmarks', jsonEncode(bookmarks));
    notifyListeners();
  }

  Future<void> relocate(String old, String uri) async {
    if (favorites.remove(old)) favorites.add(uri);
    if (watched.remove(old)) watched.add(uri);
    final marks = bookmarks.remove(old);
    if (marks != null) bookmarks[uri] = marks;
    await _prefs.setStringList('mediaFavorites', favorites.toList());
    await _prefs.setStringList('mediaWatched', watched.toList());
    await saveBookmarks();
  }

  Future<void> saveLocation(String uri, String name) async {
    locations.removeWhere((x) => x['uri'] == uri);
    locations.add({'uri': uri, 'name': name});
    await _prefs.setString('networkLocations', jsonEncode(locations));
    notifyListeners();
  }

  Future<void> removeLocation(String uri) async {
    locations.removeWhere((x) => x['uri'] == uri);
    await _prefs.setString('networkLocations', jsonEncode(locations));
    notifyListeners();
  }
}
