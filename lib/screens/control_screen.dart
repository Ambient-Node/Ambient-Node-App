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
  int? selectedUserIndex; // 단일 선택 (하위 호환성)
  List<int> selectedUserIndices = []; // 다중 선택 (최대 2명)

  // 스트림 구독 관리 변수 (메모리 누수 방지용)
  StreamSubscription? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _loadUsers();

    // 데이터 수신 리스너 등록
    // 화면이 생성될 때 스트림을 구독하고, 데이터가 오면 _handleIncomingData 호출
    _dataSubscription = widget.dataStream?.listen((data) {
      if (mounted) {
        _handleIncomingData(data);
      }
    });
  }

  @override
  void dispose() {
    // 화면이 종료될 때 구독 취소
    _dataSubscription?.cancel();
    super.dispose();
  }

  /// 서버(BLE Gateway)로부터 들어온 데이터 처리
  void _handleIncomingData(Map<String, dynamic> data) {
    print("📥 [ControlScreen] 데이터 수신: $data");
    final type = data['type'];

    if (type == 'REGISTER_ACK') {
      if (data['success'] == true) {
        print("[ControlScreen] ai_service로부터 사용자 등록 성공");
      } else {
        print("[ControlScreen] ai_service로부터 사용자 등록 실패: ${data['error']}");
      }
    }
    else if (type == 'FACE_DETECTED') {
      print("👤 얼굴 감지됨: ${data['user_id']}");
    }
    else if (type == 'FACE_LOST') { // 8초동안 얼굴이 보이지 않았을 때
      print("👤 얼굴 인식 실패: ${data['user_id']}");
    }
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

  // 2. 사용자 등록 함수 (기존 로직 유지 + ID 전송 확인)
  Future<void> _addUser() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const UserRegistrationScreen()),
    );

    if (result != null && result['action'] == 'register') {
      // 앱에서 ID 생성 (예: user_1715123456789)
      // 이 ID가 시스템 전체에서 쓰이는 최종 ID가 됩니다.
      final generatedUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';

      final newUser = UserProfile(
        name: result['name']!,
        imagePath: result['imagePath'],
        userId: generatedUserId, // 로컬에 바로 저장
      );

      setState(() {
        users.add(newUser);
      });
      await _saveUsers();

      // BLE 전송
      if (widget.connected && widget.onUserDataSend != null) {
        final base64Image = await ImageHelper.encodeImageToBase64(result['imagePath']);

        widget.onUserDataSend!.call({
          'action': 'user_register',
          'name': result['name']!,
          'user_id': generatedUserId, // [중요] 생성한 ID를 Gateway로 보냄
          'image_base64': base64Image,
          'timestamp': DateTime.now().toIso8601String(),
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
          isEditMode: true,
        ),
      ),
    );

    if (result != null) {
      if (result['action'] == 'register') {
        final existingUser = users[index];
        final updatedUser = UserProfile(
          name: result['name']!,
          imagePath: result['imagePath'],
          userId: existingUser.userId,
          avatarUrl: existingUser.avatarUrl,
        );

        setState(() {
          users[index] = updatedUser;
          // 선택된 사용자라면 정보 갱신을 위해 재전송
          if (selectedUserIndices.contains(index)) {
            _sendUserSelectionToBLE();
          }
        });
        await _saveUsers();

        if (widget.connected && widget.onUserDataSend != null) {
          // 이미지가 변경되었을 수 있으므로 다시 인코딩 (필요시 최적화 가능)
          final base64Image = await ImageHelper.encodeImageToBase64(result['imagePath']);

          widget.onUserDataSend!.call({
            'action': 'user_update',
            'user_id': updatedUser.userId,
            'username': result['name']!,
            'image_base64': base64Image, // 수정 시에도 이미지 전송 (선택사항)
            'timestamp': DateTime.now().toIso8601String(),
          });
          print('[ControlScreen] 사용자 수정 요청 전송: ${result['name']}');
        }

      } else if (result['action'] == 'delete') {
        final userToDelete = users[index];

        if (widget.connected && widget.onUserDataSend != null) {
          widget.onUserDataSend!.call({
            'action': 'user_delete', // Gateway에 맞게 수정 필요할 수 있음
            'user_id': userToDelete.userId,
            'timestamp': DateTime.now().toIso8601String(),
          });
        }
        _deleteUser(index);
      }
    }
  }

  Future<void> _deleteUser(int index) async {
    setState(() {
      if (selectedUserIndices.contains(index)) {
        selectedUserIndices.remove(index);
      }

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

  void _sendUserSelectionToBLE() {
    if (!widget.connected) {
      print('[ControlScreen] 연결되지 않아 사용자 선택 전송 불가');
      return;
    }

    if (selectedUserIndices.isEmpty) {
      if (widget.onUserDataSend != null) {
        widget.onUserDataSend!.call({
          'action': 'user_select', // Gateway 코드와 맞춤
          'users': [],
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
      return;
    }

    // 선택된 사용자 리스트 생성 (ID 포함)
    List<Map<String, dynamic>> selectedUsers = selectedUserIndices.map((idx) {
      final user = users[idx];
      return {
        'user_id': user.userId, // 서버가 준 ID 사용
        'name': user.name,
        'role': selectedUserIndices.indexOf(idx) + 1,
      };
    }).toList();

    if (widget.onUserDataSend != null) {
      widget.onUserDataSend!.call({
        'action': 'user_select',
        'users': selectedUsers,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    print('[ControlScreen] 👥 선택된 사용자 전송: ${selectedUsers.length}명');
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

    if (widget.connected && widget.onUserDataSend != null) {
      widget.onUserDataSend!.call({
        'action': 'user_select',
        'users': [],
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  void _sendCommand(String direction) {
    if (!widget.connected) {
      print('[ControlScreen] 연결되지 않아 명령 전송 불가');
      return;
    }

    // 수동 제어는 별도 액션으로 처리
    String action = 'manual_control'; // 또는 angle_change 등 Gateway 구현에 맞춤

    if (widget.onUserDataSend != null) {
      widget.onUserDataSend!.call({
        'action': 'angle_change',
        'angle': direction,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    // Analytics
    try {
      AnalyticsService.onManualControl(direction, null);
    } catch (e) {
      print('[ControlScreen] AnalyticsService 오류: $e');
    }
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

            // 상단 버튼 영역 (전체 해제, 편집)
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        foregroundColor: Colors.orange,
                        backgroundColor: Colors.orange.withOpacity(0.1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      backgroundColor: selectedUserIndices.isNotEmpty && selectedUserIndices.length == 1
                          ? const Color(0xFF3A90FF).withOpacity(0.1)
                          : Colors.grey.withOpacity(0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 사용자 리스트 뷰
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
            const SizedBox(height: 40),

            // D-Pad 컨트롤러
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
}

// ==========================================
// Helper Classes & Widgets
// ==========================================

class UserProfile {
  final String name;
  final String? avatarUrl;
  final String? imagePath;
  final String? userId;

  UserProfile({
    required this.name,
    this.avatarUrl,
    this.imagePath,
    this.userId,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'avatarUrl': avatarUrl,
    'imagePath': imagePath,
    'userId': userId,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    name: json['name'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    imagePath: json['imagePath'] as String?,
    userId: json['userId'] as String?,
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
              child: const Icon(Icons.add, color: Color(0xFF437EFF), size: 30),
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
    final borderColor = selectionOrder == 1
        ? const Color(0xFF437EFF)
        : selectionOrder == 2
        ? const Color(0xFF4CAF50)
        : const Color(0xFF437EFF);

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
          border: isSelected ? Border.all(color: borderColor, width: 3) : null,
          boxShadow: [
            BoxShadow(
              color: isSelected ? borderColor.withOpacity(0.2) : Colors.black.withOpacity(0.05),
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
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFECF0F4),
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
                        : Icon(Icons.person, size: 30, color: Colors.grey.shade400),
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
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 2)),
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