import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';

class FanDashboardWidget extends StatefulWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed;
  final Function(double) setSpeed;
  final bool trackingOn;
  final Function(bool) setTrackingOn;

  // 추가된 기능
  final bool isNaturalWind;
  final Function(bool) setNaturalWind;
  final bool isOscillating; // 회전 모드 여부
  final Function(bool) setOscillating;

  final VoidCallback openAnalytics;
  final String deviceName;
  final String? selectedUserName;
  final String? selectedUserImagePath;

  const FanDashboardWidget({
    super.key,
    required this.connected,
    required this.onConnect,
    required this.speed,
    required this.setSpeed,
    required this.trackingOn,
    required this.setTrackingOn,
    required this.isNaturalWind,
    required this.setNaturalWind,
    required this.isOscillating,
    required this.setOscillating,
    required this.openAnalytics,
    this.deviceName = 'Ambient',
    this.selectedUserName,
    this.selectedUserImagePath,
  });

  @override
  State<FanDashboardWidget> createState() => _FanDashboardWidgetState();
}

class _FanDashboardWidgetState extends State<FanDashboardWidget>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController; // 날개 회전
  late final AnimationController _oscillationController; // 좌우 회전 (회전모드)

  // Colors (Nature Theme)
  static const Color _primaryGreen = Color(0xFF4CAF50); // 자연스러운 그린
  static const Color _darkGreen = Color(0xFF2E7D32);
  static const Color _accent = Color(0xFF2D3142);

  @override
  void initState() {
    super.initState();
    // 1. 날개 회전 컨트롤러
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    // 2. 좌우 회전(Oscillation) 컨트롤러
    _oscillationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6), // 6초에 한 번 왕복
    );

    _updateState();
  }

  @override
  void didUpdateWidget(FanDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected != oldWidget.connected ||
        widget.speed != oldWidget.speed ||
        widget.isOscillating != oldWidget.isOscillating) {
      _updateState();
    }
  }

  void _updateState() {
    // 날개 회전 로직
    if (widget.connected && widget.speed > 0) {
      final durationMs = 2000 - ((widget.speed - 1) * 350);
      _rotationController.duration =
          Duration(milliseconds: durationMs.clamp(200, 2000));
      if (!_rotationController.isAnimating) _rotationController.repeat();
    } else {
      _rotationController.stop();
    }

    // 좌우 회전(Oscillation) 로직
    if (widget.connected && widget.speed > 0 && widget.isOscillating) {
      if (!_oscillationController.isAnimating) _oscillationController.repeat(
          reverse: true);
    } else {
      _oscillationController.stop();
      _oscillationController.animateTo(
          0.5, duration: const Duration(milliseconds: 500)); // 중앙 정렬
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _oscillationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppTopBar(
          deviceName: widget.connected ? widget.deviceName : "Ambient",
          subtitle: widget.selectedUserName != null
              ? '${widget.selectedUserName} Active'
              : (widget.isNaturalWind ? "Natural Breeze" : "Manual Cooling"),
          connected: widget.connected,
          onConnectToggle: widget.onConnect,
          userImagePath: widget.selectedUserImagePath,
        ),

        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // ✨ Fan Visual (Oscillating)
                _buildFanVisual(),

                const SizedBox(height: 50),

                // ✨ Control Panel (Slider + Toggles)
                _buildControlPanel(),

                const SizedBox(height: 30),

                // ✨ Stats
                Row(
                  children: [
                    Expanded(child: _buildStatCard(
                        "Runtime", "3.5", "hr", Icons.timer_outlined, onTap: widget.openAnalytics,)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStatCard(
                        "Energy", "12", "W", Icons.bolt_rounded)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // =================================================================
  // 1. Fan Visual (Rotation + Oscillation)
  // =================================================================
  Widget _buildFanVisual() {
    final isActive = widget.connected && widget.speed > 0;
    final glowOpacity = (widget.speed / 5.0).clamp(0.0, 1.0) * 0.4;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Background Glow
        if (isActive)
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _primaryGreen.withOpacity(glowOpacity),
                  blurRadius: 60,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),

        // ✨ Oscillation Transform (좌우 회전)
        // 좌우로 -15도 ~ +15도 움직임
        AnimatedBuilder(
          animation: _oscillationController,
          builder: (context, child) {
            // 0.0 ~ 1.0 -> -0.25 ~ 0.25 라디안 (약 -15 ~ 15도)
            final angle = (_oscillationController.value - 0.5) * 0.5;
            return Transform.rotate(
              angle: angle,
              alignment: Alignment.bottomCenter, // 아래쪽을 축으로 회전
              child: child,
            );
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer Ring
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF7F9FC),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                    const BoxShadow(
                      color: Colors.white,
                      blurRadius: 20,
                      offset: Offset(-10, -10),
                    ),
                  ],
                ),
              ),
              // Blades
              AnimatedBuilder(
                animation: _rotationController,
                builder: (_, __) {
                  return Transform.rotate(
                    angle: _rotationController.value * 2 * math.pi,
                    child: CustomPaint(
                      size: const Size(220, 220),
                      painter: _TurbineBladePainter(
                        color: isActive ? _primaryGreen : Colors.grey.shade300,
                      ),
                    ),
                  );
                },
              ),
              // Center Cap
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Colors.white, Color(0xFFDEE4EA)],
                    stops: [0.2, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    widget.isNaturalWind ? Icons.spa : Icons.air,
                    color: isActive ? _primaryGreen : Colors.grey.shade400,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =================================================================
  // 2. Control Panel (Slider & Toggles)
  // =================================================================
  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _primaryGreen.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Speed Label
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "WIND SPEED",
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade400,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.speed == 0 ? "Off" : "Level ${widget.speed}",
                    style: const TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                ],
              ),
              // Power Toggle (Simulated by speed)
              Switch(
                value: widget.speed > 0,
                activeColor: _primaryGreen,
                onChanged: widget.connected ? (val) {
                  widget.setSpeed(val ? 1.0 : 0.0);
                } : null,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ✨ Slider Control
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _primaryGreen,
              inactiveTrackColor: Colors.grey.shade200,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 12, elevation: 4),
              overlayColor: _primaryGreen.withOpacity(0.1),
              trackHeight: 6,
            ),
            child: Slider(
              value: widget.speed.toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              onChanged: widget.connected
                  ? (val) => widget.setSpeed(val)
                  : null,
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Off", style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text("Max", style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // ✨ Function Buttons (Natural, Rotation, AI)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _FunctionButton(
                icon: Icons.grass_rounded,
                label: "Natural",
                isActive: widget.isNaturalWind,
                onTap: () => widget.setNaturalWind(!widget.isNaturalWind),
                enabled: widget.connected && widget.speed > 0,
              ),
              _FunctionButton(
                icon: Icons.sync_alt_rounded,
                // 회전 아이콘
                label: "Rotation",
                isActive: widget.isOscillating,
                onTap: () => widget.setOscillating(!widget.isOscillating),
                enabled: widget.connected && widget.speed > 0,
              ),
              _FunctionButton(
                icon: Icons.auto_awesome,
                label: "AI Track",
                isActive: widget.trackingOn,
                onTap: () => widget.setTrackingOn(!widget.trackingOn),
                enabled: widget.connected,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, String unit, IconData icon,
      {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap, // 클릭 이벤트 연결
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF0F2F5)),
          boxShadow: onTap != null ? [ // 클릭 가능한 카드(Runtime)에만 약한 그림자 추가로 힌트 제공
            BoxShadow(
              color: Colors.green.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 20, color: Colors.grey.shade400),
                if (onTap != null) // 클릭 가능 표시 아이콘 (선택사항)
                  Icon(Icons.arrow_forward_ios_rounded, size: 12,
                      color: Colors.grey.shade300),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'Sen',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Sen',
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ✨ 기능 버튼 위젯
class _FunctionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final bool enabled;

  const _FunctionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? const Color(0xFF4CAF50) : Colors.grey.shade400;
    final bgColor = isActive ? const Color(0xFF4CAF50).withOpacity(0.1) : const Color(0xFFF5F7FA);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.5,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? const Color(0xFF4CAF50).withOpacity(0.3) : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Icon(icon, color: isActive ? const Color(0xFF4CAF50) : Colors.grey.shade600, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Sen',
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? const Color(0xFF2E7D32) : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ✨ Turbine Blade Painter (Green Color)
class _TurbineBladePainter extends CustomPainter {
  final Color color;
  _TurbineBladePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const int bladeCount = 7;
    for (int i = 0; i < bladeCount; i++) {
      canvas.save();
      final angle = (i * 2 * math.pi) / bladeCount;
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      final path = Path();
      path.moveTo(0, 0);
      path.quadraticBezierTo(10, -radius * 0.3, 0, -radius * 0.9);
      path.quadraticBezierTo(25, -radius * 1.0, 40, -radius * 0.5);
      path.quadraticBezierTo(15, -radius * 0.2, 0, 0);

      paint.shader = LinearGradient(
        colors: [color, color.withOpacity(0.6)],
        begin: Alignment.topCenter,
        end: Alignment.bottomRight,
      ).createShader(path.getBounds());

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _TurbineBladePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}