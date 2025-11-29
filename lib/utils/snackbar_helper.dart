import 'package:flutter/material.dart';

enum AppSnackType { info, error, success, connected }

void showAppSnackBar(BuildContext context, String message, {AppSnackType type = AppSnackType.info}) {
  ScaffoldMessenger.of(context).clearSnackBars();

  if (type == AppSnackType.connected) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),
    );
    return;
  }

  final isError = type == AppSnackType.error;
  final bg = isError ? const Color(0xFFFF5252) : const Color(0xFF2D3142);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(fontFamily: 'Sen', color: Colors.white, fontWeight: FontWeight.bold)),
      backgroundColor: bg,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    ),
  );
}
