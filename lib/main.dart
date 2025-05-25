import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:test_ble/ble-manager.dart';
import 'package:vector_math/vector_math_64.dart'; // For compass calculations
import 'package:geolocator/geolocator.dart'; // For phone's GPS

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        useMaterial3: true,
      ),
      home: (MyBleWidget()),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}

// ... (BLEManager and GPSData classes as before)

class MyBleWidget extends StatefulWidget {
  @override
  _MyBleWidgetState createState() => _MyBleWidgetState();
}

class _MyBleWidgetState extends State<MyBleWidget> {
  final BLEManager bleManager = BLEManager();
  List<BluetoothDevice> availableDevices = [];
  BluetoothDevice? connectedDevice;
  GPSData? latestGPSData;
  Position? phoneLocation;
  double compassHeading = 0.0; // Current compass heading
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  @override
  void initState() {
    super.initState();
    _startScan();
    _initLocation();
    _initCompass();

    bleManager.gpsDataStream.listen((gpsData) {
      setState(() {
        latestGPSData = gpsData;
      });
      print("Received GPS Data: $gpsData");
    }, onError: (error) {
      print("GPS Data Error: $error");
      // Handle the error (e.g., show a message to the user)
    });

    bleManager.connectionStateStream.listen((state) {
      setState(() {
        if (state == BluetoothConnectionState.connected) {
          connectedDevice = bleManager.connectedDevice;
        } else if (state == BluetoothConnectionState.disconnected) {
          connectedDevice = null;
          latestGPSData = null; // Clear GPS data on disconnect
        }
      });
    });
  }

  Future<void> _startScan() async {
    await bleManager.startScan();
    bleManager.deviceStream.listen((devices) {
      setState(() {
        availableDevices = devices;
      });
    });
  }

  Future<void> _initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    _positionSubscription = Geolocator.getPositionStream().listen((position) {
      setState(() {
        phoneLocation = position;
      });
    });
  }

  void _initCompass() {
    // Use a plugin like compass_plus or sensors_plus if needed.
    // This example uses a placeholder.  You'll need a real compass implementation.

    // Example using sensors_plus (you'll need to add the dependency):
    // final sensor = sensors_plus.SensorManager().compass;
    // sensor.listen((event) {
    //   setState(() {
    //     compassHeading = event.headingRadians; // Or whatever unit your compass gives
    //   });
    // });

    // Placeholder:  Replace with actual compass readings.
    // Timer.periodic(const Duration(milliseconds: 500), (timer) {
    //   setState(() {
    //     compassHeading =
    //         (compassHeading + 0.1) % (2 * pi); // Simulate compass movement
    //   });
    // });
  }

  @override
  void dispose() {
    // _scanSubscription?.cancel();
    _positionSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    bleManager.disconnect(); // Disconnect on widget dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("BLE Example")),
      body: Center(
        child: SingleChildScrollView(
          // Added for scrollability
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ElevatedButton(
                onPressed: () {
                  if (bleManager.connectedDevice != null) {
                    // Check if connected
                    int direction =
                        90; // Example direction (0-359 degrees, or whatever your protocol defines)
                    int distance =
                        80; // Example distance (units depend on your protocol)
                    bleManager.sendDirectionAndDistance(direction, distance);
                  } else {
                    // Handle the case where no device is connected
                    print("No device connected. Cannot send data.");
                  }
                },
                child: const Text("Send Direction and Distance"),
              ),
              const Text("Available Devices:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              availableDevices.isEmpty
                  ? const Text("No devices found.")
                  : DropdownButton<BluetoothDevice>(
                      value: connectedDevice,
                      items: availableDevices
                          .map((device) => DropdownMenuItem<BluetoothDevice>(
                                value: device,
                                child:
                                    Text(device.name ?? device.id.toString()),
                              ))
                          .toList(),
                      onChanged: (device) {
                        if (device != null) {
                          bleManager.connectToDevice(device);
                        }
                      },
                    ),
              const SizedBox(height: 20),
              Text(
                  "Connection State: ${connectedDevice != null ? "Connected ${bleManager.connectedDevice!.remoteId.id}" : "Disconnected"}"),
              const SizedBox(height: 20),
              if (latestGPSData != null) ...[
                const Text("Received GPS Data (BLE):",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text("Longitude: ${latestGPSData!.longitude}"),
                Text("Latitude: ${latestGPSData!.latitude}"),
              ],
              if (phoneLocation != null) ...[
                const Text("Phone GPS Location:",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text("Longitude: ${phoneLocation!.longitude}"),
                Text("Latitude: ${phoneLocation!.latitude}"),
              ],
              const SizedBox(height: 20),
              // Compass Widget (replace with your actual compass widget)
              Transform.rotate(
                angle: compassHeading,
                child: const Icon(Icons.arrow_upward, size: 50),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: connectedDevice != null
                    ? () {
                        // Example: Send some data
                        bleManager.sendDirectionAndDistance(
                            50, 40); // Example values
                      }
                    : null,
                child: const Text("Send Data"),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: connectedDevice != null
                    ? () {
                        // Example: Send some data
                        bleManager.disconnect(); // Example values
                      }
                    : null,
                child: const Text("Disconnect"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
