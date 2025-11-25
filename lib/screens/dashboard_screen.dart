import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/fan_dashboard_widget.dart';
import 'package:ambient_node/screens/timer_setting_screen.dart';

class DashboardScreen extends StatelessWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed;
  final Function(int) setSpeed;
  final bool trackingOn;
  final Function(bool) setTrackingOn;
  final VoidCallback openAnalytics;
  final VoidCallback onRemoteTap; // ★ 리모컨 화면 이동 콜백 추가
  final String deviceName;
  final String? selectedUserName;
  final String? selectedUserImagePath;

  const DashboardScreen({
    super.key,
    required this.connected,
    required this.onConnect,
    required this.speed,
    required this.setSpeed,
    required this.trackingOn,
    required this.setTrackingOn,
    required this.openAnalytics,
    required this.onRemoteTap, // ★ 필수
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
                trackingOn: trackingOn,
                setTrackingOn: setTrackingOn,
                openAnalytics: openAnalytics,
                onRemoteTap: onRemoteTap, // ★ 전달
              ),
            ),
          ],
        ),
      ),
    );
  }
}