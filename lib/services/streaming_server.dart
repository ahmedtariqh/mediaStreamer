import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:network_info_plus/network_info_plus.dart';

class StreamingServer {
  HttpServer? _server;
  String? _currentFilePath;
  int _port = 8080;

  bool get isRunning => _server != null;
  int get port => _port;

  /// Start the HTTP server to serve a single video file.
  Future<String> startServer(String filePath, {int port = 8080}) async {
    if (_server != null) await stopServer();

    _currentFilePath = filePath;
    _port = port;

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handleRequest);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
    _server!.autoCompress = true;

    final ip = await getLocalIp();
    return 'http://$ip:$_port/video.mp4';
  }

  /// Handle HTTP requests with range support for video seeking.
  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    if (request.url.path != 'video.mp4') {
      return shelf.Response.notFound('Not found');
    }

    if (_currentFilePath == null) {
      return shelf.Response.notFound('No video available');
    }

    final file = File(_currentFilePath!);
    if (!await file.exists()) {
      return shelf.Response.notFound('Video file not found');
    }

    final fileSize = await file.length();
    final rangeHeader = request.headers['range'];

    if (rangeHeader != null) {
      // Handle range request for seeking
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        final start = int.parse(match.group(1)!);
        final end = match.group(2)!.isNotEmpty
            ? int.parse(match.group(2)!)
            : fileSize - 1;

        final stream = file.openRead(start, end + 1);

        return shelf.Response(
          206,
          body: stream,
          headers: {
            'Content-Type': 'video/mp4',
            'Content-Range': 'bytes $start-$end/$fileSize',
            'Content-Length': '${end - start + 1}',
            'Accept-Ranges': 'bytes',
          },
        );
      }
    }

    // Full file response
    return shelf.Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': 'video/mp4',
        'Content-Length': '$fileSize',
        'Accept-Ranges': 'bytes',
      },
    );
  }

  /// Stop the server.
  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _currentFilePath = null;
  }

  /// Get the local WiFi IP address.
  static Future<String> getLocalIp() async {
    final info = NetworkInfo();
    final ip = await info.getWifiIP();
    return ip ?? '0.0.0.0';
  }
}
