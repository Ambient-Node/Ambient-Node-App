import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // [추가] 상태바 제어를 위해 필요

// [필수] 화면들 import
import 'package:ambient_node/screens/splash_screen.dart';
import 'package:ambient_node/screens/dashboard_screen.dart';
import 'package:ambient_node/screens/analytics_screen.dart';
import 'package:ambient_node/screens/control_screen.dart';
import 'package:ambient_node/screens/device_selection_screen.dart';
import 'package:ambient_node/screens/settings_screen.dart';

// [필수] 서비스들 import
import 'package:ambient_node/services/analytics_service.dart';
import 'package:ambient_node/services/ble_service.dart';

void main() {
  // [추가] 상태바 투명하게 설정 (앱이 더 넓어보임)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // 어두운 아이콘
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

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
        // [디자인] 글로벌 테마 설정
        fontFamily: 'Sen',
        scaffoldBackgroundColor: const Color(0xFFF6F7F8), // 공통 배경색
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A91FF), // 메인 블루 컬러
          background: const Color(0xFFF6F7F8),
        ),
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
    if (_showMain) {
      return const MainShell();
    }

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

  // BLE 데이터 스트림 중계용 컨트롤러
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
      // ControlScreen 등 다른 곳에서 구독할 수 있도록 중계
      _bleDataStreamController.add(data);
    });

    try {
      AnalyticsService.onUserChanged(selectedUserName);
    } catch (e) {
      print('Analytics error: $e');
    }
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
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DeviceSelectionScreen(
            bleService: ble,
            onConnectionChanged: (isConnected) {},
            onDeviceNameChanged: (name) {
              if (mounted) setState(() => deviceName = name);
            },
          ),
        ),
      );
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Sen')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sendSpeedChange(int newSpeed) {
    if (!connected) return;
    int targetSpeed = newSpeed.clamp(0, 5);
    final data = {
      'action': 'speed_change',
      'speed': targetSpeed,
      'timestamp': DateTime.now().toIso8601String(),
    };
    try {
      ble.sendJson(data);
    } catch (e) {
      print('전송 실패: $e');
    }
  }

  void _sendModeChange(bool isTrackingOn) {
    if (!connected) return;
    final data = {
      'action': 'mode_change',
      'mode': isTrackingOn ? 'ai' : 'manual',
      'timestamp': DateTime.now().toIso8601String(),
    };
    try {
      ble.sendJson(data);
    } catch (e) {
      print('전송 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      // 0: 대시보드
      DashboardScreen(
        connected: connected,
        onConnect: handleConnect,
        speed: speed,
        setSpeed: (v) {
          setState(() => speed = v);
          _sendSpeedChange(v);
          try { AnalyticsService.onSpeedChanged(v); } catch (_) {}
        },
        trackingOn: trackingOn,
        setTrackingOn: (v) {
          setState(() => trackingOn = v);
          _sendModeChange(v);
          try {
            v ? AnalyticsService.onFaceTrackingStart() : AnalyticsService.onFaceTrackingStop();
          } catch (_) {}
        },
        openAnalytics: () => setState(() => _index = 2),
        onRemoteTap: () => setState(() => _index = 1), // 리모컨 탭으로 이동
        deviceName: deviceName,
        selectedUserName: selectedUserName,
        selectedUserImagePath: selectedUserImagePath,
      ),

      // 1: 제어 (리모컨)
      ControlScreen(
        connected: connected,
        deviceName: deviceName,
        onConnect: handleConnect,
        dataStream: _bleDataStreamController.stream,
        selectedUserName: selectedUserName,
        onUserSelectionChanged: (userName, userImagePath) {
          setState(() {
            selectedUserName = userName;
            selectedUserImagePath = userImagePath;
          });
          try { AnalyticsService.onUserChanged(userName); } catch (_) {}
        },
        onUserDataSend: (data) => ble.sendJson(data),
      ),

      // 2: 분석
      AnalyticsScreen(selectedUserName: selectedUserName),

      // 3: 설정
      SettingsScreen(
        connected: connected,
        sendJson: (data) => ble.sendJson(data),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      extendBody: true, // 바텀 네비게이션바 뒤로 컨텐츠가 보이게 (투명도 효과 극대화)
      body: IndexedStack(
        index: _index,
        children: screens,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16, top: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9), // 살짝 투명하게
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5), // 부드러운 그림자
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavItem(0, Icons.dashboard_rounded, "홈"),
              _buildNavItem(1, Icons.gamepad_rounded, "제어"),
              _buildNavItem(2, Icons.bar_chart_rounded, "분석"),
              _buildNavItem(3, Icons.settings_rounded, "설정"),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _index == index;
    // Analytics 탭에서 사용된 메인 블루 컬러
    final activeColor = const Color(0xFF3A91FF);
    final inactiveColor = const Color(0xFF949BA5);

    return GestureDetector(
      onTap: () => setState(() => _index = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack, // 튕기는 듯한 부드러운 애니메이션
        padding: isSelected
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? activeColor : inactiveColor,
            ),
            // 선택되었을 때만 텍스트 표시 (공간 효율 + 심플함)
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: activeColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  fontFamily: 'Sen',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}