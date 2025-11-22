// lib/services/user_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../utils/image_helper.dart';

/// 사용자 관리 및 서버 동기화를 담당하는 서비스
class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  // 외부에서 주입받을 데이터 전송 함수 (BleService의 sendData)
  Function(Map<String, dynamic>)? _sendDataFunc;

  // 상태 관리를 위한 Notifier (화면 갱신용)
  final ValueNotifier<List<UserProfile>> usersNotifier = ValueNotifier([]);

  // 현재 선택된 사용자 인덱스들
  List<int> selectedUserIndices = [];

  /// 초기화: BLE 전송 함수 연결 및 로컬 데이터 로드
  Future<void> init({required Function(Map<String, dynamic>) onSendData}) async {
    _sendDataFunc = onSendData;
    await _loadUsersFromLocal();
  }

  /// 로컬 저장소에서 사용자 목록 불러오기
  Future<void> _loadUsersFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getStringList('users') ?? [];

    final loadedUsers = usersJson.map((userStr) {
      return UserProfile.fromJson(jsonDecode(userStr));
    }).toList();

    usersNotifier.value = loadedUsers;
  }

  /// 로컬 저장소에 저장
  Future<void> _saveUsersToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = usersNotifier.value
        .map((user) => jsonEncode(user.toJson()))
        .toList();
    await prefs.setStringList('users', usersJson);
  }

  // ===============================================================
  // [Action] 사용자 추가 (Register)
  // ===============================================================
  Future<void> registerUser(String name, String imagePath) async {
    // 1. ID 생성 (서버와 맞춤: user_timestamp)
    final generatedUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';

    final newUser = UserProfile(
      userId: generatedUserId,
      name: name,
      imagePath: imagePath,
    );

    // 2. 리스트 업데이트 및 로컬 저장
    final currentList = List<UserProfile>.from(usersNotifier.value);
    currentList.add(newUser);
    usersNotifier.value = currentList;
    await _saveUsersToLocal();

    // 3. BLE 전송 (서버의 user_register 액션과 매칭)
    if (_sendDataFunc != null) {
      // 이미지 인코딩
      final base64Image = await ImageHelper.encodeImageToBase64(imagePath);

      _sendDataFunc!({
        'action': 'user_register',
        'user_id': generatedUserId,
        'name': name,
        'image_base64': base64Image,
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint("📤 [UserService] 사용자 등록 요청 전송: $name");
    }
  }

  // ===============================================================
  // [Action] 사용자 수정 (Update)
  // ===============================================================
  Future<void> updateUser(int index, String name, String imagePath) async {
    if (index < 0 || index >= usersNotifier.value.length) return;

    final currentList = List<UserProfile>.from(usersNotifier.value);
    final oldUser = currentList[index];

    final updatedUser = oldUser.copyWith(
      name: name,
      imagePath: imagePath,
    );

    currentList[index] = updatedUser;
    usersNotifier.value = currentList;
    await _saveUsersToLocal();

    // BLE 전송 (서버의 handle_user_update 대응 필요 - 현재 서버 코드엔 user_register로 덮어쓰기 가능)
    if (_sendDataFunc != null) {
      final base64Image = await ImageHelper.encodeImageToBase64(imagePath);

      // 서버 로직상 user_register는 ON CONFLICT UPDATE를 수행하므로 register와 동일하게 보냄
      // 혹은 별도 user_update 액션이 있다면 그것을 사용
      _sendDataFunc!({
        'action': 'user_register', // or 'user_update'
        'user_id': updatedUser.userId,
        'name': name,
        'image_base64': base64Image,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // 만약 이 사용자가 현재 선택된 상태라면, 선택 정보도 갱신
      if (selectedUserIndices.contains(index)) {
        sendUserSelection();
      }
    }
  }

  // ===============================================================
  // [Action] 사용자 삭제 (Delete)
  // ===============================================================
  Future<void> deleteUser(int index) async {
    if (index < 0 || index >= usersNotifier.value.length) return;

    final currentList = List<UserProfile>.from(usersNotifier.value);
    final userToDelete = currentList[index];

    // 선택 목록에서 제거 및 인덱스 조정
    if (selectedUserIndices.contains(index)) {
      selectedUserIndices.remove(index);
    }
    selectedUserIndices = selectedUserIndices
        .map((idx) => idx > index ? idx - 1 : idx)
        .toList();

    currentList.removeAt(index);
    usersNotifier.value = currentList;
    await _saveUsersToLocal();

    // 삭제 후 선택 정보 갱신 전송
    sendUserSelection();
    // (선택 사항) 서버에 삭제 요청 전송 기능이 있다면 추가
    // _sendDataFunc!({'action': 'user_delete', 'user_id': userToDelete.userId});
  }

  Future<void> deleteAllUsers() async {
    usersNotifier.value = []; // 리스트 비우기
    selectedUserIndices.clear(); // 선택 정보 초기화

    await _saveUsersToLocal();
    sendUserSelection(); // 변경 사항(빈 리스트) 전송

    debugPrint("🗑️ [UserService] All users deleted.");
  }
  // ===============================================================
  // [Action] 사용자 선택 (Select)
  // ===============================================================
  void toggleUserSelection(int index) {
    if (selectedUserIndices.contains(index)) {
      selectedUserIndices.remove(index);
      selectedUserIndices.sort();
    } else {
      if (selectedUserIndices.length >= 2) {
        // 최대 2명 제한 (UI에서 스낵바 처리 등을 위해 리턴값이나 콜백 고려 가능)
        return;
      }
      selectedUserIndices.add(index);
      selectedUserIndices.sort();
    }

    // 변경 사항 서버 전송
    sendUserSelection();
  }

  void clearSelection() {
    selectedUserIndices.clear();
    sendUserSelection();
  }

  /// 현재 선택된 사용자 정보를 BLE로 전송
  void sendUserSelection() {
    if (_sendDataFunc == null) return;

    final allUsers = usersNotifier.value;

    // 서버 포맷에 맞게 변환
    List<Map<String, dynamic>> selectedUsersPayload = selectedUserIndices.map((idx) {
      final user = allUsers[idx];
      return {
        'user_id': user.userId,
        'name': user.name,
        'role': selectedUserIndices.indexOf(idx) + 1, // 1 or 2
      };
    }).toList();

    _sendDataFunc!({
      'action': 'user_select',
      'users': selectedUsersPayload,
      'timestamp': DateTime.now().toIso8601String(),
    });

    debugPrint("📤 [UserService] 사용자 선택 전송: ${selectedUsersPayload.length}명");
  }

  /// 현재 선택된 사용자(들)의 이름 문자열 반환 (UI 표시용)
  String getSelectedUsersText() {
    if (selectedUserIndices.isEmpty) return "Lab Fan";
    if (selectedUserIndices.length == 1) {
      return "${usersNotifier.value[selectedUserIndices[0]].name} 선택 중";
    }
    return "${selectedUserIndices.length}명 선택 중";
  }

  /// 현재 선택된 첫 번째 사용자의 이미지 경로 반환 (UI 표시용)
  String? getSelectedUserImage() {
    if (selectedUserIndices.isEmpty) return null;
    return usersNotifier.value[selectedUserIndices[0]].imagePath;
  }
}