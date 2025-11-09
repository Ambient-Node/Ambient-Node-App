import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ambient_node/services/ble_service.dart';

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
  final Map<String, String> _connectionStates = {};
  bool _isScanning = false;
  bool _hasConnectedDevice = false;
  Timer? _scanUpdateTimer;

  @override
  void initState() {
    super.initState();
    _setupCallbacks();
    _startScanning();
  }

  void _setupCallbacks() {
    // 연결 상태 변경 콜백
    widget.bleService.onConnectionStateChanged = (isConnected) {
      if (mounted) {
        setState(() {
          _hasConnectedDevice = isConnected;
          widget.onConnectionChanged(isConnected);
        });
      }
    };

    // 기기 이름 변경 콜백
    try {
      widget.bleService.onDeviceNameChanged = (name) {
        if (widget.onDeviceNameChanged != null) {
          widget.onDeviceNameChanged!(name);
        }
      };
    } catch (_) {}
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
      _connectionStates.clear();
    });

    widget.bleService.startScan().listen((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
        });
      }
    });

    _scanUpdateTimer?.cancel();
    _scanUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isScanning) {
        timer.cancel();
        return;
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _stopScanning() {
    widget.bleService.stopScan();
    _scanUpdateTimer?.cancel();
    if (!mounted) return;
    setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();

    // 이미 연결된 기기인 경우 해제
    if (_connectionStates[deviceId] == '연결 완료' || _hasConnectedDevice) {
      await _disconnectFromDevice(device);
      return;
    }

    setState(() {
      _connectionStates[deviceId] = '연결 중...';
    });

    final success = await widget.bleService.connectToDevice(device);

    if (mounted) {
      setState(() {
        if (success) {
          _connectionStates[deviceId] = '연결 완료';
          _hasConnectedDevice = true;
          widget.onConnectionChanged(true);
        } else {
          _connectionStates[deviceId] = '연결 실패';
          _hasConnectedDevice = false;
        }
      });
    }
  }

  Future<void> _disconnectFromDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();

    setState(() {
      _connectionStates[deviceId] = '해제 중...';
    });

    try {
      await widget.bleService.disconnect();
      if (mounted) {
        setState(() {
          _connectionStates[deviceId] = '';
          _hasConnectedDevice = false;
          widget.onConnectionChanged(false);
        });
      }
    } catch (e) {
      print('[DeviceSelection] 연결 해제 오류: $e');
      if (mounted) {
        setState(() {
          _connectionStates[deviceId] = '해제 실패';
        });
      }
    }
  }

  @override
  void dispose() {
    try {
      widget.bleService.stopScan();
    } catch (_) {}
    _scanUpdateTimer?.cancel();
    super.dispose();
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isScanning ? Colors.blue[50] : Colors.grey[100],
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: Row(
              children: [
                if (_isScanning) ...[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('기기를 스캔 중...',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${_devices.length}개 기기 발견됨',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ] else ...[
                  Icon(Icons.bluetooth_searching, color: Colors.grey[600]),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('스캔 완료',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${_devices.length}개 기기 발견됨',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ],
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _isScanning ? _stopScanning : _startScanning,
                  icon: _isScanning
                      ? const Icon(Icons.stop, size: 16)
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(_isScanning ? '중지' : '다시 스캔'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        _isScanning ? Colors.red[400] : Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bluetooth_disabled,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('Ambient로 시작하는 기기를 찾을 수 없습니다',
                            style: TextStyle(color: Colors.grey[600])),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final deviceId = device.remoteId.toString();
                      final connectionState = _connectionStates[deviceId] ?? '';
                      final isConnected = connectionState == '연결 완료';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            isConnected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth,
                            color: isConnected ? Colors.red : Colors.grey,
                          ),
                          title: Text(device.platformName.isNotEmpty
                              ? device.platformName
                              : '알 수 없는 기기'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${device.remoteId}'),
                              if (isConnected)
                                const Text(
                                  '연결 해제',
                                  style: TextStyle(
                                    color: Colors.red,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          trailing: connectionState == '연결 중...' ||
                                  connectionState == '해제 중...'
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                          onTap: connectionState == '연결 완료' ||
                                  connectionState.isEmpty
                              ? () => _connectToDevice(device)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[600],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('닫기'),
          ),
        ),
      ),
    );
  }
}
