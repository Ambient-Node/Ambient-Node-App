// lib/widgets/remote_control_dpad.dart
import 'package:flutter/material.dart';

// UI 색상 정의
class RemoteColors {
  static const kColorSlate200 = Color(0xFFE2E8F0);
  static const kColorSlate500 = Color(0xFF64748B);
  static const kColorBgLight = Color(0xFFF8FAFC);
  static const kColorCyan = Color(0xFF00BCD4);
  static const kColorBlue = Color(0xFF3B82F6);
}

class RemoteControlDpad extends StatelessWidget {
  final double size;
  final VoidCallback onUp;
  final VoidCallback onUpEnd;
  final VoidCallback onDown;
  final VoidCallback onDownEnd;
  final VoidCallback onLeft;
  final VoidCallback onLeftEnd;
  final VoidCallback onRight;
  final VoidCallback onRightEnd;
  final VoidCallback onCenter;
  final VoidCallback onCenterEnd;

  const RemoteControlDpad({
    super.key,
    required this.size,
    required this.onUp,
    required this.onUpEnd,
    required this.onDown,
    required this.onDownEnd,
    required this.onLeft,
    required this.onLeftEnd,
    required this.onRight,
    required this.onRightEnd,
    required this.onCenter,
    required this.onCenterEnd,
  });

  @override
  Widget build(BuildContext context) {

    final double innerCircleSize = size * 0.55;
    final double dpadButtonSize = 56.0; // 60 -> 56
    final double centerButtonSize = 72.0; // 80 -> 72
    final double edgeOffset = 5.0; // 20 -> 5 (버튼을 더 바깥으로)

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: RemoteColors.kColorSlate200.withOpacity(0.6),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
          const BoxShadow(
            color: Colors.white,
            blurRadius: 20,
            spreadRadius: -5,
          )
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 외곽 데코레이션 라인
          Container(
            width: size - 20,
            height: size - 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: RemoteColors.kColorSlate200.withOpacity(0.3),
              ),
            ),
          ),
          // 내부 배경 원
          Container(
            width: innerCircleSize,
            height: innerCircleSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: RemoteColors.kColorBgLight,
            ),
          ),

          // 상단 버튼 (위치를 더 위로 올림)
          Positioned(
            top: edgeOffset,
            child: _buildGestureButton(
              onTapDown: onUp,
              onTapUp: onUpEnd,
              icon: Icons.keyboard_arrow_up,
              size: dpadButtonSize,
            ),
          ),
          // 하단 버튼 (위치를 더 아래로 내림)
          Positioned(
            bottom: edgeOffset,
            child: _buildGestureButton(
              onTapDown: onDown,
              onTapUp: onDownEnd,
              icon: Icons.keyboard_arrow_down,
              size: dpadButtonSize,
            ),
          ),
          // 좌측 버튼 (위치를 더 왼쪽으로)
          Positioned(
            left: edgeOffset,
            child: _buildGestureButton(
              onTapDown: onLeft,
              onTapUp: onLeftEnd,
              icon: Icons.keyboard_arrow_left,
              size: dpadButtonSize,
            ),
          ),
          // 우측 버튼 (위치를 더 오른쪽으로)
          Positioned(
            right: edgeOffset,
            child: _buildGestureButton(
              onTapDown: onRight,
              onTapUp: onRightEnd,
              icon: Icons.keyboard_arrow_right,
              size: dpadButtonSize,
            ),
          ),

          // 중앙 버튼 (크기를 줄여서 주변 버튼과 간격 확보)
          GestureDetector(
            onTapDown: (_) => onCenter(),
            onTapUp: (_) => onCenterEnd(),
            onTapCancel: () => onCenterEnd(),
            child: Container(
              width: centerButtonSize,
              height: centerButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [RemoteColors.kColorCyan, RemoteColors.kColorBlue],
                ),
                boxShadow: [
                  BoxShadow(
                    color: RemoteColors.kColorCyan.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.settings_backup_restore,
                color: Colors.white,
                size: 30, // 아이콘 크기도 살짝 조정
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGestureButton({
    required VoidCallback onTapDown,
    required VoidCallback onTapUp,
    required IconData icon,
    required double size,
  }) {
    return GestureDetector(
      onTapDown: (_) => onTapDown(),
      onTapUp: (_) => onTapUp(),
      onTapCancel: () => onTapUp(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: RemoteColors.kColorSlate200.withOpacity(0.8),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: RemoteColors.kColorSlate500,
          size: 28,
        ),
      ),
    );
  }
}