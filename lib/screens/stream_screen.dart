import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import '../services/streaming_server.dart';
import '../services/network_discovery_service.dart';
import 'player_screen.dart';

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
  StreamSubscription<List<BonsoirService>>? _devicesSub;
  List<BonsoirService> _devices = [];

  @override
  void initState() {
    super.initState();
    _loadIp();
    _startDiscovery();

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
    _devicesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadIp() async {
    final ip = await StreamingServer.getLocalIp();
    if (mounted) setState(() => _localIp = ip);
  }

  void _startDiscovery() {
    _devicesSub = _discovery.devicesStream.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
    _discovery.startDiscovery();
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

  void _connectToDevice(BonsoirService service) {
    final ip = service.host ?? '0.0.0.0';
    final port = service.port;
    final url = 'http://$ip:$port/video.mp4';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          filePath: url,
          title: 'Stream from ${service.name}',
          youtubeUrl: '',
        ),
      ),
    );
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
            // Server status card
            _buildServerCard(theme),
            const SizedBox(height: 24),
            // Discovered devices
            _buildDevicesSection(theme),
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

  Widget _buildDevicesSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.devices, color: theme.colorScheme.secondary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Nearby Devices',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                _discovery.startDiscovery();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Scan'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_devices.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                const Icon(Icons.search, size: 40, color: Colors.white24),
                const SizedBox(height: 12),
                Text(
                  'Scanning for devices...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Make sure other devices are on the same WiFi',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white24,
                  ),
                ),
              ],
            ),
          )
        else
          ...List.generate(_devices.length, (index) {
            final device = _devices[index];
            return Card(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.phone_android,
                    color: theme.colorScheme.primary,
                  ),
                ),
                title: Text(device.name),
                subtitle: Text(
                  '${device.host ?? "resolving..."}:${device.port}',
                ),
                trailing: ElevatedButton(
                  onPressed: device.host != null
                      ? () => _connectToDevice(device)
                      : null,
                  child: const Text('Connect'),
                ),
              ),
            );
          }),
      ],
    );
  }
}
