import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class DownloadNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// Show or update a download progress notification.
  static Future<void> showProgress({
    required int id,
    required String title,
    required int progress,
    required String body,
  }) async {
    await init();
    final androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Download progress notifications',
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: progress,
      ongoing: true,
      autoCancel: false,
      icon: '@mipmap/launcher_icon',
    );
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Show a download-complete notification.
  static Future<void> showComplete({
    required int id,
    required String title,
    required String filePath,
  }) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Download progress notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/launcher_icon',
    );
    await _plugin.show(
      id,
      '✅ $title',
      'Download complete',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Show a download-failed notification.
  static Future<void> showFailed({
    required int id,
    required String title,
    String? error,
  }) async {
    await init();
    const androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Download progress notifications',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/launcher_icon',
    );
    await _plugin.show(
      id,
      '❌ $title',
      error ?? 'Download failed',
      const NotificationDetails(android: androidDetails),
    );
  }

  /// Cancel a notification.
  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }
}
