import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

class WebhookService {
  static Timer? _timer;
  static final ValueNotifier<String> lastStatus = ValueNotifier('');
  static final ValueNotifier<bool> isSending = ValueNotifier(false);

  // ── Pref keys ──
  static const _kEnabled = 'webhookEnabled';
  static const _kUrl = 'webhookUrl';
  static const _kIntervalMinutes = 'webhookIntervalMinutes';
  static const _kSendNotes = 'webhookSendNotes';
  static const _kSendLinks = 'webhookSendLinks';
  static const _kDeleteAfterSend = 'webhookDeleteAfterSend';

  // ── Lifecycle ──

  /// Starts the periodic timer if webhook is enabled.
  static Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kEnabled) ?? false;
    if (!enabled) return;
    final minutes = prefs.getInt(_kIntervalMinutes) ?? 60;
    _timer?.cancel();
    _timer = Timer.periodic(Duration(minutes: minutes), (_) => sendNow());
  }

  /// Stops the periodic timer.
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Restarts with current settings (call after settings change).
  static Future<void> restart() async {
    stop();
    await start();
  }

  // ── Send logic ──

  /// Immediately sends notes/links to the configured webhook URL.
  /// Returns `true` on success.
  static Future<bool> sendNow() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kUrl) ?? '';
    if (url.isEmpty) {
      lastStatus.value = 'No webhook URL configured';
      return false;
    }

    final sendNotes = prefs.getBool(_kSendNotes) ?? true;
    final sendLinks = prefs.getBool(_kSendLinks) ?? true;
    final deleteAfter = prefs.getBool(_kDeleteAfterSend) ?? false;

    if (!sendNotes && !sendLinks) {
      lastStatus.value = 'Nothing to send (notes & links both disabled)';
      return false;
    }

    isSending.value = true;
    try {
      final notes = sendNotes ? await DatabaseService.getNotes() : [];
      final links = sendLinks ? await DatabaseService.getLinks() : [];

      if (notes.isEmpty && links.isEmpty) {
        lastStatus.value = 'No data to send';
        isSending.value = false;
        return true;
      }

      final payload = <String, dynamic>{
        'sentAt': DateTime.now().toUtc().toIso8601String(),
      };
      if (sendNotes) {
        payload['videoNotes'] = notes
            .map((n) => n.toMap()..remove('id'))
            .toList();
      }
      if (sendLinks) {
        payload['youtubeLinks'] = links.map((l) => l.toJson()).toList();
      }

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: const JsonEncoder.withIndent('  ').convert(payload),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Success – optionally delete sent data
        if (deleteAfter) {
          if (sendNotes) {
            for (final note in notes) {
              if (note.id != null) await DatabaseService.deleteNote(note.id!);
            }
          }
          if (sendLinks) {
            for (final link in links) {
              if (link.id != null) await DatabaseService.deleteLink(link.id!);
            }
          }
        }
        final ts = _timeString();
        lastStatus.value =
            '✓ Sent at $ts'
            '${deleteAfter ? ' (data deleted)' : ''}';
        isSending.value = false;
        return true;
      } else {
        lastStatus.value = '✗ HTTP ${response.statusCode} at ${_timeString()}';
        isSending.value = false;
        return false;
      }
    } catch (e) {
      lastStatus.value = '✗ Error: ${e.toString().split('\n').first}';
      isSending.value = false;
      return false;
    }
  }

  static String _timeString() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
