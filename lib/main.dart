import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ambient_node/screens/splash_screen.dart';
import 'package:ambient_node/screens/dashboard_screen.dart';
import 'package:ambient_node/screens/analytics_screen.dart';
import 'package:ambient_node/screens/control_screen.dart';
import 'package:ambient_node/screens/device_selection_screen.dart';
import 'package:ambient_node/screens/settings_screen.dart';
import 'package:ambient_node/services/analytics_service.dart';
import 'package:ambient_node/services/ble_service.dart';
import 'package:ambient_node/services/user_service.dart'; // UserService 추가
import 'package:ambient_node/services/test_ble_service.dart'; // 추가

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
        fontFamily: 'Sen',
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
  // late final BleService ble; 원래 코드
  late final dynamic ble;

  // 서비스 인스턴스
  late final AnalyticsService analyticsService;
  late final UserService userService;

  final _bleDataStreamController = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _bleStateSub;
  StreamSubscription? _bleDataSub;

  bool connected = false;
  String deviceName = 'Ambient';

  // 대시보드 상태 변수 (UI 표시용)
  // 실제 제어 명령은 즉시 전송되지만, UI 반응성을 위해 로컬 변수 유지
  int speed = 0;
  bool trackingOn = false;

  @override
  void initState() {
    super.initState();

    const bool isTestMode = true;
    if (isTestMode) {
      ble = TestBleService(); // 가짜 서비스 주입
    } else {
      ble = BleService(); // 진짜 서비스 주입
    }

    analyticsService = AnalyticsService();
    userService = UserService();
    ble.initialize();

    // [중요] 서비스들 연결 (Dependency Injection)
    // UserService와 AnalyticsService가 BLE를 통해 데이터를 보내도록 설정
    userService.init(onSendData: ble.sendJson);

    // analyticsService.init(onPublish: _sendMqttViaBle);
    // *참고: BLE Gateway가 MQTT 브리지 역할을 하므로,
    // 앱에서는 특정 포맷으로 BLE를 보내면 Gateway가 MQTT로 변환해서 쏴주는 구조라고 가정하거나,
    // 혹은 앱이 직접 MQTT를 쓰지 않고 BLE 커맨드만 보내면 Gateway가 알아서 처리하는 구조임.
    // 현재 구조상 앱은 'action' 기반 JSON을 보내면 Gateway가 처리함.
    // 따라서 AnalyticsService의 requestAllStats도 BLE 커맨드로 변환 필요.

    // [중요] TestBleService일 경우 MQTT 전송 함수도 가짜로 연결
    analyticsService.init(onPublish: (topic, payload) {
      print("🧪 [TestMqtt] Topic: $topic, Payload: $payload");
    });

    // 2. BLE 상태 리스너
    _bleStateSub = ble.connectionStateStream.listen((state) {
      debugPrint('🔵 [Main] 연결 상태 변경: $state');
      if (!mounted) return;

      setState(() {
        connected = (state == BleConnectionState.connected);
        if (!connected) {
          speed = 0;
          trackingOn = false;
        }
      });

      if (state == BleConnectionState.connected) {
        // 연결 시 초기 데이터 요청 등 수행 가능
      } else if (state == BleConnectionState.error) {
        _showSnackBar('BLE 오류가 발생했습니다.');
      }
    });

    // 3. 데이터 수신 리스너 (라우팅)
    _bleDataSub = ble.dataStream.listen((data) {
      debugPrint('🔵 [Main] 데이터 수신: $data');
      _bleDataStreamController.add(data); // 개별 화면들이 구독

      // 통계 응답이면 AnalyticsService로 전달
      if (data['type'] == 'STATS_RESPONSE' || data.containsKey('request_id')) {
        // Gateway가 MQTT 응답을 BLE Notify로 그대로 줄 경우
        analyticsService.handleResponse(data);
      }
    });
  }

  // AnalyticsService용 어댑터 함수
  // 앱 -> BLE -> Gateway -> MQTT -> DB Service 순으로 전달됨
  void _sendMqttViaBle(String topic, Map<String, dynamic> payload) {
    if (!connected) return;

    // Gateway가 topic을 인식해서 MQTT로 쏘게 하려면
    // BLE 프로토콜에 topic 필드를 포함해서 보내야 함.
    final blePayload = {
      'action': 'mqtt_publish', // Gateway에서 이 액션을 처리해야 함 (아래 Python 코드 수정 참고)
      'topic': topic,
      'payload': payload,
      'timestamp': DateTime.now().toIso8601String(),
    };

    ble.sendJson(blePayload);
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
        debugPrint('[Main] 연결 해제 오류: $e');
      }
    } else {
      if (ble is TestBleService) {
        await (ble as TestBleService).forceConnect();
        if (mounted) _showSnackBar('테스트 기기에 연결되었습니다.');
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                DeviceSelectionScreen(
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
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2))
    );
  }

  // --- Command Wrappers ---

  void _sendSpeedChange(int newSpeed) {
    if (!connected) return;
    int targetSpeed = newSpeed.clamp(0, 5);

    final data = {
      'action': 'speed_change',
      'speed': targetSpeed,
      'timestamp': DateTime.now().toIso8601String(),
    };
    ble.sendJson(data);
  }

  void _sendModeChange(bool isAiMode) {
    if (!connected) return;

    final data = {
      'action': 'mode_change',
      'mode': isAiMode ? 'ai' : 'manual',
      'timestamp': DateTime.now().toIso8601String(),
    };
    ble.sendJson(data);
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      // 1. Dashboard
      DashboardScreen(
        connected: connected,
        onConnect: handleConnect,
        speed: speed,
        setSpeed: (v) {
          setState(() => speed = v.toInt());
          _sendSpeedChange(v.toInt());
        },
        trackingOn: trackingOn,
        setTrackingOn: (v) {
          setState(() => trackingOn = v);
          _sendModeChange(v);
        },
        openAnalytics: () => setState(() => _index = 2),
        deviceName: deviceName,
        // UserService에서 선택된 유저 정보 가져오기
        selectedUserName: userService.getSelectedUsersText(),
        selectedUserImagePath: userService.getSelectedUserImage(),
      ),

      // 2. Control
      ControlScreen(
        connected: connected,
        deviceName: deviceName,
        onConnect: handleConnect,
        // ControlScreen 내에서 UserService를 직접 쓰므로 파라미터 대폭 축소
      ),

      // 3. Analytics
      ValueListenableBuilder<DashboardAnalytics>(
        valueListenable: analyticsService.dashboardNotifier,
        builder: (context, data, _) {
          return AnalyticsScreen(
            analyticsData: data, // DashboardAnalytics 타입
            isLoading: false, // 필요 시 로딩 상태 관리 추가
            onPeriodChanged: (period) {
              analyticsService.requestAllStats(period);
            },
          );
        },
      ),

      // 4. Settings
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
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          // 상단에 부드러운 곡선 추가
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(Icons.dashboard_rounded, 'Dashboard', 0),
            _buildNavItem(Icons.gamepad_rounded, 'Control', 1),
            _buildNavItem(Icons.bar_chart_rounded, 'Analytics', 2),
            _buildNavItem(Icons.settings_rounded, 'Settings', 3),
          ],
        ),
      ),
    );
  }

  // ✨ [수정] Nav Item Builder
  Widget _buildNavItem(IconData icon, String label, int index) {
    final isSelected = _index == index;
    // Green Theme Colors
    final color = isSelected ? const Color(0xFF4CAF50) : const Color(0xFF9E9E9E);
    final bgColor = isSelected ? const Color(0xFFE8F5E9) : Colors.transparent; // 연한 초록 배경

    return GestureDetector(
      onTap: () => setState(() => _index = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontFamily: 'Sen',
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}