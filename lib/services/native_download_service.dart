import 'package:flutter/services.dart';

class NativeDownloadService {
  static const channel = MethodChannel('com.mediastreamer/downloads');

  Future<Map<String, dynamic>> extract(String url) async {
    final value = await channel.invokeMapMethod<String, dynamic>('extract', {
      'url': url,
    });
    if (value == null) throw StateError('No media information returned.');
    return value;
  }

  Future<void> enqueue(Map<String, dynamic> request) =>
      channel.invokeMethod('enqueue', request);
  Future<List<dynamic>> snapshot() async =>
      await channel.invokeListMethod<dynamic>('snapshot') ?? [];
  Future<void> command(String command, String id) =>
      channel.invokeMethod(command, {'id': id});
}
