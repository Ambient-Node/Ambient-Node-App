import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ambient_node/services/ble_service.dart'; // BleService, BleConnectionState 포함

class DeviceSelectionScreen extends StatefulWidget {
  final BleService bleService;
  final Function(bool) onConnectionChanged;
  final Function(String)? onDeviceNameChanged;

  const DeviceSelectionScreen({
    super.key,
    required this.bleService,
    required this.onConnectionChanged,
    this.onDeviceNameChanged,
  });

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  List<BluetoothDevice> _devices = [];
  // 디바이스 ID별 연결 상태 메시지 저장
  final Map<String, String> _connectionStates = {};

  bool _isScanning = false;
  bool _hasConnectedDevice = false;

  // 스트림 구독 관리
  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _startScanning();
  }

  @override
  void dispose() {
    _stopScanning();
    _connectionStateSubscription?.cancel();
    super.dispose();
  }

  void _setupListeners() {
    // 1. 연결 상태 스트림 구독
    _connectionStateSubscription = widget.bleService.connectionStateStream.listen((state) {
      print('[DeviceSelection] 연결 상태 변경: $state');

      if (!mounted) return;

      setState(() {
        _hasConnectedDevice = (state == BleConnectionState.connected);

        // 상위 위젯에 알림
        widget.onConnectionChanged(_hasConnectedDevice);

        if (state == BleConnectionState.connected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('디바이스가 연결되었습니다'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pop(); // 연결 성공 시 화면 닫기 (선택 사항)
        } else if (state == BleConnectionState.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('연결 중 오류가 발생했습니다'), backgroundColor: Colors.red),
          );
        }
      });
    });
  }

  void _startScanning() {
    if (_isScanning) return;

    setState(() => _isScanning = true);

    // 2. 스캔 스트림 구독
    _scanSubscription = widget.bleService.startScan().listen(
          (scanResults) {
        if (mounted) {
          setState(() {
            // ScanResult에서 BluetoothDevice 추출 및 중복 제거
            _devices = scanResults.map((r) => r.device).toList();
            print('[DeviceSelection] 발견된 기기: ${_devices.length}개');
          });
        }
      },
      onError: (e) {
        print('[DeviceSelection] 스캔 오류: $e');
        if (mounted) setState(() => _isScanning = false);
      },
      onDone: () {
        if (mounted) setState(() => _isScanning = false);
      },
    );
  }

  void _stopScanning() {
    widget.bleService.stopScan();
    _scanSubscription?.cancel();
    if (mounted) setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();

    // 스캔 중지 (연결 시도 전)
    _stopScanning();

    setState(() {
      _connectionStates[deviceId] = '연결 중...';
    });

    try {
      // 새로운 BleService.connect는 Future<void>이며 실패 시 throw함
      await widget.bleService.connect(device);

      // 성공 처리는 _setupListeners의 스트림에서 처리됨
      setState(() {
        _connectionStates[deviceId] = '연결 완료';
        if (widget.onDeviceNameChanged != null) {
          widget.onDeviceNameChanged!(device.platformName);
        }
      });

    } catch (e) {
      print('[DeviceSelection] 연결 예외: $e');
      if (mounted) {
        setState(() {
          _connectionStates[deviceId] = '연결 실패';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('연결 실패: $e'), backgroundColor: Colors.red),
        );
        // 3초 후 상태 메시지 초기화
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) setState(() => _connectionStates.remove(deviceId));
        });
      }
    }
  }

  Future<void> _disconnectFromDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();
    setState(() => _connectionStates[deviceId] = '해제 중...');

    try {
      await widget.bleService.disconnect();
      if (mounted) {
        setState(() {
          _connectionStates.remove(deviceId);
          _hasConnectedDevice = false;
        });
      }
    } catch (e) {
      print('[DeviceSelection] 해제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('블루투스 기기 선택'),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 상단 상태 바
          Container(
            padding: const EdgeInsets.all(16),
            color: _isScanning ? Colors.blue[50] : Colors.grey[100],
            child: Row(
              children: [
                _isScanning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.bluetooth, color: Colors.grey[600]),
                const SizedBox(width: 12),
                Text(_isScanning ? '기기 스캔 중...' : '스캔 완료'),
                const Spacer(),
                ElevatedButton(
                  onPressed: _isScanning ? _stopScanning : _startScanning,
                  child: Text(_isScanning ? '중지' : '다시 스캔'),
                ),
              ],
            ),
          ),
          // 기기 리스트
          Expanded(
            child: _devices.isEmpty
                ? Center(
              child: Text(
                _isScanning ? '기기를 찾는 중...' : '발견된 기기가 없습니다.',
                style: TextStyle(color: Colors.grey[600]),
              ),
            )
                : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                final deviceId = device.remoteId.toString();
                final status = _connectionStates[deviceId] ?? '';
                final isConnected = widget.bleService.currentState == BleConnectionState.connected &&
                    status == '연결 완료';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: Icon(
                      Icons.bluetooth,
                      color: isConnected ? Colors.blue : Colors.grey,
                    ),
                    title: Text(device.platformName.isNotEmpty ? device.platformName : '알 수 없는 기기'),
                    subtitle: Text(deviceId),
                    trailing: status.isNotEmpty
                        ? Text(status, style: TextStyle(
                        color: status.contains('실패') ? Colors.red : Colors.blue,
                        fontWeight: FontWeight.bold))
                        : null,
                    onTap: isConnected
                        ? () => _disconnectFromDevice(device)
                        : () => _connectToDevice(device),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          child: const Text('닫기'),
        ),
      ),
    );
  }
}