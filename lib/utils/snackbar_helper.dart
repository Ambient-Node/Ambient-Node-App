import 'package:flutter/material.dart';

class AppSnackBar {
  static void show(BuildContext context, String message, {bool isError = false, bool isSuccess = false}) {
    // 이미 떠있는 스낵바가 있으면 제거
    ScaffoldMessenger.of(context).clearSnackBars();

    // 색상 결정 (에러: 빨강, 성공: 초록/파랑, 기본: 다크네이비)
    Color bgColor = const Color(0xFF2D3142); // 기본
    if (isError) bgColor = const Color(0xFFFF5252);
    if (isSuccess) bgColor = const Color(0xFF6366F1); // 브랜드 컬러 (연결 성공 등)

    // 아이콘 결정
    IconData icon = Icons.info_outline_rounded;
    if (isError) icon = Icons.error_outline_rounded;
    if (isSuccess) icon = Icons.check_circle_outline_rounded;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Sen',
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating, // 떠있는 스타일
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), // 둥근 모서리
        ),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20), // 여백
        duration: const Duration(seconds: 2),
      ),
    );
  }
}