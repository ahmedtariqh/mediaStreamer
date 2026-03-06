import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/material.dart';
import '../services/network_discovery_service.dart';
import 'player_screen.dart';

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  final NetworkDiscoveryService _discovery = NetworkDiscoveryService();
  StreamSubscription<List<BonsoirService>>? _devicesSub;
  List<BonsoirService> _devices = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _devicesSub = _discovery.devicesStream.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });
    _startScan();
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _discovery.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() => _isScanning = true);
    await _discovery.startDiscovery();
    // Give it a moment for UI feedback
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) setState(() => _isScanning = false);
  }

  void _connectToDevice(BonsoirService service) {
    final ip = service.host ?? '0.0.0.0';
    final port = service.port;
    final url = 'http://$ip:$port/stream';

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

  void _connectManually() {
    final ipController = TextEditingController();
    final portController = TextEditingController(text: '8080');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Manual Connection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the IP address and port shown on the streaming device.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.100',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: portController,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '8080',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final ip = ipController.text.trim();
              final port = portController.text.trim();
              if (ip.isEmpty) return;
              Navigator.pop(ctx);
              final url = 'http://$ip:$port/stream';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PlayerScreen(
                    filePath: url,
                    title: 'Stream from $ip',
                    youtubeUrl: '',
                  ),
                ),
              );
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            onPressed: _connectManually,
            tooltip: 'Manual IP entry',
          ),
          IconButton(
            icon: _isScanning
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _startScan,
            tooltip: 'Scan for devices',
          ),
        ],
      ),
      body: _devices.isEmpty
          ? _buildEmptyState(theme)
          : _buildDeviceList(theme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                    theme.colorScheme.secondary.withValues(alpha: 0.1),
                  ],
                ),
              ),
              child: Icon(
                Icons.cast_connected,
                size: 64,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isScanning ? 'Scanning for devices...' : 'No Devices Found',
              style: theme.textTheme.titleLarge?.copyWith(
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Make sure another device is streaming\non the same WiFi network',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white38,
              ),
            ),
            if (_isScanning) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
            ] else ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _startScan,
                icon: const Icon(Icons.search),
                label: const Text('Scan Again'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _connectManually,
                icon: const Icon(Icons.keyboard),
                label: const Text('Enter IP Manually'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _devices.length,
      itemBuilder: (context, index) {
        final device = _devices[index];
        final hasHost = device.host != null && device.host!.isNotEmpty;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.2),
                    theme.colorScheme.secondary.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.phone_android,
                color: theme.colorScheme.primary,
              ),
            ),
            title: Text(device.name, style: theme.textTheme.titleMedium),
            subtitle: Text(
              hasHost ? '${device.host}:${device.port}' : 'Resolving...',
              style: theme.textTheme.bodySmall?.copyWith(
                color: hasHost ? Colors.white38 : Colors.amber,
              ),
            ),
            trailing: ElevatedButton.icon(
              onPressed: hasHost ? () => _connectToDevice(device) : null,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(hasHost ? 'Connect' : 'Wait...'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
