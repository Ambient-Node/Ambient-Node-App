import 'dart:async';
import 'dart:io';
import 'dart:convert'; // JSON
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart'; // ValueNotifier
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:camera/camera.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart'; // 필요 시 갤러리용

// ===============================================================
// [Global Variables & Initialization]
// ===============================================================
List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 카메라 초기화
  try {
    _cameras = await availableCameras();
  } on CameraException catch (e) {
    debugPrint('Error: $e.code\nError Message: $e.description');
  }

  // 2. UserService 초기화 (BLE 연동 전이라 sendData는 더미 함수)
  await UserService().init(onSendData: (data) {
    debugPrint("📡 [Mock Send]: $data"); // 실제 BLE 연동 시 교체
  });

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  runApp(const AmbientNodeApp());
}

// ===============================================================
// [Services & Models] (Provided by User)
// ===============================================================

// 1. UserProfile Model
class UserProfile {
  final String userId;
  final String name;
  final String imagePath;

  UserProfile({
    required this.userId,
    required this.name,
    required this.imagePath,
  });

  UserProfile copyWith({String? name, String? imagePath}) {
    return UserProfile(
      userId: userId,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'name': name,
    'imagePath': imagePath,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'],
      name: json['name'],
      imagePath: json['imagePath'],
    );
  }
}

// 2. ImageHelper (Mock for Demo)
class ImageHelper {
  static Future<String> encodeImageToBase64(String path) async {
    // 실제로는 File(path).readAsBytes() -> base64Encode
    return "base64_mock_string";
  }
}

// 3. UserService (Singleton Logic)
class UserService {
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal();

  Function(Map<String, dynamic>)? _sendDataFunc;
  final ValueNotifier<List<UserProfile>> usersNotifier = ValueNotifier([]);

  // [중요] 선택된 인덱스 관리용 Notifier 추가 (UI 실시간 반영을 위해)
  final ValueNotifier<List<int>> selectedIndicesNotifier = ValueNotifier([]);

  List<int> get selectedUserIndices => selectedIndicesNotifier.value;

  Future<void> init({required Function(Map<String, dynamic>) onSendData}) async {
    _sendDataFunc = onSendData;
    await _loadUsersFromLocal();
  }

  Future<void> _loadUsersFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = prefs.getStringList('users') ?? [];
    final loadedUsers = usersJson.map((userStr) => UserProfile.fromJson(jsonDecode(userStr))).toList();
    usersNotifier.value = loadedUsers;

    // 선택 상태 복원 (선택 사항, 여기선 초기화)
    selectedIndicesNotifier.value = [];
  }

  Future<void> _saveUsersToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final usersJson = usersNotifier.value.map((user) => jsonEncode(user.toJson())).toList();
    await prefs.setStringList('users', usersJson);
  }

  Future<void> registerUser(String name, String imagePath) async {
    final generatedUserId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final newUser = UserProfile(userId: generatedUserId, name: name, imagePath: imagePath);

    final currentList = List<UserProfile>.from(usersNotifier.value);
    currentList.add(newUser);
    usersNotifier.value = currentList;
    await _saveUsersToLocal();

    if (_sendDataFunc != null) {
      _sendDataFunc!({
        'action': 'user_register',
        'user_id': generatedUserId,
        'name': name,
        'image_base64': "mock_base64", // 실제 구현 시 ImageHelper 사용
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> deleteUser(int index) async {
    if (index < 0 || index >= usersNotifier.value.length) return;

    final currentList = List<UserProfile>.from(usersNotifier.value);
    currentList.removeAt(index);
    usersNotifier.value = currentList;

    // 선택 인덱스 재조정
    final currentSelected = List<int>.from(selectedIndicesNotifier.value);
    currentSelected.remove(index);
    // 삭제된 인덱스보다 큰 인덱스들은 1씩 감소
    for(int i=0; i<currentSelected.length; i++) {
      if(currentSelected[i] > index) currentSelected[i] -= 1;
    }
    selectedIndicesNotifier.value = currentSelected;

    await _saveUsersToLocal();
    sendUserSelection();
  }

  // [수정됨] 반환값 추가 (UI에서 스낵바 띄우기 위함)
  bool toggleUserSelection(int index) {
    final currentSelected = List<int>.from(selectedIndicesNotifier.value);

    if (currentSelected.contains(index)) {
      currentSelected.remove(index);
    } else {
      if (currentSelected.length >= 2) {
        return false; // 최대 2명 초과
      }
      currentSelected.add(index);
    }

    currentSelected.sort();
    selectedIndicesNotifier.value = currentSelected;
    sendUserSelection();
    return true; // 성공
  }

  void sendUserSelection() {
    if (_sendDataFunc == null) return;
    final allUsers = usersNotifier.value;
    final indices = selectedIndicesNotifier.value;

    List<Map<String, dynamic>> selectedUsersPayload = indices.map((idx) {
      final user = allUsers[idx];
      return {
        'user_id': user.userId,
        'name': user.name,
        'role': indices.indexOf(idx) + 1,
      };
    }).toList();

    _sendDataFunc!({
      'action': 'user_select',
      'users': selectedUsersPayload,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  String getSelectedUsersText() {
    final indices = selectedIndicesNotifier.value;
    final users = usersNotifier.value;

    if (indices.isEmpty) return "대기 중 (사용자 미선택)";

    final names = indices.map((idx) => users[idx].name).join(", ");
    return "$names 님 추적 중";
  }

  bool isUserSelected(int index) {
    return selectedIndicesNotifier.value.contains(index);
  }
}

// ===============================================================
// [Constants & Theme]
// ===============================================================
const Color kColorCyan = Color(0xFF06B6D4);
const Color kColorSlate900 = Color(0xFF0F172A);
const Color kColorSlate800 = Color(0xFF1E293B);
const Color kColorSlate500 = Color(0xFF64748B);
const Color kColorSlate200 = Color(0xFFE2E8F0);
const Color kColorBgLight = Color(0xFFF8FAFC);

// ===============================================================
// [Global Widgets]
// ===============================================================
Widget _buildCommonHeader(BuildContext context, String title, {bool isDark = false}) {
  final Color contentColor = isDark ? Colors.white : kColorSlate900;
  return Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        InkWell(
          onTap: () => Navigator.pop(context),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(Icons.arrow_back_ios_new, color: contentColor, size: 22),
          ),
        ),
        const SizedBox(width: 10),
        Transform.translate(
          offset: const Offset(0, -1),
          child: Text(
            title,
            style: TextStyle(
              color: contentColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
      ],
    ),
  );
}

Route _createRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      const begin = Offset(1.0, 0.0);
      const end = Offset.zero;
      const curve = Curves.easeOutCubic;
      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

class FanState {
  bool isOn;
  int speed;
  String mode;
  bool oscillation;
  bool timerOn;
  double pan;
  double tilt;

  FanState({
    this.isOn = false,
    this.speed = 1,
    this.mode = 'normal',
    this.oscillation = false,
    this.timerOn = false,
    this.pan = 0.0,
    this.tilt = 0.0,
  });
}

// ===============================================================
// [Main App]
// ===============================================================
class AmbientNodeApp extends StatelessWidget {
  const AmbientNodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = Theme.of(context).textTheme;
    final customTextTheme = GoogleFonts.notoSansKrTextTheme(baseTextTheme).copyWith(
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(letterSpacing: -0.3, fontWeight: FontWeight.w500),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(letterSpacing: -0.3, fontWeight: FontWeight.w500),
      titleLarge: baseTextTheme.titleLarge?.copyWith(letterSpacing: -0.3, fontWeight: FontWeight.w700),
    ).apply(bodyColor: kColorSlate900, displayColor: kColorSlate900);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ambient Node',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(seedColor: kColorCyan, background: Colors.white),
        textTheme: customTextTheme,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.white, elevation: 0),
      ),
      home: const SplashScreen(),
    );
  }
}

// ===============================================================
// [Splash Screen]
// ===============================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _widthAnimation;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 2500), vsync: this);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)));
    _widthAnimation = Tween<double>(begin: 0.0, end: 40.0).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.3, 0.8, curve: Curves.easeOut)));
    _controller.forward();
    Timer(const Duration(seconds: 4), () {
      Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (_, __, ___) => const HomeScreen(), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c), transitionDuration: const Duration(milliseconds: 1000)));
    });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(alignment: Alignment.center, children: [
        Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, color: kColorCyan.withOpacity(0.1), boxShadow: [BoxShadow(color: kColorCyan.withOpacity(0.2), blurRadius: 60, spreadRadius: 20)])),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          FadeTransition(opacity: _fadeAnimation, child: RichText(text: const TextSpan(style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300, color: kColorSlate800, letterSpacing: 4), children: [TextSpan(text: 'ambient '), TextSpan(text: 'node', style: TextStyle(fontWeight: FontWeight.bold, color: kColorCyan))]))),
          const SizedBox(height: 20), AnimatedBuilder(animation: _widthAnimation, builder: (context, child) => Container(height: 1, width: _widthAnimation.value, color: kColorSlate200)),
          const SizedBox(height: 16), FadeTransition(opacity: _fadeAnimation, child: const Text('AIR CONTROL SYSTEM', style: TextStyle(fontSize: 10, letterSpacing: 3, color: kColorSlate500))),
        ]),
      ]),
    );
  }
}

// ===============================================================
// [Home Screen] - Connected with UserService
// ===============================================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  FanState fanState = FanState();
  late AnimationController _bladeController;
  late AnimationController _swingController;

  // UserService 인스턴스
  final _userService = UserService();

  @override
  void initState() {
    super.initState();
    _bladeController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _swingController = AnimationController(vsync: this, duration: const Duration(seconds: 6));
  }

  @override
  void dispose() {
    _bladeController.dispose();
    _swingController.dispose();
    super.dispose();
  }

  void _updateState() {
    setState(() {
      if (fanState.isOn) {
        double speedFactor = 1.0 - (fanState.speed * 0.14);
        double duration = fanState.mode == 'sleep' ? 1.5 : speedFactor;
        _bladeController.duration = Duration(milliseconds: (duration * 1000).toInt());
        if (!_bladeController.isAnimating) _bladeController.repeat();
        if (fanState.oscillation && !_swingController.isAnimating) { _swingController.repeat(reverse: true); } else if (!fanState.oscillation && _swingController.isAnimating) { _swingController.stop(); }
      } else { _bladeController.stop(); _swingController.stop(); }
    });
  }

  // [Bottom Sheet] UserService 데이터 연동
  void _showUserSelectSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return ValueListenableBuilder<List<UserProfile>>(
            valueListenable: _userService.usersNotifier,
            builder: (context, users, child) {
              // 선택 상태 구독 (내부에서)
              return ValueListenableBuilder<List<int>>(
                  valueListenable: _userService.selectedIndicesNotifier,
                  builder: (context, selectedIndices, child) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("추적 대상 선택 (최대 2명)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                                },
                                child: const Text("관리", style: TextStyle(color: kColorSlate500)),
                              )
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (users.isEmpty)
                            Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text("등록된 사용자가 없습니다.\n'관리'를 눌러 추가해주세요.", textAlign: TextAlign.center, style: TextStyle(color: kColorSlate500))))
                          else
                            SizedBox(
                              height: 110,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: users.length,
                                separatorBuilder: (c, i) => const SizedBox(width: 20),
                                itemBuilder: (context, index) {
                                  final user = users[index];
                                  final bool isSelected = selectedIndices.contains(index);

                                  return GestureDetector(
                                    onTap: () {
                                      bool success = _userService.toggleUserSelection(index);
                                      if (!success) {
                                        // Toast나 간단한 피드백 (생략 가능)
                                      }
                                    },
                                    child: Column(
                                      children: [
                                        Stack(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(4),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(color: isSelected ? kColorCyan : Colors.transparent, width: 3),
                                              ),
                                              child: CircleAvatar(
                                                radius: 30,
                                                backgroundColor: kColorBgLight,
                                                backgroundImage: File(user.imagePath).existsSync() ? FileImage(File(user.imagePath)) : null,
                                                child: !File(user.imagePath).existsSync() ? const Icon(Icons.face, color: kColorSlate500) : null,
                                              ),
                                            ),
                                            if (isSelected)
                                              Positioned(right: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: kColorCyan, shape: BoxShape.circle), child: const Icon(Icons.check, size: 12, color: Colors.white)))
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(user.name, style: TextStyle(fontSize: 13, color: isSelected ? kColorCyan : kColorSlate900, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    );
                  }
              );
            }
        );
      },
    );
  }

  void _showMenu(BuildContext context) {
    showGeneralDialog(
      context: context, barrierDismissible: true, barrierLabel: "Menu", barrierColor: Colors.black.withOpacity(0.5), transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(alignment: Alignment.centerRight, child: Material(color: Colors.transparent, child: Container(width: MediaQuery.of(context).size.width * 0.65, height: double.infinity, decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(topLeft: Radius.circular(0))), padding: const EdgeInsets.fromLTRB(32, 60, 32, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Transform.translate(offset: const Offset(0, -1.5), child: const Text('Menu', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kColorSlate900, letterSpacing: -0.5))), GestureDetector(onTap: () => Navigator.pop(ctx), child: Container(width: 40, height: 40, decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle), child: const Icon(Icons.close, color: kColorSlate900, size: 20)))]),
          const SizedBox(height: 60),
          Expanded(child: Column(children: [
            _buildCustomMenuItem(icon: Icons.bluetooth, text: '기기 연결', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeviceScanScreen()))),
            _buildCustomMenuItem(icon: Icons.person_outline_rounded, text: '사용자 관리', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()))),
            _buildCustomMenuItem(icon: Icons.phone_iphone_rounded, text: '리모콘', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RemoteScreen(fanState: fanState, onUpdate: (newState) { setState(() { fanState = newState; }); })))),
            _buildCustomMenuItem(icon: Icons.bar_chart_rounded, text: '사용 분석', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsScreen()))),
            _buildCustomMenuItem(icon: Icons.settings_outlined, text: '설정', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          ])),
        ]))));
      },
      transitionBuilder: (ctx, anim1, anim2, child) => SlideTransition(position: Tween(begin: const Offset(1, 0), end: const Offset(0, 0)).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)), child: child),
    );
  }
  Widget _buildCustomMenuItem({required IconData icon, required String text, required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.translucent, child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Row(children: [Icon(icon, color: kColorSlate500, size: 24), const SizedBox(width: 24), Transform.translate(offset: const Offset(0, -2.0), child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: kColorSlate800, height: 1.0)))])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedContainer(duration: const Duration(seconds: 1), decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: fanState.isOn ? [const Color(0xFFEFF6FF), const Color(0xFFCFFAFE)] : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)])),
        child: SafeArea(child: Column(children: [
          Padding(padding: const EdgeInsets.all(24.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('AMBIENT', style: TextStyle(fontSize: 12, letterSpacing: 2, color: kColorSlate500)), Row(children: const [Text('NODE', style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold, color: kColorCyan))])]), IconButton(icon: const Icon(Icons.menu, color: kColorSlate500), onPressed: () => _showMenu(context))])),

          // Main Visual Area
          Expanded(child: Stack(alignment: Alignment.topCenter, children: [
            Fan3DVisual(fanState: fanState, bladeAnimation: _bladeController, swingAnimation: _swingController),

            // [Pill UI] UserService 상태 구독
            AnimatedOpacity(
              opacity: fanState.isOn ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: Positioned(
                top: 40,
                child: ValueListenableBuilder<List<int>>(
                    valueListenable: _userService.selectedIndicesNotifier,
                    builder: (context, selectedIndices, child) {
                      final statusText = _userService.getSelectedUsersText();
                      final isTracking = selectedIndices.isNotEmpty;

                      return GestureDetector(
                        onTap: _showUserSelectSheet,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: [BoxShadow(color: kColorCyan.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 4))],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8, height: 8,
                                decoration: BoxDecoration(shape: BoxShape.circle, color: isTracking ? kColorCyan : kColorSlate500, boxShadow: isTracking ? [BoxShadow(color: kColorCyan.withOpacity(0.5), blurRadius: 6, spreadRadius: 2)] : []),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(statusText, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kColorSlate900), overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down, size: 18, color: kColorSlate500),
                            ],
                          ),
                        ),
                      );
                    }
                ),
              ),
            ),
          ])),

          SizedBox(height: 60, child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: Text(fanState.isOn ? (fanState.mode == 'sleep' ? '수면풍' : '풍속 ${fanState.speed}') : '대기 모드', key: ValueKey(fanState.isOn ? fanState.mode + fanState.speed.toString() : 'off'), style: const TextStyle(fontFamily: 'Sen', fontSize: 25, fontWeight: FontWeight.w300, color: kColorSlate800)))),
          const SizedBox(height: 20),

          // Controls
          ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(40)), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: Container(color: Colors.white.withOpacity(0.7), padding: const EdgeInsets.fromLTRB(32, 32, 32, 40), child: Column(children: [
            Opacity(opacity: fanState.isOn ? 1.0 : 0.3, child: Container(height: 60, decoration: BoxDecoration(color: kColorSlate200.withOpacity(0.5), borderRadius: BorderRadius.circular(30)), child: Row(children: List.generate(5, (index) { int s = index + 1; return Expanded(child: GestureDetector(onTap: () { if (fanState.isOn) { fanState.speed = s; _updateState(); } }, child: Container(color: Colors.transparent, child: Center(child: AnimatedContainer(duration: const Duration(milliseconds: 300), width: fanState.speed == s ? 14 : 8, height: fanState.speed == s ? 14 : 8, decoration: BoxDecoration(shape: BoxShape.circle, color: fanState.speed == s ? kColorCyan : kColorSlate500.withOpacity(0.3), boxShadow: fanState.speed == s ? [const BoxShadow(color: kColorCyan, blurRadius: 10)] : [])))))); })))),
            const SizedBox(height: 30),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _buildCircleBtn(Icons.timer_outlined, '타이머', active: fanState.timerOn, onTap: () { fanState.timerOn = !fanState.timerOn; _updateState(); }),
              _buildCircleBtn(Icons.sync, '회전', active: fanState.oscillation, onTap: () { fanState.oscillation = !fanState.oscillation; _updateState(); }),
              _buildCircleBtn(Icons.nights_stay, '수면풍', active: fanState.mode == 'sleep', onTap: () { fanState.mode = fanState.mode == 'sleep' ? 'normal' : 'sleep'; _updateState(); }),
              _buildCircleBtn(Icons.gamepad, '리모콘', active: false, isRemote: true, onTap: () { Navigator.push(context, MaterialPageRoute(builder: (_) => RemoteScreen(fanState: fanState, onUpdate: (newState) { setState(() { fanState = newState; }); }))); }),
            ]),
            const SizedBox(height: 30),
            GestureDetector(onTap: () { fanState.isOn = !fanState.isOn; _updateState(); }, child: AnimatedContainer(duration: const Duration(milliseconds: 500), width: double.infinity, height: 60, decoration: BoxDecoration(gradient: fanState.isOn ? const LinearGradient(colors: [kColorCyan, Color(0xFF3B82F6)]) : const LinearGradient(colors: [kColorSlate800, kColorSlate900]), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: fanState.isOn ? kColorCyan.withOpacity(0.4) : Colors.black12, blurRadius: 20, offset: const Offset(0, 10))]), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.power_settings_new, color: Colors.white), const SizedBox(width: 8), Text(fanState.isOn ? '전원 끄기' : '전원 켜기', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]))),
          ])))),
        ])),
      ),
    );
  }
  Widget _buildCircleBtn(IconData icon, String label, {bool active = false, VoidCallback? onTap, bool isRemote = false}) {
    return GestureDetector(onTap: fanState.isOn ? onTap : null, child: Opacity(opacity: fanState.isOn ? 1.0 : 0.5, child: Column(children: [AnimatedContainer(duration: const Duration(milliseconds: 200), width: 56, height: 56, decoration: BoxDecoration(color: active ? kColorCyan.withOpacity(0.1) : (isRemote ? kColorSlate200.withOpacity(0.5) : kColorBgLight), borderRadius: BorderRadius.circular(18), border: Border.all(color: active ? kColorCyan : Colors.transparent, width: 2)), child: Icon(icon, color: active ? kColorCyan : kColorSlate500, size: 24)), const SizedBox(height: 8), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kColorSlate500))])));
  }
}

// ===============================================================
// [User Management Screen] - Connected with UserService
// ===============================================================
class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userService = UserService();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildCommonHeader(context, '사용자 관리'),

            // 상태 바 (활성 인원 표시)
            ValueListenableBuilder<List<int>>(
                valueListenable: userService.selectedIndicesNotifier,
                builder: (context, selectedIndices, child) {
                  return ValueListenableBuilder<List<UserProfile>>(
                      valueListenable: userService.usersNotifier,
                      builder: (context, users, child) {
                        return Container(
                          width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [const Icon(Icons.info_outline, color: Color(0xFF1565C0), size: 20), const SizedBox(width: 10), Expanded(child: Transform.translate(offset: const Offset(0, -1), child: RichText(text: TextSpan(style: const TextStyle(color: Color(0xFF1565C0), fontSize: 14), children: [const TextSpan(text: "현재 "), TextSpan(text: "${selectedIndices.length}", style: const TextStyle(fontWeight: FontWeight.bold)), const TextSpan(text: "명이 선택되었습니다. (전체 "), TextSpan(text: "${users.length}", style: const TextStyle(fontWeight: FontWeight.w500)), const TextSpan(text: "명)")]))))]),
                        );
                      }
                  );
                }
            ),

            // 사용자 리스트
            Expanded(
              child: ValueListenableBuilder<List<UserProfile>>(
                valueListenable: userService.usersNotifier,
                builder: (context, users, child) {
                  if (users.isEmpty) return _buildEmptyState();

                  return ValueListenableBuilder<List<int>>(
                      valueListenable: userService.selectedIndicesNotifier,
                      builder: (context, selectedIndices, _) {
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          itemCount: users.length,
                          separatorBuilder: (c, i) => const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final user = users[index];
                            final isActive = selectedIndices.contains(index);
                            return _userTile(context, user, index, isActive, userService);
                          },
                        );
                      }
                  );
                },
              ),
            ),

            // 추가 버튼
            Padding(padding: const EdgeInsets.all(24), child: SizedBox(width: double.infinity, height: 56, child: ElevatedButton(onPressed: () async { final newUser = await Navigator.push(context, MaterialPageRoute(builder: (context) => const AddUserScreen())); if (newUser != null && newUser is UserProfile) { userService.registerUser(newUser.name, newUser.imagePath); } }, style: ElevatedButton.styleFrom(backgroundColor: kColorCyan, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text("사용자 추가", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))))
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 120, height: 120, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: kColorSlate200.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 10))]), child: const Center(child: Icon(Icons.person_add_alt_1_rounded, size: 48, color: kColorCyan))), const SizedBox(height: 32), const Text("등록된 사용자가 없습니다", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kColorSlate900)), const SizedBox(height: 12), const Text("나와 가족을 등록하여\nAI 맞춤형 바람을 경험해보세요.", textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: kColorSlate500, height: 1.5)), const SizedBox(height: 60)]));
  }

  Widget _userTile(BuildContext context, UserProfile user, int index, bool isActive, UserService service) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: isActive ? kColorCyan.withOpacity(0.3) : Colors.grey.shade200, width: isActive ? 1.5 : 1), boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.05), blurRadius: 10)]),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: const BoxDecoration(shape: BoxShape.circle, color: kColorBgLight), child: ClipOval(child: File(user.imagePath).existsSync() ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: Image.file(File(user.imagePath), fit: BoxFit.cover)) : const Icon(Icons.face, color: kColorSlate500))),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Transform.translate(offset: const Offset(0, -1), child: Text(user.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))), const SizedBox(height: 4), Text(isActive ? "활성" : "비활성", style: TextStyle(fontSize: 12, color: isActive ? kColorCyan : Colors.grey, fontWeight: isActive ? FontWeight.bold : FontWeight.normal))]),
        const Spacer(),
        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey), onPressed: () => service.deleteUser(index)),
        Switch(value: isActive, onChanged: (v) {
          bool success = service.toggleUserSelection(index);
          if (!success) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("제어는 최대 2명까지만 선택할 수 있습니다."), backgroundColor: kColorSlate800, duration: Duration(seconds: 2))); }
        }, activeColor: kColorCyan)
      ]),
    );
  }
}

// --- Add User Screen (Fixed Return Type) ---
class AddUserScreen extends StatefulWidget { const AddUserScreen({super.key}); @override State<AddUserScreen> createState() => _AddUserScreenState(); }
class _AddUserScreenState extends State<AddUserScreen> {
  CameraController? _controller; String? _capturedImagePath; final TextEditingController _nameController = TextEditingController();
  @override void initState() { super.initState(); _initCamera(); }
  Future<void> _initCamera() async { if (_cameras.isEmpty) { try { _cameras = await availableCameras(); } catch (_) {} } if (_cameras.isEmpty) return; final frontCamera = _cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => _cameras.first); _controller = CameraController(frontCamera, ResolutionPreset.high, enableAudio: false, imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888); try { await _controller!.initialize(); if (mounted) setState(() {}); } catch (_) {} }
  @override void dispose() { _controller?.dispose(); _nameController.dispose(); super.dispose(); }
  Future<void> _takePicture() async { if (_controller == null || !_controller!.value.isInitialized || _controller!.value.isTakingPicture) return; try { final image = await _controller!.takePicture(); if (mounted) setState(() { _capturedImagePath = image.path; }); } catch (_) {} }
  void _register() {
    if (_nameController.text.isEmpty) return;
    // [중요] UserProfile 형태로 반환하도록 수정 (UserService와 통일)
    final newUser = UserProfile(userId: DateTime.now().toString(), name: _nameController.text, imagePath: _capturedImagePath ?? "");
    Navigator.pop(context, newUser);
  }
  @override Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(backgroundColor: Colors.white, resizeToAvoidBottomInset: true, body: Stack(fit: StackFit.expand, children: [
      if (_controller != null && _controller!.value.isInitialized) SizedBox.expand(child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _controller!.value.previewSize!.height, height: _controller!.value.previewSize!.width, child: _capturedImagePath != null ? Transform(alignment: Alignment.center, transform: Matrix4.rotationY(math.pi), child: Image.file(File(_capturedImagePath!), fit: BoxFit.cover)) : CameraPreview(_controller!)))) else const Center(child: CircularProgressIndicator(color: kColorCyan)),
      if (_capturedImagePath == null) CustomPaint(size: size, painter: FaceOverlayPainter()),
      Positioned(top: 50, left: 20, child: CircleAvatar(backgroundColor: Colors.black.withOpacity(0.3), child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)))),
      Align(alignment: Alignment.bottomCenter, child: AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: _capturedImagePath == null ? Padding(padding: const EdgeInsets.only(bottom: 60), child: Column(mainAxisSize: MainAxisSize.min, children: [const Text("얼굴을 가이드 라인에 맞춰주세요", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black45, blurRadius: 4)])), const SizedBox(height: 30), GestureDetector(onTap: _takePicture, child: Container(width: 80, height: 80, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.2), border: Border.all(color: Colors.white, width: 4)), child: Center(child: Container(width: 64, height: 64, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white))))) ])) : Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(24, 30, 24, 40), decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: const BorderRadius.vertical(top: Radius.circular(30)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, -5))]), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("사용자 등록", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kColorSlate900)), const SizedBox(height: 20), TextField(controller: _nameController, style: const TextStyle(color: kColorSlate900), decoration: InputDecoration(prefixIcon: const Icon(Icons.person_outline, color: kColorSlate500), hintText: "이름을 입력하세요", hintStyle: const TextStyle(color: kColorSlate500), filled: true, fillColor: kColorBgLight, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(vertical: 16))), const SizedBox(height: 30), Row(children: [Expanded(child: TextButton(onPressed: () => setState(() => _capturedImagePath = null), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text("재촬영", style: TextStyle(color: kColorSlate500, fontSize: 16, fontWeight: FontWeight.w600)))), const SizedBox(width: 16), Expanded(flex: 2, child: ElevatedButton(onPressed: _register, style: ElevatedButton.styleFrom(backgroundColor: kColorCyan, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.symmetric(vertical: 16)), child: const Text("등록 완료", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))))])]))))
    ]));
  }
}
// [Painters & Other Screens remain same...]
class FaceOverlayPainter extends CustomPainter { @override void paint(Canvas canvas, Size size) { final Paint backgroundPaint = Paint()..color = Colors.black.withOpacity(0.3); final double faceWidth = size.width * 0.75; final double faceHeight = faceWidth * 1.3; final Rect faceRect = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.45), width: faceWidth, height: faceHeight); final Path backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)); final Path facePath = Path()..addOval(faceRect); final Path overlayPath = Path.combine(PathOperation.difference, backgroundPath, facePath); canvas.drawPath(overlayPath, backgroundPaint); final Paint borderPaint = Paint()..color = kColorCyan.withOpacity(0.8)..style = PaintingStyle.stroke..strokeWidth = 4.0; canvas.drawOval(faceRect, borderPaint); final Paint dotPaint = Paint()..color = Colors.white; canvas.drawCircle(Offset(size.width / 2, faceRect.top - 15), 4, dotPaint); } @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false; }