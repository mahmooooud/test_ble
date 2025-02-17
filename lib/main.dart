import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:test_ble/ble-manager.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final BLEManager _bleManager = BLEManager();
  GPSData? _lastGPSData;
  String? _connectedDeviceAddress;
  StreamSubscription<GPSData>? _gpsSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Request necessary permissions
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.location.request();
  }

  void _startScan() async {
    await _bleManager.startScan();
  }

  void _connectToDevice(BluetoothDevice device) async {
    final success = await _bleManager.connectToDevice(device);
    if (success) {
      setState(() {
        _connectedDeviceAddress = device.id.id;
      });
      _startListeningToGPS();
    }
  }

  void _startListeningToGPS() {
    _gpsSubscription = _bleManager.listenForGPSData().listen((gpsData) {
      setState(() {
        _lastGPSData = gpsData;
      });
      _calculateAndSendDirectionDistance();
    });
  }

  Future<void> _calculateAndSendDirectionDistance() async {
    if (_lastGPSData == null) return;

    // Get current position
    final currentPosition = await Geolocator.getCurrentPosition();

    // Calculate bearing
    final bearing = Geolocator.bearingBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      _lastGPSData!.latitude,
      _lastGPSData!.longitude,
    );

    // Calculate distance in meters
    final distance = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      _lastGPSData!.latitude,
      _lastGPSData!.longitude,
    );

    // Send to BLE device
    await _bleManager.sendDirectionAndDistance(
      bearing.round(),
      distance.round(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Altariq Delivery'),
      ),
      body: Column(
        children: [
          // Connected device info
          if (_connectedDeviceAddress != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text('Connected to: $_connectedDeviceAddress'),
            ),

          // Scan button
          ElevatedButton(
            onPressed: _startScan,
            child: const Text('Scan for Devices'),
          ),

          // Device list
          Expanded(
            child: StreamBuilder<List<BluetoothDevice>>(
              stream: _bleManager.deviceStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final device = snapshot.data![index];
                    return ListTile(
                      title: Text(device.name),
                      subtitle: Text(device.id.id),
                      onTap: () => _connectToDevice(device),
                    );
                  },
                );
              },
            ),
          ),

          // GPS Data display
          if (_lastGPSData != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Text('Latitude: ${_lastGPSData!.latitude}'),
                  Text('Longitude: ${_lastGPSData!.longitude}'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _bleManager.disconnect();
    super.dispose();
  }
}
