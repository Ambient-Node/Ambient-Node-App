import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';
import 'package:ambient_node/widgets/remote_control_dpad.dart';
import 'package:ambient_node/screens/user_registration_screen.dart';
import 'package:ambient_node/utils/image_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ambient_node/services/analytics_service.dart';

class ControlScreen extends StatefulWidget {
  final bool connected;
  final String deviceName;
  final VoidCallback onConnect;
  final String? selectedUserName;
  final Function(String?, String?) onUserSelectionChanged;
  final Function(Map<String, dynamic>)? onUserDataSend;

  const ControlScreen({
    super.key,
    required this.connected,
    required this.deviceName,
    required this.onConnect,
    this.selectedUserName,
    required this.onUserSelectionChanged,
    this.onUserDataSend,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  List<UserProfile> users = [];
  int? selectedUserIndex; // 단일 선택 (하위 호환성)
  List<int> selectedUserIndices = []; // 다중 선택 (최대 2명)

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getStringList('users') ?? [];
    setState(() {
      users = usersJson
          .map((userStr) => UserProfile.fromJson(jsonDecode(userStr)))
          .toList();
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
      MaterialPageRoute(
        builder: (context) => const UserRegistrationScreen(),
      ),
    );

    if (result != null && result['action'] == 'register') {
      final newUser = UserProfile(
        name: result['name']!,
        imagePath: result['imagePath'],
      );

      setState(() {
        users.add(newUser);
      });
      await _saveUsers();

      // BLE로 사용자 데이터 전송 (Base64 인코딩)
      final base64Image = await ImageHelper.encodeImageToBase64(result['imagePath']);

      widget.onUserDataSend?.call({
        'action': 'register_user',
        'name': result['name']!,
        'image_base64': base64Image,
        'bluetooth_id': 'android_${DateTime.now().millisecondsSinceEpoch}', // 임시 ID
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('[ControlScreen] 사용자 등록 데이터 전송: ${result['name']}');
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
          isEditMode: true,
        ),
      ),
    );

    if (result != null) {
      if (result['action'] == 'register') {
        final updatedUser = UserProfile(
          name: result['name']!,
          imagePath: result['imagePath'],
        );

        setState(() {
          users[index] = updatedUser;
        });
        await _saveUsers();

        // BLE로 수정된 사용자 데이터 전송
        final base64Image = await ImageHelper.encodeImageToBase64(result['imagePath']);

        widget.onUserDataSend?.call({
          'action': 'update_user',
          'index': index,
          'name': result['name']!,
          'image_base64': base64Image,
          'timestamp': DateTime.now().toIso8601String(),
        });

        print('[ControlScreen] 사용자 수정 데이터 전송: ${result['name']}');
      } else if (result['action'] == 'delete') {
        widget.onUserDataSend?.call({
          'action': 'delete_user',
          'index': index,
          'name': users[index].name,
          'timestamp': DateTime.now().toIso8601String(),
        });
        _deleteUser(index);
      }
    }
  }

  Future<void> _deleteUser(int index) async {
    setState(() {
      // 다중 선택에서 제거
      if (selectedUserIndices.contains(index)) {
        selectedUserIndices.remove(index);
        // 인덱스 재조정
        selectedUserIndices = selectedUserIndices.map((idx) => idx > index ? idx - 1 : idx).toList();
      } else {
        // 인덱스 재조정
        selectedUserIndices = selectedUserIndices.map((idx) => idx > index ? idx - 1 : idx).toList();
      }

      // 하위 호환성
      if (selectedUserIndex == index) {
        selectedUserIndex = null;
        widget.onUserSelectionChanged(null, null);
      } else if (selectedUserIndex != null && selectedUserIndex! > index) {
        selectedUserIndex = selectedUserIndex! - 1;
      }

      users.removeAt(index);

      // 선택 상태 업데이트
      if (selectedUserIndices.isEmpty) {
        widget.onUserSelectionChanged(null, null);
      } else {
        final firstUser = users[selectedUserIndices[0]];
        widget.onUserSelectionChanged(firstUser.name, firstUser.imagePath);
      }
    });
    await _saveUsers();
  }

  void _selectUser(int index) {
    setState(() {
      // 이미 선택된 사용자인지 확인
      final isSelected = selectedUserIndices.contains(index);

      if (isSelected) {
        // 선택 해제
        selectedUserIndices.remove(index);
        _reorderSelectedUsers();
      } else {
        // 새로 선택
        if (selectedUserIndices.length >= 2) {
          // 최대 2명 초과 시 경고
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('최대 2명까지만 선택 가능합니다'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }
        selectedUserIndices.add(index);
      }

      // 하위 호환성을 위한 단일 선택 업데이트
      selectedUserIndex = selectedUserIndices.isNotEmpty ? selectedUserIndices[0] : null;

      // 첫 번째 선택된 사용자 정보 전달 (하위 호환성)
      if (selectedUserIndices.isNotEmpty) {
        final firstUser = users[selectedUserIndices[0]];
        widget.onUserSelectionChanged(firstUser.name, firstUser.imagePath);
      } else {
        widget.onUserSelectionChanged(null, null);
      }

      // BLE로 다중 사용자 선택 전송
      final selectedUsersData = selectedUserIndices.map((idx) {
        final user = users[idx];
        return {
          'user_id': user.name.toLowerCase().replaceAll(' ', '_'),
          'name': user.name,
          'role': selectedUserIndices.indexOf(idx) + 1, // 1번, 2번
        };
      }).toList();

      widget.onUserDataSend?.call({
        'action': 'select_users',
        'users': selectedUsersData,
        'count': selectedUserIndices.length,
        'timestamp': DateTime.now().toIso8601String(),
      });

      print('[ControlScreen] 선택된 사용자: ${selectedUserIndices.map((idx) => users[idx].name).join(", ")}');
    });
  }

  void _reorderSelectedUsers() {
    // 선택 해제 후 순서 재정렬 (1번, 2번 유지)
    // 이미 정렬되어 있으므로 별도 작업 불필요
    // 필요시 여기서 추가 로직 구현 가능
  }

  void _clearAllSelections() {
    setState(() {
      selectedUserIndices.clear();
      selectedUserIndex = null;
      widget.onUserSelectionChanged(null, null);

      widget.onUserDataSend?.call({
        'action': 'clear_selection',
        'timestamp': DateTime.now().toIso8601String(),
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
          children: [
            AppTopBar(
              deviceName: widget.deviceName,
              subtitle: selectedUserIndices.isNotEmpty
                  ? selectedUserIndices.length == 1
                      ? '${users[selectedUserIndices[0]].name} 선택 중'
                      : '${selectedUserIndices.length}명 선택 중'
                  : 'Lab Fan',
              connected: widget.connected,
              onConnectToggle: widget.onConnect,
              userImagePath: selectedUserIndices.isNotEmpty
                  ? users[selectedUserIndices[0]].imagePath
                  : null,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (selectedUserIndices.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearAllSelections,
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('전체 해제'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        foregroundColor: Colors.orange,
                        backgroundColor: Colors.orange.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  TextButton.icon(
                    onPressed: selectedUserIndices.isNotEmpty && selectedUserIndices.length == 1
                        ? () => _editUser(selectedUserIndices[0])
                        : null,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: selectedUserIndices.isNotEmpty && selectedUserIndices.length == 1
                          ? const Color(0xFF3A90FF)
                          : Colors.grey,
                    ),
                    label: Text(
                      '편집',
                      style: TextStyle(
                        fontFamily: 'Sen',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selectedUserIndices.isNotEmpty && selectedUserIndices.length == 1
                            ? const Color(0xFF3A90FF)
                            : Colors.grey,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      backgroundColor: selectedUserIndices.isNotEmpty && selectedUserIndices.length == 1
                          ? const Color(0xFF3A90FF).withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
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
                  final selectionOrder = isSelected ? selectedUserIndices.indexOf(userIndex) + 1 : null;
                  return _UserCard(
                    user: users[userIndex],
                    isSelected: isSelected,
                    selectionOrder: selectionOrder,
                    onTap: () => _selectUser(userIndex),
                  );
                },
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: Center(
                child: RemoteControlDpad(
                  size: 280,
                  onUp: () => _sendCommand('up'),
                  onDown: () => _sendCommand('down'),
                  onLeft: () => _sendCommand('left'),
                  onRight: () => _sendCommand('right'),
                  onCenter: () => _sendCommand('center'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendCommand(String direction) {
    if (selectedUserIndices.isNotEmpty) {
      final userNames = selectedUserIndices.map((idx) => users[idx].name).join(", ");
      print('[ControlScreen] 수동 제어: $direction (사용자: $userNames)');
    } else {
      print('[ControlScreen] 수동 제어: $direction (사용자 선택 없음)');
    }

    try {
      AnalyticsService.onManualControl(direction, null);
    } catch (e) {
      print('[ControlScreen] AnalyticsService 오류: $e');
    }

    // BLE로 수동 제어 명령 전송
    final selectedUsers = selectedUserIndices.map((idx) => users[idx].name).toList();
    widget.onUserDataSend?.call({
      'action': 'manual_control',
      'direction': direction,
      'users': selectedUsers,
      'user': selectedUserIndices.isNotEmpty ? users[selectedUserIndices[0]].name : null, // 하위 호환성
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}

// UserProfile, _AddUserCard, _UserCard 클래스는 동일
class UserProfile {
  final String name;
  final String? avatarUrl;
  final String? imagePath;

  UserProfile({
    required this.name,
    this.avatarUrl,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'avatarUrl': avatarUrl,
    'imagePath': imagePath,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    imagePath: json['imagePath'] as String?,
  );
}

class _AddUserCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddUserCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 90,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF437EFF).withOpacity(0.1),
              ),
              child: const Icon(
                Icons.add,
                color: Color(0xFF437EFF),
                size: 30,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '추가',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF282840),
                fontFamily: 'Sen',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserProfile user;
  final bool isSelected;
  final int? selectionOrder; // 1 또는 2
  final VoidCallback onTap;

  const _UserCard({
    required this.user,
    required this.isSelected,
    this.selectionOrder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 선택 순서에 따른 색상 결정
    final borderColor = selectionOrder == 1
        ? const Color(0xFF437EFF) // 파란색 (1번)
        : selectionOrder == 2
            ? const Color(0xFF4CAF50) // 초록색 (2번)
            : const Color(0xFF437EFF); // 기본 파란색

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 90,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: isSelected
              ? Border.all(color: borderColor, width: 3)
              : null,
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? borderColor.withOpacity(0.2)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFECF0F4),
                  ),
                  child: ClipOval(
                    child: user.imagePath != null
                        ? Image.file(
                            File(user.imagePath!),
                            fit: BoxFit.cover,
                            width: 50,
                            height: 50,
                          )
                        : user.avatarUrl != null
                            ? Image.network(
                                user.avatarUrl!,
                                fit: BoxFit.cover,
                                width: 50,
                                height: 50,
                              )
                            : Icon(
                                Icons.person,
                                size: 30,
                                color: Colors.grey.shade400,
                              ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF282840),
                    fontFamily: 'Sen',
                  ),
                ),
              ],
            ),
            // 선택 순서 배지 (왼쪽 상단)
            if (selectionOrder != null)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: borderColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$selectionOrder',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Sen',
                      ),
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
