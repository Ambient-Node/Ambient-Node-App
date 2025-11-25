import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/fan_dashboard_widget.dart';

class DashboardScreen extends StatelessWidget {
  final bool connected;
  final VoidCallback onConnect;

  final int speed;
  final Function(int) setSpeed;

  // ★ [수정] 상태 분리
  final String movementMode; // 'manual', 'rotation', 'ai_tracking'
  final bool isNaturalWind;  // true/false
  final Function(String) onMovementModeChange;
  final Function(bool) onNaturalWindChange;

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
    required this.movementMode,
    required this.isNaturalWind,
    required this.onMovementModeChange,
    required this.onNaturalWindChange,
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
                // 분리된 상태 전달
                movementMode: movementMode,
                isNaturalWind: isNaturalWind,
                onMovementModeChange: onMovementModeChange,
                onNaturalWindChange: onNaturalWindChange,
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