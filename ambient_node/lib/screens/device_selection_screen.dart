import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/ble_service.dart';

class DeviceSelectionScreen extends StatefulWidget {
  final BleService bleService;
  final Function(bool) onConnectionChanged;

  const DeviceSelectionScreen({
    super.key,
    required this.bleService,
    required this.onConnectionChanged,
  });

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  List<BluetoothDevice> _devices = [];
  final Map<String, String> _connectionStates = {}; // deviceId -> 상태
  bool _isScanning = false;
  bool _hasConnectedDevice = false; // 연결된 기기가 있는지 추적
  Timer? _scanUpdateTimer; // 스캔 중 실시간 업데이트용 타이머

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
      // 연결 실패한 기기들 초기화
      _connectionStates.removeWhere(
          (key, value) => value == '연결 실패' || value == '페어링 대기 중...');
    });

    // 스캔 시작
    widget.bleService.startScan().listen((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
        });
      }
    });

    // 1초마다 스캔 결과 업데이트 (애니메이션 중)
    _scanUpdateTimer?.cancel();
    _scanUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isScanning) {
        timer.cancel();
        return;
      }

      // 스캔 결과 강제 업데이트 요청
      if (mounted) {
        setState(() {
          // UI 업데이트를 위한 빈 setState
        });
      }
    });
  }

  void _stopScanning() {
    widget.bleService.stopScan();
    _scanUpdateTimer?.cancel();
    setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();

    setState(() {
      _connectionStates[deviceId] = '연결 중...';
    });

    // 페어링 응답 콜백 설정
    widget.bleService.onPairingResponse = (response) {
      try {
        final Map<String, dynamic> data = json.decode(response);
        if (data['type'] == 'pairing_success') {
          if (mounted) {
            setState(() {
              _connectionStates[deviceId] = '연결 완료';
              _hasConnectedDevice = true;
              widget.onConnectionChanged(true);
            });
          }
        }
      } catch (e) {
        debugPrint('Pairing response parse error: $e');
      }
    };

    final success = await widget.bleService.connectToDevice(device);

    if (mounted) {
      if (success) {
        // BLE 연결은 성공했지만, 페어링 완료 응답을 기다림
        setState(() {
          _connectionStates[deviceId] = '페어링 대기 중...';
        });

        // 10초 후에도 페어링 응답이 없으면 실패 처리
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted && _connectionStates[deviceId] == '페어링 대기 중...') {
            setState(() {
              _connectionStates[deviceId] = '연결 실패';
              _checkConnectionStatus();
            });
          }
        });
      } else {
        setState(() {
          _connectionStates[deviceId] = '연결 실패';
          _checkConnectionStatus();
        });
      }
    }
  }

  void _checkConnectionStatus() {
    // 연결된 기기가 있는지 확인
    bool hasConnected =
        _connectionStates.values.any((state) => state == '연결 완료');
    if (hasConnected != _hasConnectedDevice) {
      _hasConnectedDevice = hasConnected;
      widget.onConnectionChanged(hasConnected);
    }
  }

  @override
  void dispose() {
    _stopScanning();
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
          // 스캔 상태 표시
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
                    elevation: _isScanning ? 0 : 2,
                  ),
                ),
              ],
            ),
          ),

          // 기기 목록
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bluetooth_disabled,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Ambient로 시작하는 기기를 찾을 수 없습니다',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final deviceId = device.remoteId.toString();
                      final connectionState = _connectionStates[deviceId] ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: connectionState == '연결 완료'
                                ? Colors.green
                                : connectionState == '연결 실패'
                                    ? Colors.red
                                    : connectionState == '페어링 대기 중...'
                                        ? Colors.orange
                                        : Colors.blue,
                          ),
                          title: Text(device.platformName.isNotEmpty
                              ? device.platformName
                              : '알 수 없는 기기'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ID: ${device.remoteId}'),
                              if (connectionState.isNotEmpty)
                                Text(
                                  connectionState,
                                  style: TextStyle(
                                    color: connectionState == '연결 완료'
                                        ? Colors.green
                                        : connectionState == '연결 실패'
                                            ? Colors.red
                                            : connectionState == '페어링 대기 중...'
                                                ? Colors.orange
                                                : Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          trailing: connectionState.isEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.link),
                                  onPressed: () => _connectToDevice(device),
                                )
                              : null,
                          onTap: connectionState.isEmpty
                              ? () => _connectToDevice(device)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),

      // 연결 상태 및 닫기 버튼
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 연결 상태 표시
            if (_hasConnectedDevice)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Text(
                      '기기가 연결되었습니다',
                      style: TextStyle(
                        color: Colors.green[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            // 닫기 버튼
            SizedBox(
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
          ],
        ),
      ),
    );
  }
}
