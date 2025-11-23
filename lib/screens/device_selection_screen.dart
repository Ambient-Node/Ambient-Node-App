import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ambient_node/services/ble_service.dart'; // BleService, BleConnectionState 포함

class UIColors {
  static const kColorCyan = Color(0xFF00BCD4);
  static const kColorSlate200 = Color(0xFFE2E8F0);
  static const kColorSlate500 = Color(0xFF64748B);
  static const kColorBgLight = Color(0xFFF8FAFC);
}

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

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> with SingleTickerProviderStateMixin {
  List<BluetoothDevice> _devices = [];
  final Map<String, String> _connectionStates = {};

  bool _isScanning = false;
  bool _hasConnectedDevice = false;

  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _scanSubscription;

  // 레이더 애니메이션 컨트롤러
  late AnimationController _radarController;

  @override
  void initState() {
    super.initState();
    // 레이더 애니메이션 초기화
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _setupListeners();
    _startScanning();
  }

  @override
  void dispose() {
    _radarController.dispose();
    _stopScanning();
    _connectionStateSubscription?.cancel();
    super.dispose();
  }

  void _setupListeners() {
    _connectionStateSubscription = widget.bleService.connectionStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _hasConnectedDevice = (state == BleConnectionState.connected);
        widget.onConnectionChanged(_hasConnectedDevice);

        if (state == BleConnectionState.connected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('디바이스가 연결되었습니다'), backgroundColor: Colors.green),
          );
          Navigator.of(context).pop();
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
    // 애니메이션 재개
    if (!_radarController.isAnimating) _radarController.repeat();

    _scanSubscription = widget.bleService.startScan().listen(
          (scanResults) {
        if (mounted) {
          setState(() {
            _devices = scanResults.map((r) => r.device).toList();
          });
        }
      },
      onError: (e) {
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
    if (mounted) {
      setState(() => _isScanning = false);
      _radarController.stop(); // 스캔 중지 시 애니메이션 정지
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();
    _stopScanning();
    setState(() => _connectionStates[deviceId] = '연결 중...');

    try {
      await widget.bleService.connect(device);
      if (mounted) {
        setState(() {
          _connectionStates[deviceId] = '연결 완료';
          if (widget.onDeviceNameChanged != null) {
            widget.onDeviceNameChanged!(device.platformName);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connectionStates[deviceId] = '연결 실패');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('연결 실패: $e'), backgroundColor: Colors.red),
        );
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
      print('해제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 커스텀 헤더
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      '기기 연결',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // 밸런스용 여백
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 레이더 애니메이션 영역
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 200,
                  height: 200,
                  child: AnimatedBuilder(
                    animation: _radarController,
                    builder: (context, child) {
                      return Stack(
                        children: [0, 1, 2].map((i) {
                          double radius = 100 * ((_radarController.value + i * 0.33) % 1.0);
                          double opacity = 1.0 - ((_radarController.value + i * 0.33) % 1.0);
                          // 스캔 중이 아닐 때는 고정된 원 하나만 표시하거나 숨김 처리 가능
                          if (!_isScanning) opacity = 0.1;

                          return Center(
                            child: Container(
                              width: radius * 2,
                              height: radius * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: UIColors.kColorCyan.withOpacity(opacity),
                                    width: 1.5
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
                Icon(
                  Icons.bluetooth,
                  size: 40,
                  color: _isScanning ? const Color(0xFF00BCD4) : Colors.grey,
                ),
              ],
            ),

            const SizedBox(height: 20),
            Text(
              _isScanning ? "주변 기기 검색 중..." : "검색 완료",
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            if (!_isScanning)
              TextButton(
                onPressed: _startScanning,
                child: const Text("다시 스캔", style: TextStyle(color: UIColors.kColorCyan)),
              ),

            const SizedBox(height: 20),

            // 기기 리스트
            Expanded(
              child: _devices.isEmpty
                  ? Center(
                child: Text(
                  _isScanning ? '' : '발견된 기기가 없습니다.',
                  style: TextStyle(color: Colors.grey[400]),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildDeviceTile(_devices[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile(BluetoothDevice device) {
    final deviceId = device.remoteId.toString();
    final status = _connectionStates[deviceId] ?? '';
    final isConnected = widget.bleService.currentState == BleConnectionState.connected &&
        status == '연결 완료';
    final deviceName = device.platformName.isNotEmpty ? device.platformName : '알 수 없는 기기';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: UIColors.kColorSlate200.withOpacity(0.5),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: isConnected ? UIColors.kColorCyan : UIColors.kColorSlate200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isConnected ? const Color(0xFFE0F7FA) : Colors.grey[100],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.air,
              color: isConnected ? const Color(0xFF00BCD4) : Colors.grey,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  deviceId,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: isConnected
                ? () => _disconnectFromDevice(device)
                : () => _connectToDevice(device),
            style: ElevatedButton.styleFrom(
              backgroundColor: isConnected ? Colors.grey[300] : const Color(0xFF00BCD4),
              foregroundColor: isConnected ? Colors.black87 : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(
              status.isNotEmpty ? status : (isConnected ? "해제" : "연결"),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}