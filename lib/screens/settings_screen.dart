import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  final bool connected;
  final Function(Map<String, dynamic>) sendJson;

  const SettingsScreen({
    super.key,
    required this.connected,
    required this.sendJson,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8), // 배경색 살짝 회색으로 (선택사항)
      appBar: AppBar(
        title: const Text("설정"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "시스템 관리",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 재부팅 카드
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.restart_alt, color: Colors.orange),
              ),
              title: const Text("기기 재부팅"),
              subtitle: const Text("라즈베리파이를 재시작합니다."),
              onTap: () => _showRebootDialog(context),
            ),
          ),

          const SizedBox(height: 12),

          // 종료 카드
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.power_settings_new, color: Colors.red),
              ),
              title: const Text("기기 강제 종료"),
              subtitle: const Text("라즈베리파이 전원을 끕니다."),
              onTap: () => _showShutdownDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  // 재부팅 다이얼로그
  void _showRebootDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("시스템 재부팅"),
        content: const Text("라즈베리파이를 재시작하시겠습니까?\n연결이 일시적으로 끊어집니다."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _sendCommand(context, "reboot", "재부팅 명령을 전송했습니다.");
            },
            child: const Text("재시작", style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
  }

  // 종료 다이얼로그
  void _showShutdownDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("시스템 종료"),
        content: const Text("라즈베리파이를 완전히 종료하시겠습니까?\n다시 켜려면 전원을 재연결해야 합니다."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _sendCommand(context, "shutdown", "종료 명령을 전송했습니다.");
            },
            child: const Text("종료", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 명령 전송 공통 함수
  void _sendCommand(BuildContext context, String action, String message) {
    if (!connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("BLE 연결이 필요합니다."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    sendJson({
      "action": action, // 'reboot' 또는 'shutdown'
      "timestamp": DateTime.now().toIso8601String(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}