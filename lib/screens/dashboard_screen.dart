import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/fan_dashboard_widget.dart';

class DashboardScreen extends StatefulWidget {
  final bool connected;
  final String deviceName;
  final int speed;
  final Function(int) setSpeed;

  final bool isNatural;
  final Function(bool) setNatural;
  final bool isSwing;
  final Function(bool) setSwing;

  final VoidCallback onConnectTap;
  final VoidCallback onNavigateToControl;
  final VoidCallback onNavigateToAnalytics;
  final VoidCallback onNavigateToSettings;

  const DashboardScreen({
    super.key,
    required this.connected,
    required this.deviceName,
    required this.speed,
    required this.setSpeed,
    required this.isNatural,
    required this.setNatural,
    required this.isSwing,
    required this.setSwing,
    required this.onConnectTap,
    required this.onNavigateToControl,
    required this.onNavigateToAnalytics,
    required this.onNavigateToSettings,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // 수면풍 상태 (UI 로직용, 실제로는 상위에서 받아오거나 내부 관리)
  bool isSleep = false;

  // 모드에 따른 배경 그라데이션 색상 결정
  List<Color> _getBackgroundColors() {
    if (!widget.connected || widget.speed == 0) {
      // Power Off: Grey Gradient
      return [const Color(0xFFECEFF1), const Color(0xFFFFFFFF)];
    }

    if (widget.isNatural) {
      // 자연풍: Fresh Green (숲 느낌)
      return [const Color(0xFFE8F5E9), const Color(0xFFFFFFFF)];
    }

    if (isSleep) {
      // 수면풍: Soft Indigo (밤 느낌)
      return [const Color(0xFFE8EAF6), const Color(0xFFFFFFFF)];
    }

    // 일반풍: Cool Cyan (시원한 느낌 - 기본)
    return [const Color(0xFFE0F7FA), const Color(0xFFFFFFFF)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      // App Bar
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Text("AMBIENT", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w400, fontSize: 16, fontFamily: 'Sen')),
            const SizedBox(width: 4),
            const Text("NODE", style: TextStyle(color: Color(0xFF00BCD4), fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Sen')),
          ],
        ),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.black87, size: 28),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildDrawer(context),

      // Body with Animated Gradient
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 1000), // 부드러운 색상 전환
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: _getBackgroundColors(),
          ),
        ),
        child: SafeArea(
          child: FanDashboardWidget(
            connected: widget.connected,
            speed: widget.speed,
            setSpeed: (val) => widget.setSpeed(val.toInt()),
            isNatural: widget.isNatural,
            setNatural: widget.setNatural,
            isSwing: widget.isSwing,
            setSwing: widget.setSwing,
            isSleep: isSleep,
            setSleep: (v) => setState(() => isSleep = v), // 수면풍 제어 추가
            onRemoteTap: widget.onNavigateToControl,
          ),
        ),
      ),
    );
  }

  // Drawer (기존 코드 유지)
  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 30, 16, 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Menu", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Sen')),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(backgroundColor: Colors.grey[100]),
                  ),
                ],
              ),
            ),
            _drawerItem(Icons.bluetooth, "기기 연결", onTap: widget.onConnectTap),
            _drawerItem(Icons.person_outline, "사용자 관리", onTap: widget.onNavigateToControl),
            _drawerItem(Icons.smartphone, "리모컨", onTap: widget.onNavigateToControl),
            _drawerItem(Icons.bar_chart, "사용 분석", onTap: widget.onNavigateToAnalytics),
            _drawerItem(Icons.settings_outlined, "설정", onTap: widget.onNavigateToSettings),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, {required VoidCallback onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
      leading: Icon(icon, color: Colors.black54, size: 24),
      title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87, fontFamily: 'Sen')),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }
}