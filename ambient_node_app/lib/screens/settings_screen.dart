import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final Function(bool)? onEnergySaverChanged;
  final bool energySaver;
  final String deviceName;

  const SettingsScreen({
    super.key,
    this.onEnergySaverChanged,
    this.energySaver = false,
    this.deviceName = "Ambient Node",
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool energySaver;
  late TextEditingController nameController;

  @override
  void initState() {
    super.initState();
    energySaver = widget.energySaver;
    nameController = TextEditingController(text: widget.deviceName);
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Sen'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _mockShutdownDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.power_settings_new, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              '시스템 종료',
              style: TextStyle(fontFamily: 'Sen'),
            ),
          ],
        ),
        content: const Text(
          '시스템이 안전하게 종료됩니다.\n\n진행하시겠습니까?',
          style: TextStyle(fontSize: 15, fontFamily: 'Sen'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '취소',
              style: TextStyle(fontFamily: 'Sen'),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnackBar('시스템이 안전하게 종료되었습니다.');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              '종료',
              style: TextStyle(fontFamily: 'Sen'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastSync = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '설정',
          style: TextStyle(fontFamily: 'Sen'),
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 🧭 시스템 관리
          const Text(
            '시스템 관리',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 8),

          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync, color: Colors.blue),
                  title: const Text(
                    '센서 재보정',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                  subtitle: const Text(
                    '팬 각도나 얼굴 인식이 어긋날 때 재보정합니다.',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                  onTap: () => _showSnackBar('센서 재보정이 완료되었습니다.'),
                ),
                SwitchListTile(
                  value: energySaver,
                  onChanged: (v) {
                    setState(() => energySaver = v);
                    widget.onEnergySaverChanged?.call(v);
                    _showSnackBar(
                      v ? '전력 절약 모드가 활성화되었습니다.' : '전력 절약 모드가 해제되었습니다.',
                    );
                  },
                  secondary:
                      const Icon(Icons.battery_saver, color: Colors.green),
                  title: const Text(
                    '전력 절약 모드',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                  subtitle: const Text(
                    '절전 모드 활성화 시 배터리 수명 향상',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.power_settings_new, color: Colors.red),
                  title: const Text(
                    '시스템 종료',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                  subtitle: const Text(
                    '시스템이 안전하게 종료됩니다.',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                  onTap: _mockShutdownDialog,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 🪪 시스템 정보
          const Text(
            '시스템 정보',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 8),

          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline, color: Colors.grey),
                  title: const Text(
                    '앱 버전',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                  trailing: const Text(
                    'v1.0.0',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.memory, color: Colors.grey),
                  title: const Text(
                    '펌웨어 버전',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                  trailing: const Text(
                    'Raspberry Pi BLE Agent 0.2',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.update, color: Colors.grey),
                  title: const Text(
                    '마지막 동기화',
                    style: TextStyle(fontFamily: 'Sen'),
                  ),
                  trailing: Text(
                    '${lastSync.hour.toString().padLeft(2, '0')}:${lastSync.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 14, fontFamily: 'Sen'),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.devices_other, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          style: const TextStyle(fontFamily: 'Sen'),
                          decoration: const InputDecoration(
                            labelText: '디바이스 이름 변경',
                            labelStyle: TextStyle(fontFamily: 'Sen'),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          _showSnackBar('디바이스 이름이 변경되었습니다.');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          '저장',
                          style: TextStyle(fontFamily: 'Sen'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
