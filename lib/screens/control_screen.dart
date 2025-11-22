import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ambient_node/models/user_profile.dart';
import 'package:ambient_node/services/user_service.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';
import 'package:ambient_node/widgets/remote_control_dpad.dart'; // 새로 바뀐 Dpad import
import 'package:ambient_node/screens/user_registration_screen.dart';

class ControlScreen extends StatefulWidget {
  final bool connected;
  final String deviceName;
  final VoidCallback onConnect;
  final Function(Map<String, dynamic>)? onUserDataSend;

  const ControlScreen({
    super.key,
    required this.connected,
    required this.deviceName,
    required this.onConnect,
    this.onUserDataSend,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final UserService _userService = UserService();

  // Green Nature Theme Colors
  static const Color _bgWhite = Colors.white;
  static const Color _bgLight = Color(0xFFF1F8E9); // Very Light Green
  static const Color _primaryGreen = Color(0xFF4CAF50);
  static const Color _textDark = Color(0xFF2D3142);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgWhite,
      body: SafeArea(
        child: ValueListenableBuilder<List<UserProfile>>(
          valueListenable: _userService.usersNotifier,
          builder: (context, users, _) {
            return Column(
              children: [
                // 1. App Top Bar (Nature Theme)
                AppTopBar(
                  deviceName: widget.deviceName,
                  subtitle: _userService.getSelectedUsersText(),
                  connected: widget.connected,
                  onConnectToggle: widget.onConnect,
                  userImagePath: _userService.getSelectedUserImage(),
                ),

                const SizedBox(height: 20),

                // 2. Header: "Target Users" + Action Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Target Users",
                        style: TextStyle(
                          fontFamily: 'Sen',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                        ),
                      ),
                      // Actions Row
                      Row(
                        children: [
                          // Delete All (새 기능)
                          if (users.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.delete_sweep_outlined, color: Colors.grey),
                              tooltip: "Delete All",
                              onPressed: () => _confirmDeleteAll(),
                            ),
                          // Clear Selection
                          if (_userService.selectedUserIndices.isNotEmpty)
                            TextButton(
                              onPressed: () => setState(() => _userService.clearSelection()),
                              child: const Text("Clear", style: TextStyle(color: Colors.orange)),
                            ),
                        ],
                      )
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 3. User List (Horizontal)
                SizedBox(
                  height: 130,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
                    scrollDirection: Axis.horizontal,
                    itemCount: users.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(width: 16),
                    itemBuilder: (context, index) {
                      if (index == 0) return _AddUserCard(onTap: _onAddUser);

                      final userIndex = index - 1;
                      final user = users[userIndex];
                      final isSelected = _userService.selectedUserIndices.contains(userIndex);
                      final order = isSelected
                          ? _userService.selectedUserIndices.indexOf(userIndex) + 1
                          : null;

                      return _UserCard(
                        user: user,
                        isSelected: isSelected,
                        selectionOrder: order,
                        onTap: () => setState(() => _userService.toggleUserSelection(userIndex)),
                        onEdit: () => _onEditUser(userIndex, users),
                      );
                    },
                  ),
                ),

                const Spacer(),

                // 4. Remote Control Section
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 30, bottom: 50),
                  decoration: const BoxDecoration(
                    color: _bgLight,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        "DIRECTION CONTROL",
                        style: TextStyle(
                          fontFamily: 'Sen',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // D-Pad Widget
                      RemoteControlDpad(
                        size: 260,
                        onUp: () => _sendCommand('up'),
                        onDown: () => _sendCommand('down'),
                        onLeft: () => _sendCommand('left'),
                        onRight: () => _sendCommand('right'),
                        onCenter: () => _sendCommand('center'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- Handlers ---

  Future<void> _confirmDeleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete All Users?"),
        content: const Text("This will remove all registered profiles permanently."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _userService.deleteAllUsers();
      setState(() {});
    }
  }

  Future<void> _onAddUser() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const UserRegistrationScreen()),
    );

    if (result != null && result['action'] == 'register') {
      await _userService.registerUser(result['name'], result['imagePath']);
      setState(() {});
    }
  }

  Future<void> _onEditUser(int index, List<UserProfile> users) async {
    final user = users[index];
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => UserRegistrationScreen(
          existingName: user.name,
          existingImagePath: user.imagePath,
          isEditMode: true,
        ),
      ),
    );

    if (result != null) {
      if (result['action'] == 'register') {
        await _userService.updateUser(index, result['name'], result['imagePath']);
      } else if (result['action'] == 'delete') {
        await _userService.deleteUser(index);
      }
      setState(() {});
    }
  }

  void _sendCommand(String direction) {
    if (!widget.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Device not connected"), duration: Duration(seconds: 1)),
      );
      return;
    }
    if (widget.onUserDataSend != null) {
      widget.onUserDataSend!.call({
        'action': 'angle_change',
        'direction': direction,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }
}

// --- Helper Widgets ---

class _AddUserCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddUserCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade300, width: 1.5, style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF5F5F5)),
              child: const Icon(Icons.add, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text("New", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserProfile user;
  final bool isSelected;
  final int? selectionOrder;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _UserCard({
    required this.user,
    required this.isSelected,
    this.selectionOrder,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onEdit,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? const Color(0xFF4CAF50) : Colors.transparent,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? const Color(0xFF4CAF50).withOpacity(0.2) : Colors.grey.withOpacity(0.1),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade100, width: 2),
                  ),
                  child: ClipOval(
                    child: user.imagePath != null
                        ? Image.file(File(user.imagePath!), fit: BoxFit.cover)
                        : const Icon(Icons.person, color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Sen',
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? const Color(0xFF4CAF50) : Colors.black87,
                  ),
                ),
              ],
            ),
            if (isSelected && selectionOrder != null)
              Positioned(
                top: 8, right: 8,
                child: Container(
                  width: 20, height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0xFF4CAF50), shape: BoxShape.circle),
                  child: Text('$selectionOrder', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}