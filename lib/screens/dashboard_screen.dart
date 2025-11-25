import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/fan_dashboard_widget.dart';

class DashboardScreen extends StatelessWidget {
  final bool connected;
  final VoidCallback onConnect;

  final int speed;
  final Function(int) setSpeed;

  // ★ [수정] trackingOn, setTrackingOn 삭제 -> currentMode, onModeChange 추가
  final String currentMode;
  final Function(String) onModeChange;

  final Function(int) onTimerSet;
  final Function(String, int) onManualControl;
  final VoidCallback openAnalytics;

  final String deviceName;
  final String? selectedUserName;
  final String? selectedUserImagePath;

  const DashboardScreen({
    super.key,
    required this.connected,
    required this.onConnect,
    required this.speed,
    required this.setSpeed,
    // ★ [수정] 생성자 파라미터 변경
    required this.currentMode,
    required this.onModeChange,

    required this.onTimerSet,
    required this.onManualControl,
    required this.openAnalytics,
    this.deviceName = 'Ambient',
    this.selectedUserName,
    this.selectedUserImagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: FanDashboardWidget(
                connected: connected,
                deviceName: deviceName,
                selectedUserName: selectedUserName,
                selectedUserImagePath: selectedUserImagePath,
                onConnect: onConnect,
                speed: speed,
                setSpeed: (double value) {
                  setSpeed(value.round());
                },
                // ★ [수정] 하위 위젯으로 전달
                currentMode: currentMode,
                onModeChange: onModeChange,
                onTimerSet: onTimerSet,
                onManualControl: onManualControl,
                openAnalytics: openAnalytics,
              ),
            ),
          ],
        ),
      ),
    );
  }
}