import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ambient_node/widgets/fan_dashboard_widget.dart';

class DashboardScreen extends StatefulWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed;
  final Function(int) setSpeed;
  final bool trackingOn;
  final Function(bool) setTrackingOn;
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
    required this.trackingOn,
    required this.setTrackingOn,
    required this.openAnalytics,
    this.deviceName = 'Ambient',
    this.selectedUserName,
    this.selectedUserImagePath,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // 추가된 상태 변수 (화면 내부에서 관리하거나 상위에서 받아와야 함)
  // 실제 앱에서는 MainShell에서 관리하는 것이 좋지만, UI 시연을 위해 여기서 선언
  bool _isNaturalWind = false;
  bool _isOscillating = false; // 회전 모드

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    final bool isActive = widget.connected && widget.speed > 0;
    // 그린 테마 적용
    final Color primaryColor = const Color(0xFF4CAF50); // Fresh Green

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 1. Dynamic Nature Background

          // Top-Right Orb (Primary Green)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeInOutCubic,
            top: isActive ? -100 : -200,
            right: isActive ? -50 : -150,
            child: _AnimatedGlowOrb(
              color: primaryColor,
              size: 450,
              opacity: isActive ? 0.15 : 0.05,
            ),
          ),

          // Bottom-Left Orb (Teal/Forest Accent)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeInOutCubic,
            bottom: isActive ? -100 : -300,
            left: isActive ? -50 : -150,
            child: _AnimatedGlowOrb(
              color: const Color(0xFF009688), // Teal
              size: 400,
              opacity: isActive ? 0.12 : 0.0,
            ),
          ),

          // 2. Glassmorphism Blur Layer
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Container(color: Colors.transparent),
            ),
          ),

          // 3. Main Content
          SafeArea(
            child: FanDashboardWidget(
              connected: widget.connected,
              deviceName: widget.deviceName,
              selectedUserName: widget.selectedUserName,
              selectedUserImagePath: widget.selectedUserImagePath,
              onConnect: widget.onConnect,
              speed: widget.speed,
              setSpeed: (double value) => widget.setSpeed(value.round()),
              trackingOn: widget.trackingOn,
              setTrackingOn: widget.setTrackingOn,
              openAnalytics: widget.openAnalytics,
              // 추가된 기능 전달
              isNaturalWind: _isNaturalWind,
              setNaturalWind: (v) => setState(() => _isNaturalWind = v),
              isOscillating: _isOscillating,
              setOscillating: (v) => setState(() => _isOscillating = v),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedGlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _AnimatedGlowOrb({
    required this.color,
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeInOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(opacity),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(opacity),
            blurRadius: 100,
            spreadRadius: 20,
          ),
        ],
      ),
    );
  }
}