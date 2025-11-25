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
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          background: const Color(0xFFF8FAFC),
          surface: Colors.white,
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
    if (_showMain) return const MainShell();
    return SplashScreen(onFinish: () => setState(() => _showMain = true));
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // ★ 테스트 모드 설정
  final bool _isTestMode = true;

  int _index = 0;
  late final BleService ble;

  final _bleDataStreamController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _bleStateSub;
  StreamSubscription? _bleDataSub;

  bool connected = false;
  String deviceName = 'Ambient';

  // --- [상태 변수 관리] ---
  int speed = 0;

  // ★ 모드 관리 (ai_tracking, manual_control, rotation, natural_wind)
  // 기본값은 manual_control로 설정
  String currentMode = 'manual_control';

  String? selectedUserName;
  String? selectedUserImagePath;

  @override
  void initState() {
    super.initState();
    ble = BleService();

    if (!_isTestMode) {
      ble.initialize();
      _bleStateSub = ble.connectionStateStream.listen((state) {
        if (!mounted) return;
        setState(() {
          connected = (state == BleConnectionState.connected);
          if (!connected) {
            speed = 0;
            currentMode = 'manual_control'; // 연결 끊기면 기본값 복귀
          }
        });
        if (state == BleConnectionState.error) _showSnackBar('BLE 오류가 발생했습니다.');
      });

      _bleDataSub = ble.dataStream.listen((data) {
        _bleDataStreamController.add(data);
      });
    } else {
      print("🧪 [Test Mode] 실행 중");
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
    if (_isTestMode) {
      setState(() {
        connected = !connected;
        if (connected) {
          speed = 1;
          deviceName = "Ambient (Mock)";
          _showSnackBar('테스트 모드: 연결됨');
        } else {
          speed = 0;
          currentMode = 'manual_control';
          _showSnackBar('테스트 모드: 연결 해제');
        }
      });
      return;
    }

    if (connected) {
      try {
        await ble.disconnect();
        if (mounted) _showSnackBar('기기 연결이 해제되었습니다.');
      } catch (e) { print(e); }
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => DeviceSelectionScreen(
            bleService: ble,
            onConnectionChanged: (_) {},
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
    final bool isError = message.contains('해제') || message.contains('오류');
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontFamily: 'Sen', color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: isError ? const Color(0xFFFF5252) : const Color(0xFF2D3142),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),
    );
  }

  // --- [BLE 전송 로직] ---

  void _sendData(Map<String, dynamic> data) {
    if (_isTestMode) {
      print("📤 [Mock Send] ${jsonEncode(data)}");
      return;
    }
    if (connected) ble.sendJson(data);
  }

  // 1. 모드 변경 (Mode Change)
  // mode: ai_tracking, manual_control, rotation, natural_wind
  void _setMode(String mode) {
    setState(() => currentMode = mode);

    // 모드 변경 시 별도의 데이터 없이 모드 이름만 전송 (설계 의도 반영)
    _sendData({
      'action': 'mode_change',
      'mode': mode,
      'timestamp': DateTime.now().toIso8601String()
    });

    if(mode == 'ai_tracking') AnalyticsService.onFaceTrackingStart();
  }

  // 2. 속도 변경 (Speed Change)
  // 속도를 수동으로 조절하면 'manual_control'로 강제 복귀
  void _setSpeed(int newSpeed) {
    int target = newSpeed.clamp(0, 5);
    setState(() {
      speed = target;
      // 자연풍이나 회전 모드 등에서 속도를 건드리면 -> 수동 모드로 간주
      if (currentMode != 'manual_control' && currentMode != 'ai_tracking') {
        currentMode = 'manual_control';
      }
    });

    _sendData({
      'action': 'speed_change',
      'speed': target,
      // 속도 조절 시에는 명시적으로 manual 모드로 돌아갔음을 알려주는게 안전할 수 있음
      // 펌웨어 로직에 따라 다르지만, 여기서는 별도 mode_change를 보내지 않고
      // 앱 UI 상태만 manual로 바꿉니다. (펌웨어가 speed_change 받으면 알아서 manual로 인식한다고 가정)
      'timestamp': DateTime.now().toIso8601String()
    });

    AnalyticsService.onSpeedChanged(target);
  }

  // 3. 타이머 설정 (Timer)
  void _setTimer(int seconds) {
    _sendData({
      'action': 'timer',
      'duration_sec': seconds, // 초 단위 전송
      'timestamp': DateTime.now().toIso8601String()
    });
    _showSnackBar(seconds > 0 ? '${seconds ~/ 60}분 후 종료됩니다.' : '타이머가 취소되었습니다.');
  }

  // 4. 수동 조작 (D-Pad Control)
  void _sendManualCommand(String direction, int toggleOn) {
    // 수동 조작 시도가 있으면 모드를 manual로 변경해야 함
    if (currentMode != 'manual_control') {
      _setMode('manual_control');
    }

    String d = direction.isNotEmpty ? direction[0].toLowerCase() : direction;
    _sendData({
      'action': 'angle_change',
      'direction': d,
      'toggleOn': toggleOn,
      'timestamp': DateTime.now().toIso8601String(),
    });

    if (toggleOn == 1) AnalyticsService.onManualControl(d, speed);
  }


  @override
  Widget build(BuildContext context) {
    final screens = [
      // 0: 대시보드
      DashboardScreen(
        connected: connected,
        onConnect: handleConnect,

        speed: speed,
        setSpeed: _setSpeed,

        // ★ [수정] trackingOn 삭제 -> currentMode와 onModeChange 연결
        currentMode: currentMode,
        onModeChange: _setMode,

        // 타이머 및 수동 제어 연결
        onTimerSet: _setTimer,
        onManualControl: _sendManualCommand,

        openAnalytics: () => setState(() => _index = 2),
        deviceName: deviceName,
        selectedUserName: selectedUserName,
        selectedUserImagePath: selectedUserImagePath,
      ),

      // 1: 유저 관리
      ControlScreen(
        connected: connected,
        deviceName: deviceName,
        onConnect: handleConnect,
        dataStream: _bleDataStreamController.stream,
        selectedUserName: selectedUserName,
        onUserSelectionChanged: (name, img) {
          setState(() {
            selectedUserName = name;
            selectedUserImagePath = img;
          });
          AnalyticsService.onUserChanged(name);
        },
        onUserDataSend: _sendData,
      ),

      // 2: 분석
      AnalyticsScreen(selectedUserName: selectedUserName),

      // 3: 설정
      SettingsScreen(
        connected: connected,
        sendJson: _sendData,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: screens,
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16, top: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5)),
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
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _index == index;
    final activeColor = const Color(0xFF6366F1); // Indigo
    final inactiveColor = const Color(0xFF949BA5);

    return GestureDetector(
      onTap: () => setState(() => _index = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        padding: isSelected ? const EdgeInsets.symmetric(horizontal: 20, vertical: 12) : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: isSelected ? activeColor : inactiveColor),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: activeColor, fontWeight: FontWeight.w700, fontSize: 14, fontFamily: 'Sen')),
            ],
          ],
        ),
      ),
    );
  }
}