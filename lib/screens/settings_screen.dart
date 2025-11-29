import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart'; // iOS 스타일 다이얼로그 등을 위해
import '../utils/snackbar_helper.dart';

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
      backgroundColor: const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
          children: [
            // 커스텀 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Row(
                children: [
                  const Text(
                    "설정",
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF2D3142),
                    ),
                  ),
                  const Spacer(),
                  // 연결 상태 뱃지
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: connected ? const Color(0xFFE3F2FD) : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: connected ? const Color(0xFF90CAF9) : const Color(0xFFFFCDD2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: connected ? const Color(0xFF2196F3) : const Color(0xFFF44336),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          connected ? "Connected" : "Disconnected",
                          style: TextStyle(
                            fontFamily: 'Sen',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: connected ? const Color(0xFF1976D2) : const Color(0xFFD32F2F),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                children: [
                  _buildSectionHeader("시스템 제어"),
                  const SizedBox(height: 12),

                  // 재부팅 타일
                  _buildSettingsTile(
                    context: context,
                    icon: Icons.restart_alt_rounded,
                    iconColor: Colors.orange,
                    title: "시스템 재부팅",
                    subtitle: "라즈베리파이를 재시작합니다",
                    onTap: () => _showActionDialog(
                      context,
                      title: "재부팅",
                      content: "시스템을 재시작하시겠습니까?\n연결이 잠시 끊어집니다.",
                      actionName: "재시작",
                      actionColor: Colors.orange,
                      onConfirm: () => _sendCommand(context, "reboot", "재부팅 명령 전송됨"),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 종료 타일
                  _buildSettingsTile(
                    context: context,
                    icon: Icons.power_settings_new_rounded,
                    iconColor: Colors.red,
                    title: "시스템 종료",
                    subtitle: "전원을 완전히 끕니다",
                    isDestructive: true,
                    onTap: () => _showActionDialog(
                      context,
                      title: "시스템 종료",
                      content: "정말 종료하시겠습니까?\n다시 켜려면 전원을 재연결해야 합니다.",
                      actionName: "종료",
                      actionColor: Colors.red,
                      onConfirm: () => _sendCommand(context, "shutdown", "종료 명령 전송됨"),
                    ),
                  ),

                  const SizedBox(height: 32),
                  _buildSectionHeader("앱 정보"),
                  const SizedBox(height: 12),

                  _buildInfoTile("버전", "1.0.0 (Build 24)"),
                  const SizedBox(height: 12),
                  _buildInfoTile("개발자", "Ambient Node Team"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Sen',
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Sen',
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDestructive ? Colors.red : const Color(0xFF2D3142),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Sen',
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey[300],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Sen',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D3142),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Sen',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  void _showActionDialog(
      BuildContext context, {
        required String title,
        required String content,
        required String actionName,
        required Color actionColor,
        required VoidCallback onConfirm,
      }) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소", style: TextStyle(color: Colors.grey)),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: Text(actionName, style: TextStyle(color: actionColor)),
          ),
        ],
      ),
    );
  }

  void _sendCommand(BuildContext context, String action, String message) {
    if (!connected) {
      showAppSnackBar(context, "기기와 연결되어 있지 않습니다.", type: AppSnackType.error);
      return;
    }

    sendJson({
      "action": action,
      "timestamp": DateTime.now().toIso8601String(),
    });

    showAppSnackBar(context, message, type: AppSnackType.info);
  }
}