import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BLEManager {
  static final BLEManager _instance = BLEManager._internal();
  factory BLEManager() => _instance;
  BLEManager._internal();

  final FlutterBluePlus flutterBlue = FlutterBluePlus();
  BluetoothDevice? connectedDevice;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final StreamController<List<BluetoothDevice>> _deviceController =
      StreamController<List<BluetoothDevice>>.broadcast();

  Stream<List<BluetoothDevice>> get deviceStream => _deviceController.stream;

  // Start scanning for BLE devices
  Future<void> startScan() async {
    if (_scanSubscription != null) {
      await stopScan();
    }

    // Start scanning
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      // Filter for devices with names starting with ALTARAQ_
      final devices = results.map((result) => result.device).toList();
      _deviceController.add(devices);
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      connectedDevice = device;
      return true;
    } catch (e) {
      print('Connection error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
        connectedDevice = null;
      } catch (e) {
        print('Disconnection error: $e');
      }
    }
  }

  // Send direction and distance to device
  Future<void> sendDirectionAndDistance(int direction, int distance) async {
    if (connectedDevice == null) return;

    final data = Uint8List(6);
    // Header
    data[0] = 0x5A;
    data[1] = 0x32;
    // Distance (2 bytes)
    data[2] = (distance >> 8) & 0xFF;
    data[3] = distance & 0xFF;
    // Direction (2 bytes)
    data[4] = (direction >> 8) & 0xFF;
    data[5] = direction & 0xFF;

    // Get the characteristic and send data
    List<BluetoothService> services = await connectedDevice!.discoverServices();
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.write) {
          await characteristic.write(data);
          break;
        }
      }
    }
  }

  // Listen for GPS data from device
  Stream<GPSData> listenForGPSData() async* {
    if (connectedDevice == null) return;

    List<BluetoothService> services = await connectedDevice!.discoverServices();
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.notify ||
            characteristic.properties.indicate) {
          await characteristic.setNotifyValue(true);
          yield* characteristic.value.map((data) => _parseGPSData(data));
        }
      }
    }
  }

  GPSData _parseGPSData(List<int> data) {
    if (data.length < 12) throw Exception('Invalid GPS data format');

    // Verify header
    if (data[0] != 0x5A || data[1] != 0x32) {
      throw Exception('Invalid header');
    }

    // Parse E/W and longitude
    final isEast = String.fromCharCode(data[2]) == 'E';
    final longitude = _bytesToInt(data.sublist(3, 7)) / 10000000.0;

    // Parse N/S and latitude
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
}
