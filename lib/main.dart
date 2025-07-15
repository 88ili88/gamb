import 'dart:async';
import 'dart:io';
import 'dart:convert';
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
      title: 'TimeSync BLE',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomePage(),
    );
  }
}

class Sample {
  final int ts;
  final double ec, temp, sal, batt;
  Sample(this.ts, this.ec, this.temp, this.sal, this.batt);
  List<dynamic> toCsvRow() => [ts, ec, temp, sal, batt];
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ble = FlutterReactiveBle();
  DiscoveredDevice? _device;
  late QualifiedCharacteristic _timeChar, _dataChar;
  static final _svcUuid      = Uuid.parse('00001A00-0000-1000-8000-00805F9B34FB');
  static final _timeCharUuid = Uuid.parse('00001A04-0000-1000-8000-00805F9B34FB');
  static final _dataCharUuid = Uuid.parse('00001A02-0000-1000-8000-00805F9B34FB');

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
        ['timestamp','ec','temp','salinity','battery']
      ]);
      await _csvFile.writeAsString('$header\n');
    }
  }

  void _startScan() {
    _ble.scanForDevices(withServices: [_svcUuid]).listen((dev) {
      if (_device == null && dev.name.isNotEmpty) {
        setState(() => _status = 'Found ${dev.name}');
        _device = dev;
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
    _ble.subscribeToCharacteristic(_dataChar).listen((data) async {
      final bs = ByteData.sublistView(Uint8List.fromList(data));
      final ts   = bs.getUint32(0, Endian.little);
      final ec   = bs.getFloat32(4, Endian.little);
      final temp = bs.getFloat32(8, Endian.little);
      final sal  = bs.getFloat32(12, Endian.little);
      final batt = bs.getFloat32(16, Endian.little);
      final samp = Sample(ts, ec, temp, sal, batt);
      setState(() => _samples.insert(0, samp));
      final csv = const ListToCsvConverter().convert([samp.toCsvRow()]);
      await _csvFile.writeAsString('$csv\n', mode: FileMode.append);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE TimeSync & Logger')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('Status: $_status'),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: _samples.length,
              itemBuilder: (_, i) {
                final s = _samples[i];
                return ListTile(
                  title: Text(
                    '${DateTime.fromMillisecondsSinceEpoch(s.ts*1000).toLocal()}'),
                  subtitle: Text(
                    'EC=${s.ec.toStringAsFixed(1)}  T=${s.temp.toStringAsFixed(1)}  S=${s.sal.toStringAsFixed(1)}  B=${s.batt.toStringAsFixed(2)}'),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
