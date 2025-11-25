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
  final Function(String?, String?) onUserSelectionChanged;
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

  // ★ [디자인 수정 1] 세련된 컬러 팔레트로 전면 교체
  static const Color bgLight = Color(0xFFF8FAFC);      // 아주 연한 쿨 그레이 배경
  static const Color textMain = Color(0xFF1E293B);     // 짙은 슬레이트 (가독성 UP)
  static const Color textSub = Color(0xFF64748B);      // 연한 슬레이트

  // 유저 선택 색상 (User 1: Indigo, User 2: Teal) -> 쨍한 파랑/보라 제거
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

  // --- 기존 로직 유지 ---

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
                  backgroundColor: const Color(0xFFFF5252), // 경고는 붉은색 유지
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

  void _updateMainSelectionState() {
    selectedUserIndex = selectedUserIndices.isNotEmpty ? selectedUserIndices[0] : null;
    if (selectedUserIndices.isNotEmpty) {
      final firstUser = users[selectedUserIndices[0]];
      widget.onUserSelectionChanged(firstUser.name, firstUser.imagePath);
    } else {
      widget.onUserSelectionChanged(null, null);
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
        'selected_users': selectedUsers,
      });

      if (selectedUsers.isEmpty) {
        widget.onUserDataSend!.call({'action': 'mode_change', 'mode': 'manual', 'timestamp': DateTime.now().toIso8601String(), 'selected_users': []});
      } else {
        widget.onUserDataSend!.call({'action': 'mode_change', 'mode': 'ai', 'timestamp': DateTime.now().toIso8601String(), 'selected_users': selectedUsers});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgLight, // 배경색 적용
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
                  // Add Button
                  if (index == 0) return _buildAddUserCard();

                  final userIndex = index - 1;
                  final user = users[userIndex];
                  final isSelected = selectedUserIndices.contains(userIndex);

                  // 선택 순서 (1 or 2)
                  final selectionOrder = isSelected
                      ? selectedUserIndices.indexOf(userIndex) + 1
                      : null;

                  return _UserGridCard(
                    user: user,
                    isSelected: isSelected,
                    selectionOrder: selectionOrder,
                    // ★ [수정] Grid에서 Card로 색상 전달
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

  // ★ [디자인 수정 2] 헤더 (Reset 버튼 색상: 노랑 -> 회색)
  Widget _buildSelectionHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Tracking Targets", // 'AI' 제거, 심플하게
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
                      : colorUser1, // 활성 상태 시 Indigo
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
                    color: textSub, // 노란색 제거 -> 회색
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

  // ★ [디자인 수정 3] Add Card 스타일 (점선 느낌 대신 깔끔한 보더)
  Widget _buildAddUserCard() {
    return GestureDetector(
      onTap: _addUser,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFE2E8F0), // 아주 연한 회색
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
                color: Color(0xFFF1F5F9), // 연한 배경
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

// UserProfile 모델
class UserProfile {
  final String name;
  final String? avatarUrl;
  final String? imagePath;
  final String? userId;

  UserProfile({required this.name, this.avatarUrl, this.imagePath, this.userId});

  Map<String, dynamic> toJson() => {'name': name, 'avatarUrl': avatarUrl, 'imagePath': imagePath, 'userId': userId};
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(name: json['name'], avatarUrl: json['avatarUrl'], imagePath: json['imagePath'], userId: json['userId']);
}

// ★ [디자인 수정 4] 새로 정의된 Grid Card (오류 해결됨)
// 기존의 중복된 클래스를 삭제하고 하나로 통합함
class _UserGridCard extends StatelessWidget {
  final UserProfile user;
  final bool isSelected;
  final int? selectionOrder;
  final Color activeColor; // 상위에서 색상을 받도록 수정
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _UserGridCard({
    required this.user,
    required this.isSelected,
    this.selectionOrder,
    required this.activeColor, // 필수 파라미터로 추가
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
          // 선택 시 테두리 처리
          border: Border.all(
              color: isSelected ? activeColor : Colors.transparent,
              width: isSelected ? 2.5 : 0
          ),
          // 그림자 효과 개선
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
                // 상태 텍스트
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

            // 편집 아이콘
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

            // 선택 번호 배지
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