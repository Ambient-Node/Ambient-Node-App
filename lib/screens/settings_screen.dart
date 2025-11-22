import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class SettingsScreen extends StatefulWidget {
  final bool connected;
  final Function(Map<String, dynamic>) sendJson;

  const SettingsScreen({
    super.key,
    required this.connected,
    required this.sendJson,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _soundEnabled = false;

  // ✨ Nature Theme Colors
  static const Color _bgColor = Color(0xFFF1F8E9);
  static const Color _primaryGreen = Color(0xFF4CAF50);
  static const Color _textDark = Color(0xFF2D3142);
  static const Color _textGrey = Color(0xFF9095A5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        title: const Text("Settings", style: TextStyle(fontFamily: 'Sen', fontWeight: FontWeight.w700, color: _textDark)),
        backgroundColor: _bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _textDark), onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        children: [
          _buildSectionHeader("Device Info"),
          _buildInfoCard(icon: Icons.router_outlined, title: "Model Name", value: "Ambient Node Eco", iconColor: _primaryGreen),
          const SizedBox(height: 12),
          _buildInfoCard(icon: Icons.dns_outlined, title: "Firmware Version", value: "v2.1.0 (Green)", iconColor: Colors.orange),

          const SizedBox(height: 32),

          _buildSectionHeader("Preferences"),
          Container(
            decoration: _boxDecoration(),
            child: Column(
              children: [
                _buildSwitchTile(
                  icon: Icons.notifications_none_rounded,
                  title: "Notifications",
                  value: _notificationsEnabled,
                  onChanged: (v) => setState(() => _notificationsEnabled = v),
                ),
                const Divider(height: 1, indent: 56, endIndent: 20),
                _buildSwitchTile(
                  icon: Icons.volume_up_outlined,
                  title: "Sound Effects",
                  value: _soundEnabled,
                  onChanged: (v) => setState(() => _soundEnabled = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          _buildSectionHeader("System"),
          Container(
            decoration: _boxDecoration(),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFF3B30).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.power_settings_new_rounded, color: Color(0xFFFF3B30)),
              ),
              title: const Text("Remote Shutdown", style: TextStyle(fontFamily: 'Sen', fontSize: 16, fontWeight: FontWeight.w600, color: _textDark)),
              subtitle: const Text("Safely turn off the device", style: TextStyle(fontFamily: 'Sen', fontSize: 12, color: _textGrey)),
              trailing: const Icon(Icons.chevron_right_rounded, color: _textGrey),
              onTap: () => _showShutdownDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helpers (Same logic, different colors) ---

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 12),
      child: Text(title.toUpperCase(), style: const TextStyle(fontFamily: 'Sen', fontSize: 12, fontWeight: FontWeight.w700, color: _textGrey, letterSpacing: 1.2)),
    );
  }

  Widget _buildInfoCard({required IconData icon, required String title, required String value, required Color iconColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: _boxDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontFamily: 'Sen', fontSize: 12, color: _textGrey, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontFamily: 'Sen', fontSize: 16, color: _textDark, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({required IconData icon, required String title, required bool value, required ValueChanged<bool> onChanged}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: _textDark.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: _textDark, size: 22),
      ),
      title: Text(title, style: const TextStyle(fontFamily: 'Sen', fontSize: 16, fontWeight: FontWeight.w600, color: _textDark)),
      trailing: CupertinoSwitch(value: value, activeColor: _primaryGreen, onChanged: onChanged),
    );
  }

  BoxDecoration _boxDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
    );
  }

  void _showShutdownDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text("Shutdown Device", style: TextStyle(fontFamily: 'Sen', fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to turn off the device?", style: TextStyle(fontFamily: 'Sen', fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel", style: TextStyle(color: _textGrey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF3B30), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              Navigator.pop(ctx);
              if (!widget.connected) return;
              widget.sendJson({"action": "shutdown", "timestamp": DateTime.now().toIso8601String()});
            },
            child: const Text("Shutdown", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}