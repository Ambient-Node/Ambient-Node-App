import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  // 상태바 투명하게 설정
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
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
        fontFamily: 'Sen',
        scaffoldBackgroundColor: const Color(0xFFF6F7F8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A91FF),
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
  // ★★★ [테스트 모드 스위치] ★★★
  // true: 가상 연결 모드 (블루투스 없이 UI/UX 테스트 가능)
  // false: 실제 블루투스 연결 모드
  final bool _isTestMode = true;

  int _index = 0;
  late final BleService ble;

  final _bleDataStreamController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _bleStateSub;
  StreamSubscription? _bleDataSub;

  bool connected = false;
  String deviceName = 'Ambient (Test)';

  int speed = 0;
  bool trackingOn = false;

  String? selectedUserName;
  String? selectedUserImagePath;

  @override
  void initState() {
    super.initState();
    ble = BleService();

    if (!_isTestMode) {
      // [실제 모드] BLE 초기화 및 리스너 등록
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
        _bleDataStreamController.add(data);
      });
    } else {
      // [테스트 모드] 초기화 로직 없음 (가상 연결 대기)
      print("🧪 [Test Mode] 앱이 테스트 모드로 실행되었습니다.");
    }

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

  /// 연결 핸들러 (테스트 모드 분기)
  Future<void> handleConnect() async {
    // [테스트 모드] 가상 연결 처리
    if (_isTestMode) {
      setState(() {
        connected = !connected; // 토글
        if (connected) {
          speed = 1; // 연결 시 기본 속도 1
          deviceName = "Ambient (Mock)";
          _showSnackBar('테스트 모드: 가상 연결됨');

          // 가상 데이터 수신 시뮬레이션 (예: 2초 후 얼굴 감지)
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && connected) {
              print("🧪 [Test] 가상 데이터 수신: FACE_DETECTED");
              _bleDataStreamController.add({
                'type': 'FACE_DETECTED',
                'user_id': 'test_user'
              });
            }
          });
        } else {
          speed = 0;
          trackingOn = false;
          _showSnackBar('테스트 모드: 연결 해제됨');
        }
      });
      return;
    }

    // [실제 모드]
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

  // --- 가상 전송 헬퍼 ---
  void _mockSendJson(Map<String, dynamic> data) {
    print("📤 [Test Mock Send] ${jsonEncode(data)}");

    // 사용자 등록/수정 등의 경우 가짜 ACK 응답
    if (data['action'] == 'user_register' || data['action'] == 'user_update') {
      Future.delayed(const Duration(milliseconds: 500), () {
        _bleDataStreamController.add({
          'type': 'REGISTER_ACK',
          'success': true,
          'user_id': data['user_id']
        });
        print("🧪 [Test] 가상 응답: REGISTER_ACK (Success)");
      });
    }
  }

  // --- 명령 전송 함수들 ---

  void _sendSpeedChange(int newSpeed) {
    int targetSpeed = newSpeed.clamp(0, 5);
    final data = {
      'action': 'speed_change',
      'speed': targetSpeed,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (_isTestMode) {
      _mockSendJson(data);
      return;
    }

    if (!connected) return;
    try {
      ble.sendJson(data);
    } catch (e) {
      print('전송 실패: $e');
    }
  }

  void _sendModeChange(bool isTrackingOn) {
    final data = {
      'action': 'mode_change',
      'mode': isTrackingOn ? 'ai' : 'manual',
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (_isTestMode) {
      _mockSendJson(data);
      return;
    }

    if (!connected) return;
    try {
      ble.sendJson(data);
    } catch (e) {
      print('전송 실패: $e');
    }
  }

  void _sendCommand(String direction, int toggleOn) {
    String d = direction.isNotEmpty ? direction[0].toLowerCase() : direction;
    final data = {
      'action': 'angle_change',
      'direction': d,
      'toggleOn': toggleOn,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (_isTestMode) {
      _mockSendJson(data);
      // 분석 로그 기록 시뮬레이션
      if (toggleOn == 1) {
        AnalyticsService.onManualControl(d, speed);
      }
      return;
    }

    if (!connected) return;
    try {
      ble.sendJson(data);
      if (toggleOn == 1) {
        AnalyticsService.onManualControl(d, speed);
      }
    } catch (e) {
      print('전송 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      // 0: 대시보드 (수동 제어 기능 통합)
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
        onManualControl: _sendCommand,
        deviceName: deviceName,
        selectedUserName: selectedUserName,
        selectedUserImagePath: selectedUserImagePath,
      ),

      // 1: 사용자 관리 (구 제어 탭)
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
        onUserDataSend: (data) {
          if (_isTestMode) {
            _mockSendJson(data);
          } else {
            ble.sendJson(data);
          }
        },
      ),

      // 2: 분석
      AnalyticsScreen(selectedUserName: selectedUserName),

      // 3: 설정
      SettingsScreen(
        connected: connected,
        sendJson: (data) {
          if (_isTestMode) {
            _mockSendJson(data);
          } else {
            ble.sendJson(data);
          }
        },
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: screens,
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16, top: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavItem(0, Icons.dashboard_rounded, "홈"),
              _buildNavItem(1, Icons.people_alt_rounded, "유저"),
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
    final activeColor = const Color(0xFF3A91FF);
    final inactiveColor = const Color(0xFF949BA5);

    return GestureDetector(
      onTap: () => setState(() => _index = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
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