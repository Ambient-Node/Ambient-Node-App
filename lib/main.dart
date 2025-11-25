import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ambient_node/screens/splash_screen.dart';
import 'package:ambient_node/screens/dashboard_screen.dart';
import 'package:ambient_node/screens/analytics_screen.dart';
import 'package:ambient_node/screens/control_screen.dart';
import 'package:ambient_node/screens/device_selection_screen.dart';
import 'package:ambient_node/screens/settings_screen.dart';
import 'package:ambient_node/services/analytics_service.dart';
import 'package:ambient_node/services/ble_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ambient Node',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SplashWrapper(),
    );
  }
}

class SplashWrapper extends StatefulWidget {
  const SplashWrapper({super.key});

  @override
  State<SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<SplashWrapper> {
  bool _showMain = false;

  @override
  Widget build(BuildContext context) {
    if (_showMain) return const MainShell();

    return SplashScreen(
      onFinish: () {
        setState(() => _showMain = true);
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final BleService ble;

  final _bleDataStreamController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _bleStateSub;
  StreamSubscription? _bleDataSub;

  bool connected = false;
  String deviceName = 'Ambient';

  // 상태 변수
  int speed = 0;
  bool trackingOn = false;

  String? selectedUserName;
  String? selectedUserImagePath;
  String? selectedUserId; // userId 저장 추가

  @override
  void initState() {
    super.initState();
    ble = BleService();
    ble.initialize();

    _bleStateSub = ble.connectionStateStream.listen((state) {
      print('🔵 [Main] 연결 상태 변경: $state');
      if (!mounted) return;

      setState(() {
        connected = (state == BleConnectionState.connected);
        if (!connected) {
          speed = 0;
          trackingOn = false;
        }
      });

      if (state == BleConnectionState.error) {
        _showSnackBar('BLE 오류가 발생했습니다.');
      }
    });

    _bleDataSub = ble.dataStream.listen((data) {
      print('🔵 [Main] 데이터 수신: $data');
      _bleDataStreamController.add(data);
    });

    AnalyticsService.onUserChanged(selectedUserName);
  }

  @override
  void dispose() {
    _bleStateSub?.cancel();
    _bleDataSub?.cancel();
    _bleDataStreamController.close();
    super.dispose();
  }

  Future<void> handleConnect() async {
    if (connected) {
      try {
        await ble.disconnect();
        if (mounted) _showSnackBar('기기 연결이 해제되었습니다.');
      } catch (e) {
        print('[Main] 연결 해제 오류: $e');
      }
    } else {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => DeviceSelectionScreen(
          bleService: ble,
          onConnectionChanged: (isConnected) {},
          onDeviceNameChanged: (name) {
            if (mounted) setState(() => deviceName = name);
          },
        ),
      ));
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  // 대시보드에서 속도 변경 시 호출
  void _sendSpeedChange(int newSpeed) {
    if (!connected) return;

    int targetSpeed = newSpeed.clamp(0, 5);
    final data = {
      'action': 'speed_change',
      'speed': targetSpeed,
      'user_list': _getCurrentUserList(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      print('📤 [BLE] 풍속 변경 요청: $data');
      ble.sendJson(data);
    } catch (e) {
      print('전송 실패: $e');
    }
  }

  // 대시보드에서 모드 변경 시 호출
  void _sendModeChange(bool isAiMode) {
    if (!connected) return;

    final data = {
      'action': 'mode_change',
      'mode': isAiMode ? 'ai' : 'manual',
      'user_list': _getCurrentUserList(),
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      print('📤 [BLE] 모드 변경 요청: $data');
      ble.sendJson(data);
    } catch (e) {
      print('전송 실패: $e');
    }
  }

  // 현재 선택된 사용자 정보를 user_list 형식으로 반환하는 헬퍼
  List<Map<String, dynamic>> _getCurrentUserList() {
    if (selectedUserId == null || selectedUserName == null) return [];

    return [
      {
        'user_id': selectedUserId,
        'username': selectedUserName,
        'role': 1,
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        connected: connected,
        onConnect: handleConnect,
        speed: speed,
        setSpeed: (v) {
          setState(() => speed = v);
          _sendSpeedChange(v);
          try {
            AnalyticsService.onSpeedChanged(v);
          } catch (e) {}
        },
        trackingOn: trackingOn,
        setTrackingOn: (v) {
          setState(() => trackingOn = v);
          _sendModeChange(v);
          try {
            v ? AnalyticsService.onFaceTrackingStart() : AnalyticsService.onFaceTrackingStop();
          } catch (e) {}
        },
        openAnalytics: () => setState(() => _index = 2),
        deviceName: deviceName,
        selectedUserName: selectedUserName,
        selectedUserImagePath: selectedUserImagePath,
      ),
      ControlScreen(
        connected: connected,
        deviceName: deviceName,
        onConnect: handleConnect,
        dataStream: _bleDataStreamController.stream,
        selectedUserName: selectedUserName,
        onUserSelectionChanged: (userName, userImagePath, userId) {
          setState(() {
            selectedUserName = userName;
            selectedUserImagePath = userImagePath;
            this.selectedUserId = userId;
          });
          try {
            AnalyticsService.onUserChanged(userName);
          } catch (e) {}
        },
        onUserDataSend: (data) {
          print('🔵 BLE 전송: $data');
          ble.sendJson(data);
        },
      ),
      AnalyticsScreen(selectedUserName: selectedUserName),
      SettingsScreen(
        connected: connected,
        sendJson: (data) => ble.sendJson(data),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: screens,
        ),
      ),
      bottomNavigationBar: Container(
        height: 89,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(
                icon: Icons.dashboard_outlined,
                label: '대시보드',
                isSelected: _index == 0,
                onTap: () => setState(() => _index = 0)),
            _buildNavItem(
                icon: Icons.control_camera,
                label: '제어',
                isSelected: _index == 1,
                onTap: () => setState(() => _index = 1)),
            _buildNavItem(
                icon: Icons.analytics_outlined,
                label: '분석',
                isSelected: _index == 2,
                onTap: () => setState(() => _index = 2)),
            _buildNavItem(
                icon: Icons.settings_outlined,
                label: '설정',
                isSelected: _index == 3,
                onTap: () => setState(() => _index = 3)),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 24,
                color: isSelected
                    ? const Color(0xFF3A90FF)
                    : const Color(0xFF838799)),
            const SizedBox(height: 5),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color:
                    isSelected ? const Color(0xFF3A90FF) : const Color(0xFF838799),
                    fontSize: 13,
                    fontFamily: 'Sen',
                    fontWeight: FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
