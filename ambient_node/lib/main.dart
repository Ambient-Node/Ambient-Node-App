// main.dart
// Flutter prototype for 'Circulator' app
// - Dashboard, Face Select & Manual Control, Analytics screens
// - Mock AI / BLE services; replace with real implementations when available

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:ambient_node/services/ble_service.dart';
import 'package:ambient_node/services/mock_ai_service.dart';
import 'package:ambient_node/screens/dashboard_screen.dart';
import 'package:ambient_node/screens/control_screen.dart';
import 'package:ambient_node/screens/analytics_screen.dart';
import 'package:ambient_node/screens/device_selection_screen.dart';

void main() {
  runApp(const CirculatorApp());
}

class CirculatorApp extends StatelessWidget {
  const CirculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Circulator',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MainShell(),
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
  final ble = BleService(
    namePrefix: 'Ambient',
    serviceUuid: Guid('12345678-1234-5678-1234-56789abcdef0'),
    writeCharUuid: Guid('12345678-1234-5678-1234-56789abcdef1'),
    notifyCharUuid: Guid('12345678-1234-5678-1234-56789abcdef2'),
  );
  final ai = MockAIService();

  bool connected = false;
  bool powerOn = true;
  int speed = 60;
  bool trackingOn = true;
  String? selectedFaceId;

  @override
  void initState() {
    super.initState();
    ai.start();

    // BLE 연결 상태 모니터링 설정
    ble.onConnectionStateChanged = (isConnected) {
      if (mounted) {
        setState(() => connected = isConnected);
      }
    };
  }

  @override
  void dispose() {
    ai.dispose();
    ble.dispose();
    super.dispose();
  }

  Future<void> handleConnect() async {
    // 기기 선택 화면 열기
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeviceSelectionScreen(
          bleService: ble,
          onConnectionChanged: (isConnected) {
            setState(() => connected = isConnected);
          },
        ),
      ),
    );
  }

  void sendState() {
    // 연결 상태와 무관하게 항상 전송 (디버깅용)
    debugPrint('sendState called - connected: $connected, powerOn: $powerOn');

    // JSON 데이터 구성 (null 값 제거)
    final Map<String, dynamic> data = {
      'powerOn': powerOn,
      'speed': powerOn ? speed : 0,
      'trackingOn': powerOn ? trackingOn : false,
      'deviceName': 'FlutterApp', // 기기 이름 추가
      'timestamp': DateTime.now().millisecondsSinceEpoch, // 타임스탬프 추가
    };

    // selectedFaceId가 null이 아닐 때만 추가
    if (powerOn && selectedFaceId != null) {
      data['selectedFaceId'] = selectedFaceId;
    } else {
      data['selectedFaceId'] = ""; // null 대신 빈 문자열
    }

    debugPrint('Sending data: $data');
    ble.send(data);
  }

  @override
  Widget build(BuildContext context) {
    // build 메서드에서 자동 전송 제거 - 상태 변경 시에만 전송

    final screens = [
      DashboardScreen(
        connected: connected,
        onConnect: handleConnect,
        powerOn: powerOn,
        setPowerOn: (v) {
          setState(() => powerOn = v);
          // 전원 상태 변경 시 즉시 전송
          sendState();
        },
        speed: speed,
        setSpeed: (v) {
          setState(() => speed = v);
          // 속도 변경 시 즉시 전송
          sendState();
        },
        trackingOn: trackingOn,
        setTrackingOn: (v) {
          setState(() => trackingOn = v);
          // 추적 상태 변경 시 즉시 전송
          sendState();
        },
        openControl: () => setState(() => _index = 1),
      ),
      ControlScreen(
        ai: ai,
        trackingOn: trackingOn,
        setTrackingOn: (v) => setState(() => trackingOn = v),
        selectedFaceId: selectedFaceId,
        selectFace: (id) {
          setState(() => selectedFaceId = id);
          ai.select(id);
        },
        manualMove: (vec) => ble.send({
          'manual': {'x': vec.dx, 'y': vec.dy}
        }),
      ),
      const AnalyticsScreen(),
    ];

    return Scaffold(
      body: SafeArea(child: IndexedStack(index: _index, children: screens)),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '대시보드'),
          BottomNavigationBarItem(icon: Icon(Icons.person_search), label: '제어'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: '분석'),
        ],
      ),
    );
  }
}
