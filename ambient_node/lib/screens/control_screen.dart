import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';
import 'package:ambient_node/widgets/remote_control_dpad.dart';

class ControlScreen extends StatefulWidget {
  final bool connected;
  final String deviceName;
  final VoidCallback onConnect;
  final String? selectedUserName;
  final Function(String?) onUserSelectionChanged;

  const ControlScreen({
    super.key,
    required this.connected,
    required this.deviceName,
    required this.onConnect,
    this.selectedUserName,
    required this.onUserSelectionChanged,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  List<UserProfile> users = [];
  int? selectedUserIndex;

  void _addUser() {
    setState(() {
      users.add(UserProfile(
        name: 'User ${users.length + 1}',
        avatarUrl: 'https://i.pravatar.cc/150?img=${users.length + 1}',
      ));
    });
  }

  void _deleteUser(int index) {
    setState(() {
      if (selectedUserIndex == index) {
        selectedUserIndex = null;
        widget.onUserSelectionChanged(null);
      } else if (selectedUserIndex != null && selectedUserIndex! > index) {
        selectedUserIndex = selectedUserIndex! - 1;
      }
      users.removeAt(index);
    });
  }

  void _selectUser(int index) {
    setState(() {
      selectedUserIndex = (selectedUserIndex == index) ? null : index;
      // 부모 위젯(MainShell)에 선택된 사용자 이름 전달
      widget.onUserSelectionChanged(
        selectedUserIndex != null ? users[selectedUserIndex!].name : null,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
          children: [
            // 공통 상단바
            AppTopBar(
              deviceName: widget.deviceName,
              subtitle: selectedUserIndex != null
                  ? '${users[selectedUserIndex!].name} 선택 중'
                  : 'Lab Fan',
              connected: widget.connected,
              onConnectToggle: widget.onConnect,
            ),

            const SizedBox(height: 16),

            // 사용자 프로필 가로 스크롤
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: users.length + 1, // +1 for add button
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // 첫 번째: 사용자 추가 버튼
                    return _AddUserCard(onTap: _addUser);
                  }
                  final userIndex = index - 1;
                  return _UserCard(
                    user: users[userIndex],
                    isSelected: selectedUserIndex == userIndex,
                    onTap: () => _selectUser(userIndex),
                    onLongPress: () => _showDeleteDialog(userIndex),
                  );
                },
              ),
            ),

            const SizedBox(height: 40),

            // 리모콘
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

  void _showDeleteDialog(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사용자 삭제'),
        content: Text('${users[index].name}을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              _deleteUser(index);
              Navigator.pop(context);
            },
            child: const Text(
              '삭제',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _sendCommand(String direction) {
    if (selectedUserIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사용자를 먼저 선택해주세요')),
      );
      return;
    }
    print('Command: $direction for user ${users[selectedUserIndex!].name}');
    // TODO: BLE 명령 전송 로직
  }
}

class UserProfile {
  final String name;
  final String avatarUrl;

  UserProfile({required this.name, required this.avatarUrl});
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
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _UserCard({
    required this.user,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 90,
        height: 90,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: isSelected
              ? Border.all(color: const Color(0xFF437EFF), width: 3)
              : null,
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFF437EFF).withOpacity(0.2)
                  : Colors.black.withOpacity(0.05),
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
                image: DecorationImage(
                  image: NetworkImage(user.avatarUrl),
                  fit: BoxFit.cover,
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
      ),
    );
  }
}
