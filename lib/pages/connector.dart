import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  late StreamSubscription<BluetoothAdapterState> _adapterStateStateSubscription;

  List<ScanResult> _scanResults = [];
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  bool _isScanning = false;

  BluetoothDevice? _connectedDevice;
  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  List<BluetoothService> _services = [];
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _readCharacteristic;

  String _connectionStatus = "Disconnected";
  String _receivedData = "";

  @override
  void initState() {
    super.initState();
    _adapterStateStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      setState(() {
        _adapterState = state;
        if (state == BluetoothAdapterState.off) {
          _connectionStatus = "Bluetooth is OFF";
          _disconnect();
        }
      });
    });
    _requestPermissions();
  }

  @override
  void dispose() {
    _adapterStateStateSubscription.cancel();
    _scanResultsSubscription.cancel();
    _connectionStateSubscription.cancel();
    _disconnect();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  void _startScan() async {
     if (_adapterState != BluetoothAdapterState.on) {
      return;
    }
    setState(() {
      _scanResults = [];
      _connectionStatus = "Searching for devices...";
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
       print("Scan results: ${results.length}");
       for (var result in results) {
         print("Found device: ${result.device.remoteId} with name: ${result.device.platformName}");
       }
       setState(() {
        _scanResults = results;
      });
    });

     _isScanning = true;
    setState((){});


    FlutterBluePlus.isScanning.listen((isScanning) {
        _isScanning = isScanning;
        if(!_isScanning){
           _connectionStatus = _scanResults.isEmpty
                ? 'No devices found'
                : 'Found ${_scanResults.length} device(s)';
        }
        setState((){});
    });
  }


  Future<void> _connectToDevice(BluetoothDevice device) async {
    await device.connect(autoConnect: false, license: License.free);

    _connectionStateSubscription = device.connectionState.listen((state) async {
      if (state == BluetoothConnectionState.connected) {
        setState(() {
          _connectedDevice = device;
          _connectionStatus = 'Connected to ${device.platformName}';
        });

        _services = await device.discoverServices();
        for (var service in _services) {
          for (var characteristic in service.characteristics) {
            if (characteristic.properties.write) {
              _writeCharacteristic = characteristic;
            }
            if (characteristic.properties.notify || characteristic.properties.read) {
              _readCharacteristic = characteristic;
            }
          }
        }
        if(_readCharacteristic != null){
             await _readCharacteristic!.setNotifyValue(true);
             _readCharacteristic!.lastValueStream.listen((value) {
                setState(() {
                  _receivedData += utf8.decode(value);
                });
             });
        }
        setState((){});

      } else if (state == BluetoothConnectionState.disconnected) {
        _disconnect();
      }
    });
  }

  void _disconnect() {
    _connectedDevice?.disconnect();
    setState(() {
      _connectedDevice = null;
      _connectionStatus = 'Disconnected';
      _services = [];
      _writeCharacteristic = null;
      _readCharacteristic = null;
      _receivedData = "";
    });
  }

  Future<void> _sendData(String data) async {
    if (_writeCharacteristic != null) {
      await _writeCharacteristic!.write(utf8.encode(data));
      print('Data sent: $data');
    }
  }

 @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Controller'),
        backgroundColor: Colors.blue[700],
      ),
      body: Container(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Bluetooth Status Card
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _adapterState == BluetoothAdapterState.on
                              ? Icons.bluetooth_connected
                              : Icons.bluetooth_disabled,
                          color: _adapterState == BluetoothAdapterState.on
                              ? Colors.green
                              : Colors.red,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Bluetooth: ${_adapterState == BluetoothAdapterState.on ? "ON" : "OFF"}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(_connectionStatus, style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed:
                      _adapterState == BluetoothAdapterState.on && !_isScanning
                          ? _startScan
                          : null,
                  child: Text('Scan Devices'),
                ),
                ElevatedButton(
                  onPressed: _connectedDevice != null ? _disconnect : null,
                  child: Text('Disconnect'),
                ),
              ],
            ),

            SizedBox(height: 16),

            // Device Lists
            Expanded(
              child: ListView.builder(
                itemCount: _scanResults.length,
                itemBuilder: (context, index) {
                  final result = _scanResults[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.bluetooth),
                      title: Text(result.device.platformName.isNotEmpty ? result.device.platformName : 'Unknown Device'),
                      subtitle: Text(result.device.remoteId.toString()),
                      trailing: Icon(Icons.arrow_forward_ios),
                      onTap: _connectedDevice == null ? () => _connectToDevice(result.device) : null,
                    ),
                  );
                },
              ),
            ),


            // Control buttons and data display when connected
            if (_connectedDevice != null) ...[
              Container(
                height: 100,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      _receivedData.isEmpty
                          ? 'No data received yet...'
                          : _receivedData,
                      style: TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => _sendData('1'),
                    child: Text('Send "1"'),
                  ),
                  ElevatedButton(
                    onPressed: () => _sendData('0'),
                    child: Text('Send "0"'),
                  ),
                  ElevatedButton(
                    onPressed: () => _sendData('TEST'),
                    child: Text('Send "TEST"'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
