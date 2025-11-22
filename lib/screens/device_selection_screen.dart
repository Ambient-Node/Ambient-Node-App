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

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> with SingleTickerProviderStateMixin {
  List<BluetoothDevice> _devices = [];
  final Map<String, String> _connectionStates = {};

  bool _isScanning = false;
  bool _hasConnectedDevice = false;

  StreamSubscription? _connectionStateSubscription;
  StreamSubscription? _scanSubscription;

  // 애니메이션 컨트롤러 (레이더 효과)
  late final AnimationController _rippleController;

  @override
  void initState() {
    super.initState();

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _setupListeners();
    _startScanning();
  }

  @override
  void dispose() {
    _stopScanning();
    _connectionStateSubscription?.cancel();
    _rippleController.dispose();
    super.dispose();
  }

  // --- Logic (기존 로직 유지) ---

  void _setupListeners() {
    _connectionStateSubscription = widget.bleService.connectionStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _hasConnectedDevice = (state == BleConnectionState.connected);
        widget.onConnectionChanged(_hasConnectedDevice);

        if (state == BleConnectionState.connected) {
          // 연결 성공 시 스캔 중지 및 애니메이션 정지
          _stopScanning();
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device Connected'),
              backgroundColor: Color(0xFF3A91FF),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (state == BleConnectionState.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connection Failed'), backgroundColor: Colors.red),
          );
        }
      });
    });
  }

  void _startScanning() {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    _rippleController.repeat(); // 애니메이션 시작

    _scanSubscription = widget.bleService.startScan().listen(
          (scanResults) {
        if (mounted) {
          setState(() {
            // 이름이 있는 기기를 우선 정렬
            _devices = scanResults.map((r) => r.device).toList()
              ..sort((a, b) {
                if (a.platformName.isNotEmpty && b.platformName.isEmpty) return -1;
                if (a.platformName.isEmpty && b.platformName.isNotEmpty) return 1;
                return 0;
              });
          });
        }
      },
      onError: (e) {
        if (mounted) setState(() => _isScanning = false);
        _rippleController.stop();
      },
      onDone: () {
        if (mounted) setState(() => _isScanning = false);
        _rippleController.stop();
      },
    );
  }

  void _stopScanning() {
    widget.bleService.stopScan();
    _scanSubscription?.cancel();
    if (mounted) {
      setState(() => _isScanning = false);
      _rippleController.stop();
      _rippleController.reset();
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    final deviceId = device.remoteId.toString();
    _stopScanning();

    setState(() => _connectionStates[deviceId] = 'connecting');

    try {
      await widget.bleService.connect(device);
      if (mounted) {
        setState(() {
          _connectionStates[deviceId] = 'connected';
        });
        if (widget.onDeviceNameChanged != null) {
          widget.onDeviceNameChanged!(device.platformName);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connectionStates[deviceId] = 'failed');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _connectionStates.remove(deviceId));
        });
      }
    }
  }

  // --- UI Building ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Header Section (Radar Animation)
            _buildHeader(),

            const SizedBox(height: 10),

            // 2. Scanning Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isScanning ? "Searching nearby..." : "Scan paused",
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_isScanning)
                    const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3A91FF)),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. Device List
            Expanded(
              child: _devices.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                itemCount: _devices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final device = _devices[index];
                  return _DeviceCard(
                    device: device,
                    connectionState: _connectionStates[device.remoteId.toString()] ?? 'idle',
                    onConnect: () => _connectToDevice(device),
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // Floating Action Button for Scan Control
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? _stopScanning : _startScanning,
        backgroundColor: _isScanning ? Colors.white : const Color(0xFF3A91FF),
        elevation: 4,
        icon: Icon(
          _isScanning ? Icons.stop_rounded : Icons.search_rounded,
          color: _isScanning ? const Color(0xFFFF3B30) : Colors.white,
        ),
        label: Text(
          _isScanning ? "Stop Scan" : "Scan Again",
          style: TextStyle(
            fontFamily: 'Sen',
            fontWeight: FontWeight.bold,
            color: _isScanning ? const Color(0xFF2D3142) : Colors.white,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            offset: Offset(0, 10),
            blurRadius: 20,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Back Button
          Positioned(
            top: 16,
            left: 16,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),

          // Radar Animation
          if (_isScanning)
            CustomPaint(
              painter: _RadarPainter(_rippleController),
              size: const Size(300, 300),
            ),

          // Center Icon
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF3A91FF).withOpacity(0.1),
                ),
                child: const Icon(Icons.bluetooth_searching_rounded, size: 40, color: Color(0xFF3A91FF)),
              ),
              const SizedBox(height: 16),
              const Text(
                "Find Devices",
                style: TextStyle(
                  fontFamily: 'Sen',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2D3142),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.device_unknown_outlined, size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _isScanning ? "Scanning for devices..." : "No devices found",
            style: TextStyle(
              fontFamily: 'Sen',
              fontSize: 16,
              color: Colors.grey[400],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// Sub Widgets
// ==========================================

class _DeviceCard extends StatelessWidget {
  final BluetoothDevice device;
  final String connectionState; // 'idle', 'connecting', 'connected', 'failed'
  final VoidCallback onConnect;

  const _DeviceCard({
    required this.device,
    required this.connectionState,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final hasName = device.platformName.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              hasName ? Icons.headphones_battery_outlined : Icons.bluetooth,
              color: hasName ? const Color(0xFF3A91FF) : Colors.grey[400],
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasName ? device.platformName : "Unknown Device",
                  style: TextStyle(
                    fontFamily: 'Sen',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: hasName ? const Color(0xFF2D3142) : Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  device.remoteId.toString(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                    fontFamily: 'Sen',
                  ),
                ),
              ],
            ),
          ),

          // Connect Button
          _buildActionButton(),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    if (connectionState == 'connecting') {
      return const SizedBox(
        width: 24, height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3A91FF)),
      );
    }

    if (connectionState == 'connected') {
      return const Icon(Icons.check_circle_rounded, color: Color(0xFF4CD964), size: 28);
    }

    return InkWell(
      onTap: onConnect,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F5FF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          "Connect",
          style: TextStyle(
            color: Color(0xFF3A91FF),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ==========================================
// Radar Animation Painter
// ==========================================
class _RadarPainter extends CustomPainter {
  final AnimationController controller;

  _RadarPainter(this.controller) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    // 3개의 물결을 그림
    for (int i = 0; i < 3; i++) {
      final progress = (controller.value + (i / 3)) % 1.0;
      final radius = maxRadius * progress;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      paint.color = const Color(0xFF3A91FF).withOpacity(opacity * 0.3);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}