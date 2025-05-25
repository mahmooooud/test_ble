import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:vector_math/vector_math_64.dart'; // For compass calculations

class BLEManager {
  static final BLEManager _instance = BLEManager._internal();
  factory BLEManager() => _instance;
  BLEManager._internal();

  final FlutterBluePlus flutterBlue = FlutterBluePlus();
  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final StreamController<List<BluetoothDevice>> _deviceController =
      StreamController<List<BluetoothDevice>>.broadcast();
  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController<BluetoothConnectionState>.broadcast();
  final StreamController<GPSData> _gpsDataController =
      StreamController<GPSData>.broadcast();

  // Replace with your actual UUIDs
  static const String SERVICE_UUID = "d93d1001-9591-4dc0-946e-c01c4bddf68e";
  static const String WRITE_CHARACTERISTIC_UUID =
      "d93d1003-9591-4dc0-946e-c01c4bddf68e";
  static const String READ_CHARACTERISTIC_UUID =
      "d93d1002-9591-4dc0-946e-c01c4bddf68e";

  Stream<List<BluetoothDevice>> get deviceStream => _deviceController.stream;
  Stream<BluetoothConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  Stream<GPSData> get gpsDataStream => _gpsDataController.stream;

  Future<void> startScan() async {
    if (_scanSubscription != null) {
      await stopScan();
    }

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        final devices = results.map((result) => result.device).toList();
        log('Discovered devices: ${devices}');
        _deviceController.add(devices);
      }, onError: (error) {
        print('Error during scan: $error');
        // Handle error, e.g., show a message to the user
      });
    } catch (e) {
      print('Error starting scan: $e');
      // Handle error
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    _connectionStateController.add(BluetoothConnectionState.connecting);

    try {
      await device.connect();
      connectedDevice = device;
      _connectionStateController.add(BluetoothConnectionState.connected);

      device.connectionState.listen((state) {
        _connectionStateController.add(state);
        if (state == BluetoothConnectionState.disconnected) {
          connectedDevice = null;
          _gpsDataController
              .addError("Device disconnected"); // Notify GPS stream
        }
      });

      _listenForGPSData(); // Start listening for GPS data after connection

      return true;
    } catch (e) {
      print('Connection error: $e');
      _connectionStateController.add(BluetoothConnectionState.disconnected);
      return false;
    }
  }

  Future<void> disconnect() async {
    if (connectedDevice != null) {
      try {
        await disconnectLed();
        await connectedDevice!.disconnect();
        connectedDevice = null;
        _connectionStateController.add(BluetoothConnectionState.disconnected);
        _gpsDataController.addError("Device disconnected"); // Notify GPS stream
      } catch (e) {
        print('Disconnection error: $e');
        _connectionStateController.add(BluetoothConnectionState.disconnected);
        _gpsDataController.addError("Device disconnected"); // Notify GPS stream
      }
    }
  }

  Future<void> sendDirectionAndDistance(int direction, int distance) async {
    if (connectedDevice == null) return;

    final data = Uint8List(6);
    data[0] = 0x5A;
    data[1] = 0x34;
    data[2] = (distance >> 8) & 0xFF;
    data[3] = distance & 0xFF;
    data[4] = (direction >> 8) & 0xFF;
    data[5] = direction & 0xFF;
    log('data: $data');
    try {
      final services = await connectedDevice!.discoverServices();
      final service =
          services.firstWhere((s) => s.uuid.toString() == SERVICE_UUID);
      final characteristic = service.characteristics
          .firstWhere((c) => c.uuid.toString() == WRITE_CHARACTERISTIC_UUID);
      await characteristic.write(data);
    } catch (e) {
      print('Error sending data: $e');
      // Handle error
    }
  }

  Future<void> disconnectLed() async {
    if (connectedDevice == null) return;

    final data = Uint8List(6);
    data[0] = 0x5a;
    data[1] = 0x34;
    data[2] = 0x00;
    data[3] = 0x70;
    data[4] = 0x00;
    data[5] = 0x00;
    log('data: $data');
    try {
      final services = await connectedDevice!.discoverServices();
      final service =
          services.firstWhere((s) => s.uuid.toString() == SERVICE_UUID);
      final characteristic = service.characteristics
          .firstWhere((c) => c.uuid.toString() == WRITE_CHARACTERISTIC_UUID);
      await characteristic.write(data);
    } catch (e) {
      print('Error sending data: $e');
      // Handle error
    }
  }

  Future<void> _listenForGPSData() async {
    if (connectedDevice == null) return;

    try {
      final services = await connectedDevice!.discoverServices();
      final service =
          services.firstWhere((s) => s.uuid.toString() == SERVICE_UUID);
      final characteristic = service.characteristics
          .firstWhere((c) => c.uuid.toString() == READ_CHARACTERISTIC_UUID);

      await characteristic.setNotifyValue(true);
      characteristic.value.listen((data) {
        try {
          final gpsData = _parseGPSData(data);
          _gpsDataController.add(gpsData);
        } catch (e) {
          _gpsDataController.addError(e); // Handle parsing errors
        }
      }, onError: (error) {
        _gpsDataController.addError(error); // Handle stream errors
      });
    } catch (e) {
      print('Error listening for GPS data: $e');

      _gpsDataController
          .addError(e); // Handle service/characteristic discovery errors
    }
  }

  GPSData _parseGPSData(List<int> data) {
    if (data.length < 12) throw Exception('Invalid GPS data format');

    if (data[0] != 0x5A || data[1] != 0x32) {
      throw Exception('Invalid header');
    }

    final isEast = String.fromCharCode(data[2]) == 'E';
    final longitude = _bytesToInt(data.sublist(3, 7)) / 10000000.0;

    final isNorth = String.fromCharCode(data[7]) == 'N';
    final latitude = _bytesToInt(data.sublist(8, 12)) / 10000000.0;

    return GPSData(
      longitude: isEast ? longitude : -longitude,
      latitude: isNorth ? latitude : -latitude,
    );
  }

  int _bytesToInt(List<int> bytes) {
    int result = 0;
    for (var byte in bytes) {
      result = (result << 8) + byte;
    }
    return result;
  }
}

class GPSData {
  final double longitude;
  final double latitude;

  GPSData({required this.longitude, required this.latitude});

  @override
  String toString() {
    return 'GPSData{longitude: $longitude, latitude: $latitude}';
  }
}
