import 'dart:math' as math;
import 'dart:ui'; // BackdropFilter용
import 'package:flutter/material.dart';

class FanDashboardWidget extends StatefulWidget {
  final bool connected;
  final int speed;
  final Function(double) setSpeed;

  final bool isNatural;
  final Function(bool) setNatural;
  final bool isSwing;
  final Function(bool) setSwing;
  final bool isSleep;
  final Function(bool) setSleep;

  final VoidCallback onRemoteTap;

  const FanDashboardWidget({
    super.key,
    required this.connected,
    required this.speed,
    required this.setSpeed,
    required this.isNatural,
    required this.setNatural,
    required this.isSwing,
    required this.setSwing,
    required this.isSleep,
    required this.setSleep,
    required this.onRemoteTap,
  });

  @override
  State<FanDashboardWidget> createState() => _FanDashboardWidgetState();
}

class _FanDashboardWidgetState extends State<FanDashboardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const Color _bladeColor = Color(0xFF26C6DA); // Cyan Blades
  static const Color _activeBlue = Color(0xFF00B0FF);
  static const Color _ringBorderColor = Color(0xFFB2EBF2);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2));
    if (widget.connected && widget.speed > 0) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant FanDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected && widget.speed > 0) {
      final duration = 2000 - (widget.speed * 300);
      _controller.duration = Duration(milliseconds: duration.clamp(200, 2000).toInt());
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isModeActive = widget.isNatural || widget.isSleep;

    return Column(
      children: [
        // 1. Fan Visual Area
        Expanded(
          flex: 5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Temperature Tag (Top)
              Positioned(
                top: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5), // 반투명
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.8)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.thermostat, size: 14, color: Colors.black54),
                      SizedBox(width: 4),
                      Text("24°C", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Sen')),
                    ],
                  ),
                ),
              ),

              // ✨ Circular Fan Housing
              SizedBox(
                width: 280,
                height: 280,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        border: Border.all(color: _ringBorderColor, width: 3),
                      ),
                    ),

                    ClipOval(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                      ),
                    ),

                    // Deco Dots (Top, Bottom, Left, Right)
                    ...List.generate(4, (index) {
                      final angle = (index * 90) * (math.pi / 180);
                      return Transform.translate(
                        offset: Offset(125 * math.cos(angle - math.pi/2), 125 * math.sin(angle - math.pi/2)), // 위쪽부터 시작
                        child: Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            color: _bladeColor.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),

                    // ✨ 3-Blade Fan (Animated)
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (_, __) => Transform.rotate(
                        angle: _controller.value * 2 * math.pi,
                        child: CustomPaint(
                          size: const Size(200, 200),
                          painter: _ThreeBladeFanPainter(color: _bladeColor.withOpacity(0.9)),
                        ),
                      ),
                    ),

                    // Center Hub Gradient Overlay (Depth)
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [_bladeColor.withOpacity(0.4), _bladeColor.withOpacity(0.0)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Speed / Mode Text
              Positioned(
                bottom: 20,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    widget.speed > 0
                        ? (widget.isNatural ? "자연풍" : (widget.isSleep ? "수면풍" : "풍속 ${widget.speed}"))
                        : "정지",
                    key: ValueKey<String>("${widget.speed}${widget.isNatural}${widget.isSleep}"),
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w300,
                      color: Colors.black87,
                      fontFamily: 'Sen',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 2. Lower Area: Control Panel
        Expanded(
          flex: 4,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(30),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              boxShadow: [
                BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -5)),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Slider
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 8,
                      activeTrackColor: isModeActive ? Colors.grey[400] : _bladeColor.withOpacity(0.3),
                      inactiveTrackColor: Colors.grey[300],
                      thumbColor: isModeActive ? Colors.grey : _bladeColor,
                      overlayColor: _bladeColor.withOpacity(0.1),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12, elevation: 2),
                    ),
                    child: Slider(
                      value: widget.speed.toDouble(),
                      min: 0,
                      max: 5,
                      divisions: 5,
                      onChanged: (isModeActive || !widget.connected) ? null : (v) => widget.setSpeed(v),
                    ),
                  ),
                ),

                // Grid Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _ControlBtn(
                        icon: widget.isNatural ? Icons.eco : Icons.bolt,
                        label: "MODE",
                        isActive: widget.isNatural,
                        onTap: () {
                          // 자연풍 토글 (자연풍 켜면 수면풍 끔)
                          if(widget.isNatural) {
                            widget.setNatural(false);
                          } else {
                            widget.setNatural(true);
                            widget.setSleep(false);
                          }
                        }
                    ),
                    _ControlBtn(
                        icon: Icons.cached,
                        label: "SWING",
                        isActive: widget.isSwing,
                        onTap: () => widget.setSwing(!widget.isSwing)
                    ),
                    _ControlBtn(
                        icon: Icons.nightlight_round,
                        label: "SLEEP",
                        isActive: widget.isSleep,
                        onTap: () {
                          // 수면풍 토글 (수면풍 켜면 자연풍 끔)
                          if(widget.isSleep) {
                            widget.setSleep(false);
                          } else {
                            widget.setSleep(true);
                            widget.setNatural(false);
                          }
                        }
                    ),
                    _ControlBtn(
                        icon: Icons.smartphone,
                        label: "REMOTE",
                        isActive: false,
                        onTap: widget.onRemoteTap
                    ),
                  ],
                ),

                // Power Button
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () {
                      if(widget.connected) widget.setSpeed(0);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _activeBlue,
                      elevation: 5,
                      shadowColor: _activeBlue.withOpacity(0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.power_settings_new, color: Colors.white),
                        SizedBox(width: 8),
                        Text("Power Off", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, fontFamily: 'Sen')),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 버튼 위젯 - 모드, 회전, 수면풍 등 ...
class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ControlBtn({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 60, height: 60,
            decoration: BoxDecoration(
                color: isActive ? const Color(0xFFE1F5FE) : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: isActive ? const Color(0xFF00B0FF) : Colors.transparent, width: 1.5),
                boxShadow: [
                  if (!isActive)
                    BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 5, offset: const Offset(0, 2))
                ]
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF00B0FF) : Colors.grey,
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600, fontFamily: 'Sen')),
        ],
      ),
    );
  }
}

// 3엽 날개 페인터 (기존과 동일)
class _ThreeBladeFanPainter extends CustomPainter {
  final Color color;
  _ThreeBladeFanPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..color = color;

    for (int i = 0; i < 3; i++) {
      canvas.save();
      final angle = (i * 120) * (math.pi / 180);
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      final path = Path();
      path.moveTo(0, 0);
      path.cubicTo(radius * 0.6, -radius * 0.4, radius * 0.9, -radius * 0.1, radius * 0.8, radius * 0.4);
      path.cubicTo(radius * 0.5, radius * 0.7, 0, radius * 0.2, 0, 0);

      canvas.drawPath(path, paint);
      canvas.restore();
    }
    canvas.drawCircle(center, radius * 0.15, Paint()..color = color.withOpacity(0.5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}