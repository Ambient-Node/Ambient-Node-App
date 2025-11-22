import 'package:flutter/material.dart';

class RemoteControlDpad extends StatelessWidget {
  final double size;
  final VoidCallback onUp, onDown, onLeft, onRight, onCenter;

  const RemoteControlDpad({
    super.key,
    this.size = 240,
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
    required this.onCenter,
  });

  @override
  Widget build(BuildContext context) {
    // Nature Theme Colors
    final bgGradientStart = Colors.white;
    final bgGradientEnd = const Color(0xFFF1F8E9); // Very Light Green
    final iconColor = const Color(0xFF558B2F); // Darker Green

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgGradientStart, bgGradientEnd],
        ),
        boxShadow: [
          // Soft Shadow
          BoxShadow(
            color: const Color(0xFF33691E).withOpacity(0.15),
            offset: const Offset(10, 10),
            blurRadius: 30,
          ),
          // Highlight
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-10, -10),
            blurRadius: 20,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Inner Circle Guide
          Container(
            width: size * 0.35,
            height: size * 0.35,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withOpacity(0.5), width: 1),
              gradient: RadialGradient(
                colors: [Colors.grey.shade100, Colors.white.withOpacity(0)],
              ),
            ),
          ),

          Positioned(top: 15, child: _ArrowBtn(Icons.keyboard_arrow_up_rounded, onUp, iconColor)),
          Positioned(bottom: 15, child: _ArrowBtn(Icons.keyboard_arrow_down_rounded, onDown, iconColor)),
          Positioned(left: 15, child: _ArrowBtn(Icons.keyboard_arrow_left_rounded, onLeft, iconColor)),
          Positioned(right: 15, child: _ArrowBtn(Icons.keyboard_arrow_right_rounded, onRight, iconColor)),

          // Center Stop Button
          GestureDetector(
            onTap: onCenter,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF1F8E9),
                boxShadow: [
                  BoxShadow(color: Colors.grey.shade300, blurRadius: 10, offset: const Offset(4, 4)),
                  const BoxShadow(color: Colors.white, blurRadius: 10, offset: Offset(-4, -4)),
                ],
              ),
              child: const Icon(Icons.stop_rounded, color: Color(0xFFE53935), size: 32),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _ArrowBtn(this.icon, this.onTap, this.color);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        width: 60, height: 60,
        alignment: Alignment.center,
        child: Icon(icon, size: 38, color: color),
      ),
    );
  }
}