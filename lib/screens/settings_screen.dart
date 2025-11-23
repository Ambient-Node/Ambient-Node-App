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
      appBar: AppBar(
        title: const Text("설정"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "시스템 관리",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          Card(
            child: ListTile(
              leading: const Icon(Icons.power_settings_new, color: Colors.red),
              title: const Text("기기 강제 종료"),
              subtitle: const Text("라즈베리파이를 안전하게 종료합니다."),
              onTap: () => _showShutdownDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showShutdownDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("기기 강제 종료"),
        content: const Text("라즈베리파이를 종료하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);

              if (!connected) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("BLE 연결이 필요합니다."),
                  ),
                );
                return;
              }

              // BLE로 shutdown 명령 전송
              sendJson({
                "action": "shutdown",
                "timestamp": DateTime.now().toIso8601String(),
              });

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("기기 종료 명령을 전송했습니다.")),
              );
            },
            child: const Text("종료"),
          ),
        ],
      ),
    );
  }
}
