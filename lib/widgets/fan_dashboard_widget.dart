import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';

class FanDashboardWidget extends StatefulWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed; // ★ 0~5 단계 (절대 0~100 아님)
  final Function(double) setSpeed; // 호환성을 위해 double로 유지하되, 내부값은 0.0~5.0
  final bool trackingOn;
  final Function(bool) setTrackingOn;
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
    required this.openAnalytics,
    this.deviceName = 'Ambient',
    this.selectedUserName,
    this.selectedUserImagePath,
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

    if (widget.connected) _updateRotation();
  }

  @override
  void didUpdateWidget(FanDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected != oldWidget.connected ||
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
    // [수정] 0~5 기준으로 회전 속도 계산
    if (widget.connected && widget.speed > 0) {
      // speed 1: 2000ms, speed 5: 400ms (숫자가 클수록 빠름)
      final durationMs = 2400 ~/ widget.speed;
      _controller.duration = Duration(milliseconds: durationMs);
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
    // [수정] speed는 이미 0~5 범위이므로 100 클램핑 제거
    final currentSpeed = widget.speed;

    final color = (widget.connected && currentSpeed > 0)
        ? _fanBlue
        : Colors.grey.shade400;

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Sen'),
      child: Column(
        children: [
          AppTopBar(
            deviceName: widget.connected ? widget.deviceName : "Ambient",
            subtitle: widget.selectedUserName != null
                ? '${widget.selectedUserName} 선택 중'
                : "Lab Fan",
            connected: widget.connected,
            onConnectToggle: widget.onConnect,
            userImagePath: widget.selectedUserImagePath,
          ),
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
                        // 팬 애니메이션 영역
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
                                  color: const Color(0xFFE5E9F0), width: 6),
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

                        // [수정] 컨트롤 버튼 영역
                        Builder(builder: (context) {
                          final controlColor =
                          widget.connected && currentSpeed > 0
                              ? _fanBlue
                              : const Color(0xFF838799);

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // (-) 버튼: 1 감소
                              _roundControlButton(
                                icon: Icons.remove,
                                onTap: widget.connected
                                    ? () => widget.setSpeed(
                                    ((currentSpeed - 1).clamp(0, 5))
                                        .toDouble())
                                    : () {},
                                color: widget.connected
                                    ? controlColor
                                    : Colors.grey.shade300,
                                iconSize: 20,
                              ),

                              // 숫자 표시: 변환 없이 그대로 표시 (0~5)
                              Text(
                                '$currentSpeed',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                  color: controlColor,
                                ),
                              ),

                              // (+) 버튼: 1 증가
                              _roundControlButton(
                                icon: Icons.add,
                                onTap: widget.connected
                                    ? () => widget.setSpeed(
                                    ((currentSpeed + 1).clamp(0, 5))
                                        .toDouble())
                                    : () {},
                                color: widget.connected
                                    ? controlColor
                                    : Colors.grey.shade300,
                                iconSize: 20,
                              ),
                            ],
                          );
                        }),
                        const SizedBox(height: 8),
                        const Text(
                          "Speed Level (0-5)",
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