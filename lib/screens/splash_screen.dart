import 'dart:math' as math;
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const SplashScreen({super.key, required this.onFinish});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // 전체 애니메이션 시간
    )..repeat(); // 배경용 반복

    // 3.5초 후 종료 트리거
    Future.delayed(const Duration(milliseconds: 3500), widget.onFinish);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Dynamic Aurora Background
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: _AuroraPainter(animationValue: _controller.value),
                size: Size.infinite,
              );
            },
          ),

          // 2. Content (Logo & Text)
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with "Breathing" and "Glass" effect
                _buildGlassLogo(),
                const SizedBox(height: 40),
                // Staggered Text Animation
                _buildAnimatedText(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassLogo() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(
            opacity: value.clamp(0.0, 1.0),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.3),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3A91FF).withOpacity(0.3 * value),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
                border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
              ),
              child: Center(
                child: Icon(
                  Icons.cyclone_rounded, // 더 멋진 아이콘
                  size: 60,
                  color: const Color(0xFF3A91FF).withOpacity(0.9),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAnimatedText() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 20.0, end: 0.0),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (context, translateY, child) {
        double opacity = (1.0 - (translateY / 20.0)).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, translateY),
          child: Opacity(
            opacity: opacity,
            child: Column(
              children: [
                const Text(
                  "AMBIENT NODE",
                  style: TextStyle(
                    fontFamily: 'Sen',
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2024),
                    letterSpacing: 2.0, // 자간 넓게
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 30, height: 1, color: const Color(0xFF3A91FF)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        "INTELLIGENT COOLING",
                        style: TextStyle(
                          fontFamily: 'Sen',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF838699),
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    Container(width: 30, height: 1, color: const Color(0xFF3A91FF)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ✨ 고급스러운 오로라 배경 그리기
class _AuroraPainter extends CustomPainter {
  final double animationValue;
  _AuroraPainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // 부드러운 그라데이션 원 1 (Blue)
    final center1 = Offset(
      size.width * 0.5 + math.cos(animationValue * 2 * math.pi) * 50,
      size.height * 0.4 + math.sin(animationValue * 2 * math.pi) * 50,
    );
    paint.shader = RadialGradient(
      colors: [const Color(0xFF3A91FF).withOpacity(0.15), Colors.transparent],
    ).createShader(Rect.fromCircle(center: center1, radius: size.width * 0.8));
    canvas.drawCircle(center1, size.width * 0.8, paint);

    // 부드러운 그라데이션 원 2 (Cyan)
    final center2 = Offset(
      size.width * 0.5 + math.sin(animationValue * 2 * math.pi) * 50,
      size.height * 0.6 + math.cos(animationValue * 2 * math.pi) * 50,
    );
    paint.shader = RadialGradient(
      colors: [const Color(0xFF4CD964).withOpacity(0.1), Colors.transparent],
    ).createShader(Rect.fromCircle(center: center2, radius: size.width * 0.7));
    canvas.drawCircle(center2, size.width * 0.7, paint);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => true;
}