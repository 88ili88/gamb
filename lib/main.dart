import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';

void main() {
  runApp(const TimeSyncApp());
}

class TimeSyncApp extends StatelessWidget {
  const TimeSyncApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Sensor Logger',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const HomePage(),
    );
  }
}

class Sample {
  final int ts;
  final double lat;
  final double lon;
  final double ec;
  final double temp;
  final double sal;
  final double batt;

  Sample(this.ts, this.lat, this.lon, this.ec, this.temp, this.sal, this.batt);

  List<dynamic> toCsvRow() => [ts, lat, lon, ec, temp, sal, batt];
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  DiscoveredDevice? _device;
  late QualifiedCharacteristic _timeChar;
  late QualifiedCharacteristic _dataChar;

  static final Uuid _svcUuid      = Uuid.parse('00001A00-0000-1000-8000-00805F9B34FB');
  static final Uuid _timeCharUuid = Uuid.parse('00001A04-0000-1000-8000-00805F9B34FB');
  static final Uuid _dataCharUuid = Uuid.parse('00001A02-0000-1000-8000-00805F9B34FB');

  String _status = 'Scanning…';
  List<Sample> _samples = [];
  late File _csvFile;

  @override
  void initState() {
    super.initState();
    _prepareCsv().then((_) => _startScan());
  }

  Future<void> _prepareCsv() async {
    final dir = await getApplicationDocumentsDirectory();
    _csvFile = File('${dir.path}/samples.csv');
    if (!await _csvFile.exists()) {
      final header = const ListToCsvConverter().convert([
        ['timestamp','lat','lon','ec','temp','salinity','battery']
      ]);
      await _csvFile.writeAsString('$header\n');
    }
  }

  void _startScan() {
    _ble.scanForDevices(withServices: [_svcUuid]).listen((device) {
      if (_device == null && device.name.isNotEmpty) {
        setState(() => _status = 'Found ${device.name}');
        _device = device;
        _connect();
      }
    }, onError: (e) {
      setState(() => _status = 'Scan error: $e');
    });
  }

  Future<void> _connect() async {
    setState(() => _status = 'Connecting…');
    await _ble.connectToDevice(id: _device!.id).first;
    setState(() => _status = 'Connected');
    _timeChar = QualifiedCharacteristic(
      serviceId: _svcUuid,
      characteristicId: _timeCharUuid,
      deviceId: _device!.id,
    );
    _dataChar = QualifiedCharacteristic(
      serviceId: _svcUuid,
      characteristicId: _dataCharUuid,
      deviceId: _device!.id,
    );
    _syncTime();
    _subscribeData();
  }

  Future<void> _syncTime() async {
    final epoch = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final bytes = List<int>.generate(4, (i) => (epoch >> (8 * i)) & 0xFF);
    await _ble.writeCharacteristicWithResponse(_timeChar, value: bytes);
    setState(() => _status = 'Time synced: $epoch');
  }

  void _subscribeData() {
    _ble.subscribeToCharacteristic(_dataChar).listen(_handleIncomingData);
  }

  Future<void> _handleIncomingData(List<int> data) async {
    // Blob: ts(4) lat(4) lon(4) ec(4) temp(4) sal(4) batt(4) = 28 bytes
    final bs = ByteData.sublistView(Uint8List.fromList(data));
    final ts   = bs.getUint32(0, Endian.little);
    final lat  = bs.getFloat32(4, Endian.little);
    final lon  = bs.getFloat32(8, Endian.little);
    final ec   = bs.getFloat32(12, Endian.little);
    final temp = bs.getFloat32(16, Endian.little);
    final sal  = bs.getFloat32(20, Endian.little);
    final batt = bs.getFloat32(24, Endian.little);
    final sample = Sample(ts, lat, lon, ec, temp, sal, batt);
    setState(() => _samples.insert(0, sample));
    final csvLine = const ListToCsvConverter().convert([sample.toCsvRow()]);
    await _csvFile.writeAsString('$csvLine\n', mode: FileMode.append);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Sensor Logger')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: $_status'),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _samples.length,
                itemBuilder: (context, index) {
                  final s = _samples[index];
                  return ListTile(
                    title: Text(
                      DateTime.fromMillisecondsSinceEpoch(s.ts * 1000)
                          .toLocal()
                          .toString(),
                    ),
                    subtitle: Text(
                      'Lat=${s.lat.toStringAsFixed(5)}, '
                      'Lon=${s.lon.toStringAsFixed(5)}\n'
                      'EC=${s.ec.toStringAsFixed(1)} mS/cm, '
                      'T=${s.temp.toStringAsFixed(1)}°C, '
                      'S=${s.sal.toStringAsFixed(1)} g/L, '
                      'B=${s.batt.toStringAsFixed(2)} V',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
