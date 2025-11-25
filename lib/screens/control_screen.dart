import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ambient_node/widgets/app_top_bar.dart';
import 'package:ambient_node/screens/user_registration_screen.dart';
import 'package:ambient_node/utils/image_helper.dart';
import 'package:ambient_node/services/analytics_service.dart';

class ControlScreen extends StatefulWidget {
  final bool connected;
  final String deviceName;
  final VoidCallback onConnect;
  final String? selectedUserName;

  // ✅ [수정 1] 콜백 함수 타입 변경: (String? id, String? name, String? imagePath)
  // 기존: final Function(String?, String?) onUserSelectionChanged;
  final Function(String?, String?, String?) onUserSelectionChanged;

  final Function(Map<String, dynamic>)? onUserDataSend;
  final Stream<Map<String, dynamic>>? dataStream;

  const ControlScreen({
    super.key,
    required this.connected,
    required this.deviceName,
    required this.onConnect,
    this.selectedUserName,
    required this.onUserSelectionChanged,
    this.onUserDataSend,
    this.dataStream,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  List<UserProfile> users = [];
  int? selectedUserIndex;
  List<int> selectedUserIndices = [];
  StreamSubscription? _dataSubscription;

  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color textMain = Color(0xFF1E293B);
  static const Color textSub = Color(0xFF64748B);

  static const Color colorUser1 = Color(0xFF6366F1);
  static const Color colorUser2 = Color(0xFF14B8A6);

  @override
  void initState() {
    super.initState();
    _loadUsers();

    _dataSubscription = widget.dataStream?.listen((data) {
      if (!mounted) return;
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  List<Map<String, dynamic>> _getSelectedUsersList() {
    return selectedUserIndices.map((idx) {
      final user = users[idx];
      return {
        'user_id': user.userId,
        'username': user.name,
        'role': selectedUserIndices.indexOf(idx) + 1,
      };
    }).toList();
  }

  Future<void> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getStringList('users') ?? [];

    final loadedUsers = usersJson.map((userStr) {
      final userMap = jsonDecode(userStr);
      final user = UserProfile.fromJson(userMap);
      if (user.userId == null) {
        return UserProfile(
          name: user.name,
          avatarUrl: user.avatarUrl,
          imagePath: user.imagePath,
          userId: 'user_${user.name.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}',
        );
      }
      return user;
    }).toList();

    setState(() {
      users = loadedUsers;
    });
  }

  Future<void> _saveUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = users.map((user) => jsonEncode(user.toJson())).toList();
    await prefs.setStringList('users', usersJson);
  }

  Future<void> _addUser() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const UserRegistrationScreen()),
    );
    if (result != null && result['action'] == 'register') {
      final generatedUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';
      final newUser = UserProfile(
          name: result['name']!,
          imagePath: result['imagePath'],
          userId: generatedUserId);
      setState(() => users.add(newUser));
      await _saveUsers();

      if (widget.connected && widget.onUserDataSend != null) {
        final base64Image = await ImageHelper.encodeImageToBase64(result['imagePath']);
        widget.onUserDataSend!.call({
          'action': 'user_register',
          'user_id': generatedUserId,
          'username': result['name']!,
          'image_base64': base64Image,
          'timestamp': DateTime.now().toIso8601String(),
          'selected_users': _getSelectedUsersList(),
        });
      }
    }
  }

  Future<void> _editUser(int index) async {
    final user = users[index];
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => UserRegistrationScreen(
            existingName: user.name,
            existingImagePath: user.imagePath,
            isEditMode: true),
      ),
    );

    if (result != null) {
      if (result['action'] == 'register') {
        final existingUser = users[index];
        final updatedUser = UserProfile(
            name: result['name']!,
            imagePath: result['imagePath'],
            userId: existingUser.userId,
            avatarUrl: existingUser.avatarUrl);
        setState(() {
          users[index] = updatedUser;
          if (selectedUserIndices.contains(index)) _sendUserSelectionToBLE();
        });
        await _saveUsers();

        if (widget.connected && widget.onUserDataSend != null) {
          final base64Image = await ImageHelper.encodeImageToBase64(result['imagePath']);
          widget.onUserDataSend!.call({
            'action': 'user_update',
            'user_id': updatedUser.userId,
            'username': result['name']!,
            'image_base64': base64Image,
            'timestamp': DateTime.now().toIso8601String(),
            'selected_users': _getSelectedUsersList(),
          });
        }
      } else if (result['action'] == 'delete') {
        final userToDelete = users[index];
        if (widget.connected && widget.onUserDataSend != null) {
          widget.onUserDataSend!.call({
            'action': 'user_delete',
            'user_id': userToDelete.userId,
            'timestamp': DateTime.now().toIso8601String(),
            'selected_users': _getSelectedUsersList(),
          });
        }
        _deleteUser(index);
      }
    }
  }

  Future<void> _deleteUser(int index) async {
    setState(() {
      if (selectedUserIndices.contains(index)) selectedUserIndices.remove(index);
      users.removeAt(index);
      selectedUserIndices = selectedUserIndices
          .map((idx) => idx > index ? idx - 1 : idx)
          .where((idx) => idx >= 0 && idx < users.length)
          .toList();

      _updateMainSelectionState();
    });
    await _saveUsers();
    _sendUserSelectionToBLE();
  }

  void _selectUser(int index) {
    setState(() {
      final isSelected = selectedUserIndices.contains(index);
      if (isSelected) {
        selectedUserIndices.remove(index);
        selectedUserIndices.sort();
      } else {
        if (selectedUserIndices.length >= 2) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Row(
                    children: const [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '최대 2명까지만 선택 가능합니다',
                          style: TextStyle(fontFamily: 'Sen', fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFFFF5252),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  duration: const Duration(seconds: 2)
              )
          );
          return;
        }
        selectedUserIndices.add(index);
        selectedUserIndices.sort();
      }
      _updateMainSelectionState();
    });
    _sendUserSelectionToBLE();
  }

  // ✅ [수정 2] 선택 상태 업데이트 시 user_id도 함께 전달하도록 수정
  void _updateMainSelectionState() {
    selectedUserIndex = selectedUserIndices.isNotEmpty ? selectedUserIndices[0] : null;
    if (selectedUserIndices.isNotEmpty) {
      final firstUser = users[selectedUserIndices[0]];
      // user_id, name, imagePath 순서로 전달
      widget.onUserSelectionChanged(firstUser.userId, firstUser.name, firstUser.imagePath);
    } else {
      // 선택된 유저가 없을 경우 모두 null 전달
      widget.onUserSelectionChanged(null, null, null);
    }
  }

  void _clearAllSelections() {
    setState(() {
      selectedUserIndices.clear();
      _updateMainSelectionState();
    });
    _sendUserSelectionToBLE();
  }

  void _sendUserSelectionToBLE() {
    if (!widget.connected) return;
    List<Map<String, dynamic>> selectedUsers = [];
    if(selectedUserIndices.isNotEmpty) selectedUsers = _getSelectedUsersList();

    if (widget.onUserDataSend != null) {
      widget.onUserDataSend!.call({
        'action': 'user_select',
        'user_list': selectedUsers,
        'timestamp': DateTime.now().toIso8601String(),
        // 'selected_users' 필드는 프로토콜에 따라 중복이면 제거 가능
      });

      if (selectedUsers.isEmpty) {
        // [수정] 유저가 없으면 Manual로 변경 (type: motor 추가)
        widget.onUserDataSend!.call({
          'action': 'mode_change',
          'type': 'motor', // ★ 추가됨
          'mode': 'manual_control', // 'manual' 대신 명시적 값 사용 권장
          'timestamp': DateTime.now().toIso8601String(),
        });
      } else {
        // [수정] 유저가 있으면 AI Tracking으로 변경 (type: motor 추가)
        widget.onUserDataSend!.call({
          'action': 'mode_change',
          'type': 'motor', // ★ 추가됨
          'mode': 'ai_tracking', // 'ai' 대신 'ai_tracking'으로 통일
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight,
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              deviceName: widget.deviceName,
              subtitle: 'User Management',
              connected: widget.connected,
              onConnectToggle: widget.onConnect,
              userImagePath: null,
            ),
            const SizedBox(height: 10),

            _buildSelectionHeader(),

            const SizedBox(height: 10),

            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.8,
                ),
                itemCount: users.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return _buildAddUserCard();

                  final userIndex = index - 1;
                  final user = users[userIndex];
                  final isSelected = selectedUserIndices.contains(userIndex);

                  final selectionOrder = isSelected
                      ? selectedUserIndices.indexOf(userIndex) + 1
                      : null;

                  return _UserGridCard(
                    user: user,
                    isSelected: isSelected,
                    selectionOrder: selectionOrder,
                    activeColor: selectionOrder == 1 ? colorUser1 : colorUser2,
                    onTap: () => _selectUser(userIndex),
                    onEdit: () => _editUser(userIndex),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Tracking Targets",
                style: TextStyle(
                  fontFamily: 'Sen',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: textMain,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                selectedUserIndices.isEmpty
                    ? "Select up to 2 targets"
                    : "${selectedUserIndices.length} active",
                style: TextStyle(
                  fontFamily: 'Sen',
                  fontSize: 14,
                  color: selectedUserIndices.isEmpty
                      ? textSub
                      : colorUser1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (selectedUserIndices.isNotEmpty)
            TextButton.icon(
              onPressed: _clearAllSelections,
              icon: const Icon(Icons.refresh_rounded, size: 16, color: textSub),
              label: const Text(
                "Reset",
                style: TextStyle(
                    fontFamily: 'Sen',
                    color: textSub,
                    fontWeight: FontWeight.w600,
                    fontSize: 13
                ),
              ),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                    side: BorderSide(color: Colors.grey.withOpacity(0.2))
                ),
                elevation: 0,
              ),
            )
        ],
      ),
    );
  }

  Widget _buildAddUserCard() {
    return GestureDetector(
      onTap: _addUser,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFE2E8F0),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: Color(0xFF94A3B8), size: 28),
            ),
            const SizedBox(height: 12),
            const Text(
              "Add New",
              style: TextStyle(
                fontFamily: 'Sen',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserProfile {
  final String name;
  final String? avatarUrl;
  final String? imagePath;
  final String? userId;

  UserProfile({required this.name, this.avatarUrl, this.imagePath, this.userId});

  Map<String, dynamic> toJson() => {'name': name, 'avatarUrl': avatarUrl, 'imagePath': imagePath, 'userId': userId};
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(name: json['name'], avatarUrl: json['avatarUrl'], imagePath: json['imagePath'], userId: json['userId']);
}

class _UserGridCard extends StatelessWidget {
  final UserProfile user;
  final bool isSelected;
  final int? selectionOrder;
  final Color activeColor;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _UserGridCard({
    required this.user,
    required this.isSelected,
    this.selectionOrder,
    required this.activeColor,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isSelected ? activeColor : Colors.transparent,
              width: isSelected ? 2.5 : 0
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: activeColor.withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 8),
              )
            else
              BoxShadow(
                color: const Color(0xFFCBD5E1).withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isSelected ? 76 : 72,
                    height: isSelected ? 76 : 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? activeColor.withOpacity(0.2) : Colors.transparent,
                        width: isSelected ? 4 : 0,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF8FAFC),
                          image: user.imagePath != null
                              ? DecorationImage(image: FileImage(File(user.imagePath!)), fit: BoxFit.cover)
                              : null
                      ),
                      child: user.imagePath == null
                          ? Icon(Icons.person, size: 32, color: Colors.grey[300])
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 16,
                      color: isSelected ? activeColor : const Color(0xFF1E293B),
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? activeColor.withOpacity(0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isSelected ? "Tracking Active" : "Tab to select",
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected ? activeColor : const Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 10,
              right: 10,
              child: GestureDetector(
                onTap: onEdit,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.more_horiz_rounded, size: 16, color: Color(0xFF64748B)),
                ),
              ),
            ),
            if (isSelected && selectionOrder != null)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withOpacity(0.4),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "$selectionOrder",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      fontFamily: 'Sen',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}