import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ambient_node/screens/splash_screen.dart';
import 'package:ambient_node/screens/dashboard_screen.dart';
import 'package:ambient_node/screens/analytics_screen.dart';
import 'package:ambient_node/screens/control_screen.dart';
import 'package:ambient_node/screens/device_selection_screen.dart';
import 'package:ambient_node/screens/settings_screen.dart';
import 'package:ambient_node/utils/snackbar_helper.dart';
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
  final bool _isTestMode = true;

  int _index = 0;
  late final BleService ble;

  final _bleDataStreamController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _bleStateSub;
  StreamSubscription? _bleDataSub;

  bool connected = false;
  bool _wasConnected = false;
  String deviceName = 'Ambient';

  int speed = 0;
  String _movementMode = 'manual'; 
  bool _isNaturalWind = false;     

  String? selectedUserId;
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
        if (state == BleConnectionState.disconnected) {
          setState(() {
            connected = false;
            speed = 0;
            _movementMode = 'manual_control';
            _isNaturalWind = false;
          });

          if (_wasConnected) {
            showAppSnackBar(context, '기기와의 연결이 끊어졌습니다.', type: AppSnackType.error);
          }
          _wasConnected = false;
        } else if (state == BleConnectionState.connected) {
          setState(() {
            connected = true;
          });
          _wasConnected = true;
          showAppSnackBar(context, '디바이스가 연결되었습니다', type: AppSnackType.connected);
        } else if (state == BleConnectionState.error) {
          showAppSnackBar(context, 'BLE 오류가 발생했습니다.', type: AppSnackType.error);
        }
      });

      _bleDataSub = ble.dataStream.listen((data) {
        _bleDataStreamController.add(data);

        if (data['event_type'] == 'speed_change') {
           int s = data['speed'] ?? 0;
           setState(() => speed = s);
        }
        if (data['event_type'] == 'mode_change') {
           String type = data['type'] ?? '';
           String mode = data['mode'] ?? '';
           if (type == 'wind') {
             setState(() => _isNaturalWind = (mode == 'natural_wind'));
           } else if (type == 'motor') {
             setState(() => _movementMode = (mode == 'manual_control' ? 'manual' : mode));
           }
        }

        if (data['type'] == 'SHUTDOWN') {
          if (!mounted) return;
          setState(() {
            connected = false;
            speed = 0;
            _movementMode = 'manual_control';
            _isNaturalWind = false;
          });
          _showSnackBar('게이트웨이 종료 알림을 받았습니다.');
          ble.disconnect();
        }
      });
    } else {
      print("🧪 [Test Mode] 실행 중");
    }
  }

  // [수정] 타이머 설정용 (Map 반환) - DashboardScreen에서 사용
  Future<Map<String, dynamic>?> _setTimer(int seconds) async {
    if (_isTestMode) {
      return {'success': true, 'end_time': DateTime.now().add(Duration(seconds: seconds)).toIso8601String()};
    }

    if (!connected) {
      _showSnackBar('기기 연결이 필요합니다.');
      return null;
    }

    return await ble.sendRequestWithAck({
      'action': 'timer',
      'duration_sec': seconds,
      'timestamp': DateTime.now().toIso8601String()
    }, timeout: const Duration(seconds: 3));
  }

  // [추가] ControlScreen용 (Bool 반환) - ACK 여부만 필요할 때
  Future<bool> _sendDataAwaitAckBool(Map<String, dynamic> data) async {
    if (_isTestMode) return true;
    if (!connected) return false;

    final res = await ble.sendRequestWithAck(data);
    return res != null;
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
          _movementMode = 'manual';
          _isNaturalWind = false;
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
    final bool isError = message.contains('해제') || message.contains('오류') || message.contains('실패');
    showAppSnackBar(context, message, type: isError ? AppSnackType.error : AppSnackType.info);
  }

  void _sendData(Map<String, dynamic> data) {
    if (selectedUserId != null) {
      data['user_id'] = selectedUserId;
    }
    if (_isTestMode) {
      print("📤 [Mock Send] ${jsonEncode(data)}");
      return;
    }
    if (connected) ble.sendJson(data);
  }

  void _setMovementMode(String mode) {
    setState(() => _movementMode = mode);
    String finalMode = mode;
    if (mode == 'manual') finalMode = 'manual_control';

    _sendData({
      'action': 'mode_change',
      'type': 'motor',
      'mode': finalMode,
      'timestamp': DateTime.now().toIso8601String()
    });
    if(mode == 'ai_tracking') AnalyticsService.onFaceTrackingStart();
  }

   void _setNaturalWind(bool active) {
    setState(() => _isNaturalWind = active);
    _sendData({
      'action': 'mode_change',
      'type': 'wind',
      'mode': active ? 'natural_wind' : 'normal_wind',
      'timestamp': DateTime.now().toIso8601String()
    });
    if (!active) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (!mounted) return;
        _sendData({
          'action': 'speed_change',
          'speed': speed,
          'timestamp': DateTime.now().toIso8601String()
        });
      });
    }
  }

  void _setSpeed(int newSpeed) {
    int target = newSpeed.clamp(0, 5);
    setState(() {
      speed = target;
      if (_isNaturalWind) {
        _isNaturalWind = false;
        _sendData({
          'action': 'mode_change',
          'type': 'wind',
          'mode': 'normal_wind',
          'timestamp': DateTime.now().toIso8601String()
        });
      }
    });
    _sendData({'action': 'speed_change', 'speed': target, 'timestamp': DateTime.now().toIso8601String()});
    AnalyticsService.onSpeedChanged(target);
  }

  void _sendManualCommand(String direction, int toggleOn) {
    if (_movementMode != 'manual') {
      _setMovementMode('manual');
    }
    String d = direction.isNotEmpty ? direction[0].toLowerCase() : direction;
    _sendData({
      'action': 'direction_change',
      'direction': d,
      'toggleOn': toggleOn,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (toggleOn == 1) AnalyticsService.onManualControl(d, speed);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        connected: connected,
        onConnect: handleConnect,
        speed: speed,
        setSpeed: _setSpeed,
        movementMode: _movementMode,
        isNaturalWind: _isNaturalWind,
        onMovementModeChange: _setMovementMode,
        onNaturalWindChange: _setNaturalWind,
        onTimerSet: _setTimer, // [핵심] Map? 반환
        onManualControl: _sendManualCommand,
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
        onUserSelectionChanged: (id, name, img) {
          setState(() {
            selectedUserId = id;
            selectedUserName = name;
            selectedUserImagePath = img;
          });
          AnalyticsService.onUserChanged(name);
        },
        onUserDataSend: _sendData,
        onUserDataSendAwait: _sendDataAwaitAckBool, // [핵심] Bool 반환
      ),

      AnalyticsScreen(selectedUserName: selectedUserName),

      SettingsScreen(
        connected: connected,
        sendJson: _sendData,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      extendBody: true,
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.only(bottom: 20, left: 16, right: 16, top: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
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
    final activeColor = const Color(0xFF6366F1);
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