import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BrowserBookmark {
  final String url;
  final String title;
  final DateTime addedAt;

  BrowserBookmark({
    required this.url,
    required this.title,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'addedAt': addedAt.toIso8601String(),
  };

  factory BrowserBookmark.fromJson(Map<String, dynamic> json) =>
      BrowserBookmark(
        url: json['url'],
        title: json['title'],
        addedAt: DateTime.parse(json['addedAt']),
      );
}

class BrowserHistoryItem {
  final String url;
  final String title;
  final DateTime visitedAt;

  BrowserHistoryItem({
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'visitedAt': visitedAt.toIso8601String(),
  };

  factory BrowserHistoryItem.fromJson(Map<String, dynamic> json) =>
      BrowserHistoryItem(
        url: json['url'],
        title: json['title'],
        visitedAt: DateTime.parse(json['visitedAt']),
      );
}

class BrowserStateService {
  static const String _bookmarksKey = 'browser_bookmarks';
  static const String _historyKey = 'browser_history';
  static const String _adBlockKey = 'browser_ad_block';
  static const String _desktopModeKey = 'browser_desktop_mode';

  static Future<List<BrowserBookmark>> getBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_bookmarksKey);
    if (data == null) return [];
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((j) => BrowserBookmark.fromJson(j)).toList();
  }

  static Future<void> addBookmark(String url, String title) async {
    final bookmarks = await getBookmarks();
    // Avoid exact duplicates
    if (!bookmarks.any((b) => b.url == url)) {
      bookmarks.insert(
        0,
        BrowserBookmark(url: url, title: title, addedAt: DateTime.now()),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _bookmarksKey,
        jsonEncode(bookmarks.map((b) => b.toJson()).toList()),
      );
    }
  }

  static Future<void> removeBookmark(String url) async {
    final bookmarks = await getBookmarks();
    bookmarks.removeWhere((b) => b.url == url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _bookmarksKey,
      jsonEncode(bookmarks.map((b) => b.toJson()).toList()),
    );
  }

  static Future<bool> isBookmarked(String url) async {
    final bookmarks = await getBookmarks();
    return bookmarks.any((b) => b.url == url);
  }

  static Future<List<BrowserHistoryItem>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString(_historyKey);
    if (data == null) return [];
    final List<dynamic> jsonList = jsonDecode(data);
    return jsonList.map((j) => BrowserHistoryItem.fromJson(j)).toList();
  }

  static Future<void> addHistory(String url, String title) async {
    final history = await getHistory();
    // Remove if exists to move it to the top
    history.removeWhere((item) => item.url == url);
    history.insert(
      0,
      BrowserHistoryItem(url: url, title: title, visitedAt: DateTime.now()),
    );

    // Keep only last 200 items
    if (history.length > 200) {
      history.removeRange(200, history.length);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(history.map((h) => h.toJson()).toList()),
    );
  }

  static Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }

  static Future<bool> getAdBlockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_adBlockKey) ?? true; // Default true
  }

  static Future<void> setAdBlockEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_adBlockKey, value);
  }

  static Future<bool> getDesktopModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_desktopModeKey) ?? false; // Default false
  }

  static Future<void> setDesktopModeEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_desktopModeKey, value);
  }
}
