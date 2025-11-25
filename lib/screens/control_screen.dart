import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ambient_node/widgets/app_top_bar.dart';
import 'package:ambient_node/widgets/remote_control_dpad.dart';
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
  bool isManualControlActive = false;

  // 디자인 상수
  static const Color primaryBlue = Color(0xFF3A91FF);
  static const Color textDark = Color(0xFF2D3142);

  @override
  void initState() {
    super.initState();
    _loadUsers();

    _dataSubscription = widget.dataStream?.listen((data) {
      if (!mounted) return;
      setState(() {
        _handleIncomingData(data);
      });
    });
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    super.dispose();
  }

  void _handleIncomingData(Map<String, dynamic> data) {
    // ... (기존 로직 유지) ...
    print("[ControlScreen] Data received: $data");
    final type = data['type'];
    if (type == 'REGISTER_ACK') {
      // ...
    } else if (type == 'FACE_DETECTED') {
      print("[ControlScreen] Face detected: ${data['user_id']}");
    } else if (type == 'FACE_LOST') {
      print("[ControlScreen] Face lost: ${data['user_id']}");
    }
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

  // ... (기존 _addUser, _editUser, _deleteUser, _selectUser, _sendUserSelectionToBLE, _reorderSelectedUsers, _clearAllSelections, _sendCommand 로직 모두 동일하게 유지) ...
  // 코드 길이상 로직 부분은 생략하지 않고 핵심만 유지하거나, 기존 코드를 그대로 사용해주세요.
  // (UI 변경을 위해 아래 build 메서드와 위젯 클래스들이 중요합니다.)

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
      if (selectedUserIndices.isNotEmpty) {
        selectedUserIndex = selectedUserIndices[0];
        final firstUser = users[selectedUserIndex!];
        widget.onUserSelectionChanged(firstUser.name, firstUser.imagePath);
      } else {
        selectedUserIndex = null;
        widget.onUserSelectionChanged(null, null);
      }
    });
    await _saveUsers();
    _sendUserSelectionToBLE();
  }

  void _selectUser(int index) {
    setState(() {
      final isSelected = selectedUserIndices.contains(index);
      if (isSelected) {
        selectedUserIndices.remove(index);
        _reorderSelectedUsers();
      } else {
        if (selectedUserIndices.length >= 2) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('최대 2명까지만 선택 가능합니다'), duration: Duration(seconds: 2), backgroundColor: Colors.orange));
          return;
        }
        selectedUserIndices.add(index);
        _reorderSelectedUsers();
      }
      selectedUserIndex = selectedUserIndices.isNotEmpty ? selectedUserIndices[0] : null;
      if (selectedUserIndices.isNotEmpty) {
        final firstUser = users[selectedUserIndices[0]];
        widget.onUserSelectionChanged(firstUser.name, firstUser.imagePath);
      } else {
        widget.onUserSelectionChanged(null, null);
      }
    });
    _sendUserSelectionToBLE();
  }

  void _reorderSelectedUsers() {
    selectedUserIndices.sort();
  }

  void _clearAllSelections() {
    setState(() {
      selectedUserIndices.clear();
      selectedUserIndex = null;
      widget.onUserSelectionChanged(null, null);
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
      // 만약 선택 해제면 manual, 선택되면 AI (리모컨 아닐때)
      if (selectedUsers.isEmpty) {
        widget.onUserDataSend!.call({'action': 'mode_change', 'mode': 'manual', 'timestamp': DateTime.now().toIso8601String(), 'selected_users': []});
        isManualControlActive = false;
      } else if (!isManualControlActive) {
        widget.onUserDataSend!.call({'action': 'mode_change', 'mode': 'ai', 'timestamp': DateTime.now().toIso8601String(), 'selected_users': selectedUsers});
      }
    }
  }

  void _sendCommand(String direction, int toggleOn) {
    // ... (기존 로직 유지) ...
    if (!widget.connected) return;
    String d = direction.isNotEmpty ? direction[0].toLowerCase() : direction;
    final selectedUsers = _getSelectedUsersList();

    if (widget.onUserDataSend != null) {
      if (toggleOn == 1) {
        isManualControlActive = true;
        widget.onUserDataSend!.call({'action': 'mode_change', 'mode': 'manual', 'timestamp': DateTime.now().toIso8601String(), 'selected_users': selectedUsers});
      } else if (toggleOn == 0) {
        isManualControlActive = false;
        if (selectedUserIndices.isNotEmpty) {
          widget.onUserDataSend!.call({'action': 'mode_change', 'mode': 'ai', 'timestamp': DateTime.now().toIso8601String(), 'selected_users': selectedUsers});
        }
      }
      widget.onUserDataSend!.call({'action': 'angle_change', 'direction': d, 'toggleOn': toggleOn, 'timestamp': DateTime.now().toIso8601String(), 'selected_users': selectedUsers});
    }
    try { AnalyticsService.onManualControl(d, null); } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Top Bar
            AppTopBar(
              deviceName: widget.deviceName,
              subtitle: selectedUserIndices.isNotEmpty
                  ? selectedUserIndices.length == 1
                  ? '${users[selectedUserIndices[0]].name}'
                  : '${selectedUserIndices.length}명 선택됨'
                  : 'Manual Control',
              connected: widget.connected,
              onConnectToggle: widget.onConnect,
              userImagePath: selectedUserIndices.isNotEmpty
                  ? users[selectedUserIndices[0]].imagePath
                  : null,
            ),

            const SizedBox(height: 20),

            // 2. 관리 및 타이틀 섹션 (개선됨)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  const Text(
                    "Target Users",
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textDark,
                    ),
                  ),
                  const Spacer(),

                  // 편집 버튼 (선택 시 활성)
                  _buildActionButton(
                    icon: Icons.edit_rounded,
                    label: "Edit",
                    color: primaryBlue,
                    isEnabled: selectedUserIndices.length == 1,
                    onTap: () => _editUser(selectedUserIndices[0]),
                  ),

                  const SizedBox(width: 12),

                  // 전체 해제 버튼 (선택 시 활성)
                  _buildActionButton(
                    icon: Icons.close_rounded,
                    label: "Clear",
                    color: Colors.orange,
                    isEnabled: selectedUserIndices.isNotEmpty,
                    onTap: _clearAllSelections,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. 사용자 리스트 (개선됨)
            SizedBox(
              height: 120, // 높이 약간 증가
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: users.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _AddUserCard(onTap: _addUser);
                  }
                  final userIndex = index - 1;
                  final isSelected = selectedUserIndices.contains(userIndex);
                  final selectionOrder = isSelected
                      ? selectedUserIndices.indexOf(userIndex) + 1
                      : null;
                  return _UserCard(
                    user: users[userIndex],
                    isSelected: isSelected,
                    selectionOrder: selectionOrder,
                    onTap: () => _selectUser(userIndex),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // 4. D-Pad Controller
            Expanded(
              child: Center(
                child: RemoteControlDpad(
                  size: 280,
                  onUp: () => _sendCommand('up', 1),
                  onUpEnd: () => _sendCommand('up', 0),
                  onDown: () => _sendCommand('down', 1),
                  onDownEnd: () => _sendCommand('down', 0),
                  onLeft: () => _sendCommand('left', 1),
                  onLeftEnd: () => _sendCommand('left', 0),
                  onRight: () => _sendCommand('right', 1),
                  onRightEnd: () => _sendCommand('right', 0),
                  onCenter: () => _sendCommand('center', 1),
                  onCenterEnd: () => _sendCommand('center', 0),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // 액션 버튼 위젯 (캡슐 형태)
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isEnabled ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isEnabled ? color.withOpacity(0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isEnabled ? color : Colors.grey[400],
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Sen',
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isEnabled ? color : Colors.grey[400],
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

// 사용자 추가 카드 (디자인 개선)
class _AddUserCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddUserCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 85,
        margin: const EdgeInsets.only(right: 16, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.withOpacity(0.2), style: BorderStyle.solid),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF3A91FF).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, color: Color(0xFF3A91FF), size: 24),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add New',
              style: TextStyle(
                fontFamily: 'Sen',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF9098B1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 사용자 프로필 카드 (디자인 개선)
// 사용자 프로필 카드 (디자인 리뉴얼: Glow 효과 + 모던 컬러)
class _UserCard extends StatelessWidget {
  final UserProfile user;
  final bool isSelected;
  final int? selectionOrder;
  final VoidCallback onTap;

  const _UserCard({
    required this.user,
    required this.isSelected,
    this.selectionOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // [색상 변경 포인트]
    // 1번 사용자: 앱 시그니처 블루 (Soft Blue)
    // 2번 사용자: 세련된 바이올렛 (Modern Violet) - 초록색 대신 변경
    final activeColor = selectionOrder == 2
        ? const Color(0xFF8B5CF6) // Violet
        : const Color(0xFF3A91FF); // Blue

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: 85,
        margin: const EdgeInsets.only(right: 16, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          // 선택 시: 색상 테두리 + 은은한 그림자(Glow)
          border: isSelected
              ? Border.all(color: activeColor, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: activeColor.withOpacity(0.3), // 빛 번짐 효과
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 1,
              )
            else
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 프로필 이미지 컨테이너
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[50],
                      border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 2
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2)
                        ),
                      ]
                  ),
                  child: ClipOval(
                    child: user.imagePath != null
                        ? Image.file(File(user.imagePath!), fit: BoxFit.cover)
                        : user.avatarUrl != null
                        ? Image.network(user.avatarUrl!, fit: BoxFit.cover)
                        : Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(Icons.person_rounded, size: 24, color: Colors.grey[300]),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // 이름 텍스트
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? activeColor : const Color(0xFF9098B1),
                    ),
                  ),
                ),
              ],
            ),

            // 순서 뱃지 (우측 상단 작게 표시)
            if (isSelected && selectionOrder != null)
              Positioned(
                top: 6,
                right: 6,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: activeColor.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))
                    ],
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$selectionOrder',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
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