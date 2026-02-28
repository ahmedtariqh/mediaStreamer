import 'dart:async';
import 'package:bonsoir/bonsoir.dart';

class NetworkDiscoveryService {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  final String _serviceType = '_mediastreamer._tcp';
  final List<ResolvedBonsoirService> _discoveredDevices = [];
  final StreamController<List<ResolvedBonsoirService>> _devicesController =
      StreamController<List<ResolvedBonsoirService>>.broadcast();

  Stream<List<ResolvedBonsoirService>> get devicesStream =>
      _devicesController.stream;
  List<ResolvedBonsoirService> get discoveredDevices => _discoveredDevices;

  /// Broadcast this device as a streaming server.
  Future<void> startBroadcast({
    required String deviceName,
    required int port,
  }) async {
    await stopBroadcast();

    final service = BonsoirService(
      name: deviceName,
      type: _serviceType,
      port: port,
      attributes: {'app': 'MediaStreamer'},
    );

    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.ready;
    await _broadcast!.start();
  }

  /// Stop broadcasting.
  Future<void> stopBroadcast() async {
    await _broadcast?.stop();
    _broadcast = null;
  }

  /// Discover other MediaStreamer devices on the network.
  Future<void> startDiscovery() async {
    await stopDiscovery();
    _discoveredDevices.clear();

    _discovery = BonsoirDiscovery(type: _serviceType);
    await _discovery!.ready;

    _discovery!.eventStream!.listen((event) {
      if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
        final resolved = event.service as ResolvedBonsoirService;
        if (!_discoveredDevices.any((d) => d.name == resolved.name)) {
          _discoveredDevices.add(resolved);
          _devicesController.add(List.from(_discoveredDevices));
        }
      } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
        _discoveredDevices.removeWhere((d) => d.name == event.service?.name);
        _devicesController.add(List.from(_discoveredDevices));
      }
    });

    await _discovery!.start();
  }

  /// Stop discovery.
  Future<void> stopDiscovery() async {
    await _discovery?.stop();
    _discovery = null;
  }

  void dispose() {
    stopBroadcast();
    stopDiscovery();
    _devicesController.close();
  }
}
