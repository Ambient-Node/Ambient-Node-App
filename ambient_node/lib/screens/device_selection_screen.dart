import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DeviceSelectionScreen extends StatefulWidget {
  final dynamic bleService; // BleService 또는 TestBleService 모두 받음
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
  final Map<String, String> _connectionStates = {}; // deviceId -> 상태
  final Map<String, String> _pairingPins = {}; // deviceId -> PIN
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
    // 페어링 응답 콜백 설정 (TestBleService의 Notification 수신)
    widget.bleService.onPairingResponse = (response) {
      try {
        final Map<String, dynamic> data = json.decode(response);

        // 라즈베리파이에서 PIN 전송
        if (data['type'] == 'PAIRING_PIN') {
          final pin = data['pin'] as String;
          debugPrint('Received PIN from RPi: $pin');

          // 현재 연결 시도 중인 기기에 PIN 표시
          final connectingDevice = _connectionStates.entries
              .firstWhere(
                (entry) =>
                    entry.value.contains('연결 중') ||
                    entry.value.contains('본딩 중'),
                orElse: () => const MapEntry('', ''),
              )
              .key;

          if (connectingDevice.isNotEmpty && mounted) {
            setState(() {
              _pairingPins[connectingDevice] = pin;
              _connectionStates[connectingDevice] = '본딩 중 - PIN: $pin';
            });

            // PIN 다이얼로그 표시
            _showPinDialog(pin);
          }
        }

        // 연결 성공 응답
        else if (data['type'] == 'pairing_success' || data['type'] == 'ACK') {
          debugPrint('Device connected successfully');
          if (mounted) {
            final connectedDevice = _connectionStates.entries
                .firstWhere(
                  (entry) =>
                      entry.value.contains('본딩 중') ||
                      entry.value.contains('연결 중'),
                  orElse: () => const MapEntry('', ''),
                )
                .key;

            if (connectedDevice.isNotEmpty) {
              setState(() {
                _connectionStates[connectedDevice] = '연결 완료';
                _hasConnectedDevice = true;
                widget.onConnectionChanged(true);
              });
            }
          }
        }
      } catch (e) {
        debugPrint('Pairing response parse error: $e');
      }
    };

    // 기기 이름 변경 콜백 연결 (가능한 경우)
    try {
      widget.bleService.onDeviceNameChanged = (name) {
        if (widget.onDeviceNameChanged != null) {
          widget.onDeviceNameChanged!(name);
        }
      };
    } catch (_) {}
  }

  void _showPinDialog(String pin) {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, color: Colors.blue),
            SizedBox(width: 8),
            Text('블루투스 본딩'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '안드로이드 시스템 PIN 입력창에서\n아래 번호를 입력하세요:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    pin,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '💡 설정 > 블루투스에서 "AmbientNode"를 탭하고\nPIN 입력 후 "페어링" 버튼을 누르세요.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _startScanning() {
    setState(() {
      _isScanning = true;
      _connectionStates.removeWhere(
          (key, value) => value == '연결 실패' || value.contains('본딩 중'));
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
    setState(() => _isScanning = false);
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();

    setState(() {
      _connectionStates[deviceId] = '연결 중...';
    });

    final success = await widget.bleService.connectToDevice(device);

    if (mounted) {
      if (success) {
        // TestBleService는 본딩 완료 후 success=true 반환
        // BleService는 즉시 success=true 반환

        // TestBleService인 경우 본딩 대기
        if (widget.bleService.runtimeType.toString() == 'TestBleService') {
          setState(() {
            _connectionStates[deviceId] = '본딩 대기 중...';
          });

          // 60초 후에도 본딩 응답이 없으면 실패 처리
          Future.delayed(const Duration(seconds: 60), () {
            if (mounted &&
                (_connectionStates[deviceId]?.contains('본딩') ?? false) &&
                _connectionStates[deviceId] != '연결 완료') {
              setState(() {
                _connectionStates[deviceId] = '연결 실패 (본딩 타임아웃)';
                _checkConnectionStatus();
              });
            }
          });
        } else {
          // BleService는 즉시 완료 처리
          setState(() {
            _connectionStates[deviceId] = '연결 완료';
            _hasConnectedDevice = true;
            widget.onConnectionChanged(true);
          });
        }
      } else {
        setState(() {
          _connectionStates[deviceId] = '연결 실패';
          _checkConnectionStatus();
        });
      }
    }
  }

  void _checkConnectionStatus() {
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
                      final pin = _pairingPins[deviceId];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: connectionState == '연결 완료'
                                ? Colors.green
                                : connectionState == '연결 실패' ||
                                        connectionState.contains('타임아웃')
                                    ? Colors.red
                                    : connectionState.contains('본딩')
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
                                        : connectionState == '연결 실패' ||
                                                connectionState.contains('타임아웃')
                                            ? Colors.red
                                            : connectionState.contains('본딩')
                                                ? Colors.orange
                                                : Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              if (pin != null)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: Colors.orange.shade200),
                                  ),
                                  child: Text(
                                    'PIN: $pin',
                                    style: TextStyle(
                                      color: Colors.orange.shade900,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
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
