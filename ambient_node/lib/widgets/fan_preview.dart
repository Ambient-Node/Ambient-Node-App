/*
      선풍기가 돌아가는 애니메이션 부분 위젯
*/

import 'dart:math' as math;
import 'package:flutter/material.dart';

class FanPreview extends StatefulWidget {
  final bool powerOn;
  final int speed; // 0~100

  const FanPreview({
    super.key,
    required this.powerOn,
    required this.speed,
  });

  @override
  State<FanPreview> createState() => _FanPreviewState();
}

class _FanPreviewState extends State<FanPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);

    _updateAnimation();
  }

  @override
  void didUpdateWidget(FanPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.powerOn != oldWidget.powerOn ||
        widget.speed != oldWidget.speed) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.powerOn && widget.speed > 0) {
      final speedFactor = widget.speed.clamp(0, 100) / 100;
      // ChatGPT 코드의 회전 속도 로직 적용: 더 빠른 회전
      final durationMs = (2500 - 2000 * speedFactor).toInt();
      _controller.duration = Duration(milliseconds: durationMs);
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildFanBlade(double angle, Color color) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        width: 24, // ChatGPT 코드와 동일한 크기
        height: 100, // ChatGPT 코드와 동일한 크기
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.9),
              color.withValues(alpha: 0.2),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.powerOn ? Colors.blueAccent : Colors.grey.shade400;

    return Container(
      width: 200, // ChatGPT 코드와 동일한 크기
      height: 200, // ChatGPT 코드와 동일한 크기
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.4),
            color.withValues(alpha: 0.05),
          ],
          stops: const [0.6, 1.0], // ChatGPT 코드와 동일한 그라데이션
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Transform.rotate(
            angle: _controller.value * 2 * math.pi,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _buildFanBlade(0, color),
                _buildFanBlade(2 * math.pi / 3, color),
                _buildFanBlade(4 * math.pi / 3, color),
                // 중앙 원 (ChatGPT 코드와 동일한 크기)
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: color, // ChatGPT 코드와 동일한 단순한 색상
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
