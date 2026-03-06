import 'dart:async';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

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
    debugPrint('[Discovery] Broadcasting: $deviceName on port $port');
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
    _devicesController.add([]);

    _discovery = BonsoirDiscovery(type: _serviceType);
    await _discovery!.initialize();

    _discovery!.eventStream!.listen((event) {
      debugPrint(
        '[Discovery] Event: ${event.runtimeType} - ${event.service?.name}',
      );

      if (event is BonsoirDiscoveryServiceResolvedEvent) {
        final resolved = event.service;
        debugPrint(
          '[Discovery] Resolved: ${resolved.name} at ${resolved.host}:${resolved.port}',
        );
        if (!_discoveredDevices.any((d) => d.name == resolved.name)) {
          _discoveredDevices.add(resolved);
          _devicesController.add(List.from(_discoveredDevices));
        }
      } else if (event is BonsoirDiscoveryServiceFoundEvent) {
        debugPrint('[Discovery] Found (unresolved): ${event.service.name}');
        // Service found but not resolved yet — Bonsoir should auto-resolve
      } else if (event is BonsoirDiscoveryServiceLostEvent) {
        debugPrint('[Discovery] Lost: ${event.service.name}');
        _discoveredDevices.removeWhere((d) => d.name == event.service.name);
        _devicesController.add(List.from(_discoveredDevices));
      }
    });

    await _discovery!.start();
    debugPrint('[Discovery] Discovery started for $_serviceType');
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
