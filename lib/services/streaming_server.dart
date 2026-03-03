import 'dart:io';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;

class StreamingServer {
  HttpServer? _server;
  String? _currentFilePath;
  int _port = 8080;

  bool get isRunning => _server != null;
  int get port => _port;

  /// Start the HTTP server to serve a video file with an HTML player page.
  Future<String> startServer(String filePath, {int port = 8080}) async {
    if (_server != null) await stopServer();

    _currentFilePath = filePath;
    _port = port;

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addHandler(_handleRequest);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
    _server!.autoCompress = false; // Don't compress video streams

    final ip = await getLocalIp();
    return 'http://$ip:$_port';
  }

  /// Determine MIME type from file extension.
  String _getMimeType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.mp4':
        return 'video/mp4';
      case '.webm':
        return 'video/webm';
      case '.mkv':
        return 'video/x-matroska';
      case '.avi':
        return 'video/x-msvideo';
      case '.mov':
        return 'video/quicktime';
      case '.flv':
        return 'video/x-flv';
      case '.m4v':
        return 'video/mp4';
      case '.ts':
        return 'video/mp2t';
      case '.3gp':
        return 'video/3gpp';
      case '.m4a':
        return 'audio/mp4';
      case '.mp3':
        return 'audio/mpeg';
      case '.ogg':
        return 'audio/ogg';
      case '.flac':
        return 'audio/flac';
      case '.wav':
        return 'audio/wav';
      default:
        return 'application/octet-stream';
    }
  }

  /// Handle HTTP requests.
  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    final path = request.url.path;

    // Serve HTML player page at root
    if (path.isEmpty || path == '/') {
      return _servePlayerPage();
    }

    // Serve the video file at /stream
    if (path == 'stream') {
      return _serveVideoFile(request);
    }

    return shelf.Response.notFound('Not found');
  }

  /// Serve an HTML page with an embedded video player.
  shelf.Response _servePlayerPage() {
    if (_currentFilePath == null) {
      return shelf.Response.ok(
        '<html><body style="background:#111;color:#fff;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0"><h1>No video is being streamed</h1></body></html>',
        headers: {'Content-Type': 'text/html; charset=utf-8'},
      );
    }

    final fileName = p.basename(_currentFilePath!);
    final mimeType = _getMimeType(_currentFilePath!);

    final html =
        '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>MediaStreamer - $fileName</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #0a0a1a;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 20px;
    }
    .container {
      max-width: 960px;
      width: 100%;
    }
    .header {
      text-align: center;
      margin-bottom: 24px;
    }
    .header h1 {
      font-size: 1.4em;
      font-weight: 600;
      color: #6C63FF;
      margin-bottom: 4px;
    }
    .header p {
      color: #888;
      font-size: 0.9em;
    }
    .player-wrapper {
      background: #111;
      border-radius: 16px;
      overflow: hidden;
      box-shadow: 0 8px 32px rgba(108, 99, 255, 0.15);
      border: 1px solid rgba(255,255,255,0.06);
    }
    video {
      width: 100%;
      max-height: 80vh;
      display: block;
      background: #000;
    }
    .title-bar {
      padding: 12px 16px;
      background: rgba(255,255,255,0.03);
      border-top: 1px solid rgba(255,255,255,0.06);
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .title-bar .icon {
      width: 36px;
      height: 36px;
      background: linear-gradient(135deg, #6C63FF, #00D9FF);
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 18px;
    }
    .title-bar .info {
      flex: 1;
    }
    .title-bar .info .name {
      font-size: 0.95em;
      font-weight: 500;
    }
    .title-bar .info .meta {
      font-size: 0.8em;
      color: #666;
    }
    .footer {
      text-align: center;
      margin-top: 16px;
      color: #444;
      font-size: 0.8em;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>📡 MediaStreamer</h1>
      <p>Now streaming</p>
    </div>
    <div class="player-wrapper">
      <video controls autoplay>
        <source src="/stream" type="$mimeType">
        Your browser does not support the video tag.
      </video>
      <div class="title-bar">
        <div class="icon">▶</div>
        <div class="info">
          <div class="name">$fileName</div>
          <div class="meta">Streaming from MediaStreamer</div>
        </div>
      </div>
    </div>
    <div class="footer">
      Open this URL on any device on the same network to watch
    </div>
  </div>
</body>
</html>
''';

    return shelf.Response.ok(
      html,
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  /// Serve the actual video file with range request support.
  Future<shelf.Response> _serveVideoFile(shelf.Request request) async {
    if (_currentFilePath == null) {
      return shelf.Response.notFound('No video available');
    }

    final file = File(_currentFilePath!);
    if (!await file.exists()) {
      return shelf.Response.notFound('Video file not found');
    }

    final fileSize = await file.length();
    final mimeType = _getMimeType(_currentFilePath!);
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
            'Content-Type': mimeType,
            'Content-Range': 'bytes $start-$end/$fileSize',
            'Content-Length': '${end - start + 1}',
            'Accept-Ranges': 'bytes',
            'Access-Control-Allow-Origin': '*',
          },
        );
      }
    }

    // Full file response
    return shelf.Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': mimeType,
        'Content-Length': '$fileSize',
        'Accept-Ranges': 'bytes',
        'Access-Control-Allow-Origin': '*',
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
