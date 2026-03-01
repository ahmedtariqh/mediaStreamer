import 'dart:async';
import 'package:flutter/material.dart';
import '../services/streaming_server.dart';
import '../services/network_discovery_service.dart';

class StreamScreen extends StatefulWidget {
  final String? filePath;
  final String? title;

  const StreamScreen({super.key, this.filePath, this.title});

  @override
  State<StreamScreen> createState() => _StreamScreenState();
}

class _StreamScreenState extends State<StreamScreen> {
  final StreamingServer _server = StreamingServer();
  final NetworkDiscoveryService _discovery = NetworkDiscoveryService();
  String? _streamUrl;
  bool _isStarting = false;
  String _localIp = '...';

  @override
  void initState() {
    super.initState();
    _loadIp();

    // Auto-start server if filePath is provided
    if (widget.filePath != null) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _startServer();
      });
    }
  }

  @override
  void dispose() {
    _server.stopServer();
    _discovery.dispose();
    super.dispose();
  }

  Future<void> _loadIp() async {
    final ip = await StreamingServer.getLocalIp();
    if (mounted) setState(() => _localIp = ip);
  }

  Future<void> _startServer() async {
    if (widget.filePath == null) return;

    setState(() => _isStarting = true);

    try {
      final url = await _server.startServer(widget.filePath!);
      await _discovery.startBroadcast(
        deviceName: 'MediaStreamer-${DateTime.now().millisecondsSinceEpoch}',
        port: _server.port,
      );

      if (mounted) {
        setState(() {
          _streamUrl = url;
          _isStarting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error starting server: $e')));
      }
    }
  }

  Future<void> _stopServer() async {
    await _server.stopServer();
    await _discovery.stopBroadcast();
    if (mounted) setState(() => _streamUrl = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Stream')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildServerCard(theme),
            const SizedBox(height: 24),
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.secondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Other devices can receive this stream from the Receive tab',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard(ThemeData theme) {
    final isRunning = _server.isRunning;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: isRunning
            ? LinearGradient(
                colors: [
                  theme.colorScheme.primary.withValues(alpha: 0.2),
                  theme.colorScheme.secondary.withValues(alpha: 0.1),
                ],
              )
            : null,
        color: isRunning ? null : theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRunning
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : Colors.white10,
        ),
      ),
      child: Column(
        children: [
          // Status icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isRunning
                  ? theme.colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.white10,
            ),
            child: Icon(
              isRunning ? Icons.cast_connected : Icons.cast,
              size: 40,
              color: isRunning ? theme.colorScheme.primary : Colors.white38,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isRunning ? 'Streaming Active' : 'Server Offline',
            style: theme.textTheme.titleLarge?.copyWith(
              color: isRunning ? theme.colorScheme.primary : Colors.white54,
            ),
          ),
          const SizedBox(height: 8),
          if (isRunning && _streamUrl != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(
                _streamUrl!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Other devices can connect to this URL',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
            if (widget.title != null) ...[
              const SizedBox(height: 8),
              Text(
                'Playing: ${widget.title}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ] else ...[
            Text(
              'Your IP: $_localIp',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
            ),
          ],
          const SizedBox(height: 20),
          if (widget.filePath != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isStarting
                    ? null
                    : (isRunning ? _stopServer : _startServer),
                icon: _isStarting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(isRunning ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _isStarting
                      ? 'Starting...'
                      : (isRunning ? 'Stop Server' : 'Start Streaming'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning
                      ? Colors.redAccent
                      : theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            )
          else
            Text(
              'Select a video from Downloads to stream',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white38,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
