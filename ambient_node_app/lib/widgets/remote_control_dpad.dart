import 'package:flutter/material.dart';
import 'dart:math' as math;

/// 뉴모피즘 스타일의 원형 방향키 위젯입니다.
/// 각 방향과 중앙 버튼에 대한 콜백 함수를 전달할 수 있습니다.
class RemoteControlDpad extends StatelessWidget {
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onCenter;
  final double size;

  const RemoteControlDpad({
    super.key,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.onCenter,
    this.size = 250.0,
  });

  @override
  Widget build(BuildContext context) {
    // 뉴모피즘 스타일에 사용할 색상들
    const primaryColor = Color(0xFFE0E5EC); // 기본 컨테이너 색
    const darkShadowColor = Color(0xFFA3B1C6); // 어두운 그림자
    const lightShadowColor = Colors.white; // 밝은 그림자
    final iconColor = Colors.grey.shade600; // 아이콘 색상

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. 가장 바깥쪽 베이스 (살짝 들어간 효과)
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor,
                boxShadow: [
                  BoxShadow(
                    color: darkShadowColor.withOpacity(0.5),
                    offset: const Offset(5, 5),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                  const BoxShadow(
                    color: lightShadowColor,
                    offset: Offset(-5, -5),
                    blurRadius: 15,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            // 2. 안쪽 링 (방향키가 위치할 영역)
            Container(
              width: size * 0.9,
              height: size * 0.9,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    lightShadowColor,
                    primaryColor,
                  ],
                ),
              ),
            ),
            // 3. 중앙 버튼 베이스 (가장 튀어나온 부분)
            Container(
              width: size * 0.6,
              height: size * 0.6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor,
                boxShadow: [
                  BoxShadow(
                    color: darkShadowColor.withOpacity(0.7),
                    offset: const Offset(4, 4),
                    blurRadius: 10,
                  ),
                  const BoxShadow(
                    color: lightShadowColor,
                    offset: Offset(-4, -4),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            // 4. 중앙 버튼 터치 영역
            GestureDetector(
              onTap: onCenter,
              child: Container(
                width: size * 0.55,
                height: size * 0.55,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryColor,
                      lightShadowColor,
                    ],
                    stops: [0.8, 1.0],
                  ),
                ),
              ),
            ),

            // 5. 방향키 버튼들
            _DirectionalButton(
                alignment: Alignment.topCenter,
                icon: Icons.play_arrow,
                rotation: -math.pi / 2,
                onTap: onUp,
                iconColor: iconColor),
            _DirectionalButton(
                alignment: Alignment.bottomCenter,
                icon: Icons.play_arrow,
                rotation: math.pi / 2,
                onTap: onDown,
                iconColor: iconColor),
            _DirectionalButton(
                alignment: Alignment.centerLeft,
                icon: Icons.play_arrow,
                rotation: math.pi,
                onTap: onLeft,
                iconColor: iconColor),
            _DirectionalButton(
                alignment: Alignment.centerRight,
                icon: Icons.play_arrow,
                rotation: 0,
                onTap: onRight,
                iconColor: iconColor),
          ],
        ),
      ),
    );
  }
}

/// 방향키 버튼을 위한 내부 헬퍼 위젯
class _DirectionalButton extends StatelessWidget {
  final Alignment alignment;
  final IconData icon;
  final double rotation;
  final VoidCallback? onTap;
  final Color iconColor;

  const _DirectionalButton({
    required this.alignment,
    required this.icon,
    required this.rotation,
    this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: 60,
        height: 60,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            splashColor: Colors.grey.withOpacity(0.2),
            borderRadius: BorderRadius.circular(30),
            onTap: onTap,
            child: Center(
              child: Transform.rotate(
                angle: rotation,
                child: Icon(icon, color: iconColor, size: 30),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
