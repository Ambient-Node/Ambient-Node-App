import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';

class FanDashboardWidget extends StatefulWidget {
  final bool connected;
  final VoidCallback onConnect;
  final bool powerOn;
  final Function(bool) setPowerOn;
  final int speed; // 0~100
  final Function(double) setSpeed; // keep existing API (double)
  final bool trackingOn;
  final Function(bool) setTrackingOn;
  final VoidCallback openAnalytics;
  final String deviceName; // optional BT name
  final String? selectedUserName;

  const FanDashboardWidget({
    super.key,
    required this.connected,
    required this.onConnect,
    required this.powerOn,
    required this.setPowerOn,
    required this.speed,
    required this.setSpeed,
    required this.trackingOn,
    required this.setTrackingOn,
    required this.openAnalytics,
    this.deviceName = 'Ambient',
    this.selectedUserName,
  });

  @override
  State<FanDashboardWidget> createState() => _FanDashboardWidgetState();
}

class _FanDashboardWidgetState extends State<FanDashboardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const Color _fanBlue = Color(0xFF3A91FF);

  Widget _wrapMaxWidth(Widget child) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    if (widget.powerOn) _updateRotation();
  }

  @override
  void didUpdateWidget(FanDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.powerOn != oldWidget.powerOn ||
        widget.speed != oldWidget.speed) {
      _updateRotation();
    }
  }

  Widget _roundControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    double iconSize = 15,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 4),
        ),
        child: Icon(icon, size: iconSize, color: color),
      ),
    );
  }

  void _updateRotation() {
    if (widget.powerOn && widget.speed > 0) {
      final duration =
          Duration(milliseconds: (2500 ~/ ((widget.speed / 20).clamp(1, 5))));
      _controller.duration = duration;
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  Widget _buildFanBlades(Color color) {
    Widget blade(double angle) {
      return Transform.rotate(
        angle: angle,
        child: Container(
          width: 24,
          height: 110,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withOpacity(0.9),
                color.withOpacity(0.2),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Transform.rotate(
          angle: _controller.value * 2 * math.pi,
          child: Stack(
            alignment: Alignment.center,
            children: [
              blade(0),
              blade(2 * math.pi / 3),
              blade(4 * math.pi / 3),
              // center hub
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      color.withOpacity(0.9),
                      color.withOpacity(0.3),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              // reflective highlight
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final safeSpeed = widget.speed.clamp(0, 100);
    final color = widget.powerOn ? _fanBlue : Colors.grey.shade400;

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Sen'),
      child: Column(
        children: [
          // 상단바는 패딩 없이 표시
          AppTopBar(
            deviceName: widget.connected ? widget.deviceName : "Ambient",
            subtitle: widget.selectedUserName != null
                ? '${widget.selectedUserName} 선택 중'
                : "Lab Fan",
            connected: widget.powerOn,
            onConnectToggle: () {
              // 스위치를 토글하면 전원을 켜고 끔
              widget.setPowerOn(!widget.powerOn);
            },
          ),
          // 나머지 컨텐츠는 스크롤 가능
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                children: [
                  _wrapMaxWidth(Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 32, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE0E3E7)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 240,
                            height: 240,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFF6F8FB),
                              gradient: const RadialGradient(
                                colors: [Color(0xFFFFFFFF), Color(0xFFF0F3F8)],
                                radius: 0.95,
                              ),
                              border: Border.all(
                                  color: Color(0xFFE5E9F0), width: 6),
                              boxShadow: [
                                BoxShadow(
                                  color: color.withOpacity(0.3),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: Center(child: _buildFanBlades(color)),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Builder(builder: (context) {
                          const Color controlColor = Color(0xFF838799);
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _roundControlButton(
                                icon: Icons.remove,
                                onTap: () => widget.setSpeed(
                                    ((safeSpeed - 20).clamp(0, 100))
                                        .toDouble()),
                                color: controlColor,
                                iconSize: 20,
                              ),
                              Text(
                                '${(safeSpeed / 20).round()}',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                  color: controlColor,
                                ),
                              ),
                              _roundControlButton(
                                icon: Icons.add,
                                onTap: () => widget.setSpeed(
                                    ((safeSpeed + 20).clamp(0, 100))
                                        .toDouble()),
                                color: controlColor,
                                iconSize: 20,
                              ),
                            ],
                          );
                        }),
                        const SizedBox(height: 8),
                        const Text(
                          "Speed Level",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 24),
                  _wrapMaxWidth(Container(
                    width: double.infinity,
                    child: Row(
                      children: [
                        Expanded(child: _infoCard("오늘 사용", "3.5h")),
                        const SizedBox(width: 16),
                        Expanded(child: _infoCard("연속 가동", "1.1h")),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String label, String value) {
    return Container(
      height: 115,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: Color(0xFF32343E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF838699),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// removed painter (replaced by gradient rectangular blades)
