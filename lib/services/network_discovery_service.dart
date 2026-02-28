import 'dart:async';
import 'package:bonsoir/bonsoir.dart';

class NetworkDiscoveryService {
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;

  final String _serviceType = '_mediastr._tcp';
  final List<BonsoirService> _discoveredDevices = [];
  final StreamController<List<BonsoirService>> _devicesController =
      StreamController<List<BonsoirService>>.broadcast();

  Stream<List<BonsoirService>> get devicesStream => _devicesController.stream;
  List<BonsoirService> get discoveredDevices => _discoveredDevices;

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
      attributes: {'app': 'MediaStr'},
    );

    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();
  }

  /// Stop broadcasting.
  Future<void> stopBroadcast() async {
    if (_broadcast != null && !_broadcast!.isStopped) {
      await _broadcast!.stop();
    }
    _broadcast = null;
  }

  /// Discover other MediaStreamer devices on the network.
  Future<void> startDiscovery() async {
    await stopDiscovery();
    _discoveredDevices.clear();

    _discovery = BonsoirDiscovery(type: _serviceType);
    await _discovery!.initialize();

    _discovery!.eventStream!.listen((event) {
      if (event is BonsoirDiscoveryServiceResolvedEvent) {
        final resolved = event.service;
        if (!_discoveredDevices.any((d) => d.name == resolved.name)) {
          _discoveredDevices.add(resolved);
          _devicesController.add(List.from(_discoveredDevices));
        }
      } else if (event is BonsoirDiscoveryServiceLostEvent) {
        _discoveredDevices.removeWhere((d) => d.name == event.service.name);
        _devicesController.add(List.from(_discoveredDevices));
      }
    });

    await _discovery!.start();
  }

  /// Stop discovery.
  Future<void> stopDiscovery() async {
    if (_discovery != null && !_discovery!.isStopped) {
      await _discovery!.stop();
    }
    _discovery = null;
  }

  void dispose() {
    stopBroadcast();
    stopDiscovery();
    _devicesController.close();
  }
}
