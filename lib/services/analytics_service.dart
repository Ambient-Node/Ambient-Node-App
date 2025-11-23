import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_analytics.dart';

/// 사용자 분석 데이터를 관리하는 서비스
class AnalyticsService {
  static const String _analyticsKey = 'user_analytics';

  // 현재 활성 세션들
  static FanSession? _currentFanSession;
  static FaceTrackingSession? _currentFaceTrackingSession;
  static String? _currentUser;

  /// 사용자별 분석 데이터 불러오기
  static Future<Map<String, UserAnalytics>> loadAllAnalytics() async {
    final prefs = await SharedPreferences.getInstance();
    final analyticsJson = prefs.getString(_analyticsKey);

    if (analyticsJson == null) return {};

    final Map<String, dynamic> data = jsonDecode(analyticsJson);
    return data.map((key, value) => MapEntry(
          key,
          UserAnalytics.fromJson(value as Map<String, dynamic>),
        ));
  }

  /// 특정 사용자 분석 데이터 불러오기
  static Future<UserAnalytics?> getUserAnalytics(String username) async {
    final allAnalytics = await loadAllAnalytics();
    return allAnalytics[username];
  }

  /// 분석 데이터 저장
  static Future<void> saveAnalytics(
      Map<String, UserAnalytics> analytics) async {
    final prefs = await SharedPreferences.getInstance();
    final analyticsJson = jsonEncode(analytics.map(
      (key, value) => MapEntry(key, value.toJson()),
    ));
    await prefs.setString(_analyticsKey, analyticsJson);
  }

  /// 사용자 변경 시 이전 세션 종료 및 새 사용자 설정
  static void onUserChanged(String? newUser) {
    // 이전 사용자의 세션 종료 (비동기로 처리하되 결과를 기다리지 않음)
    if (_currentUser != null) {
      _endCurrentFanSession().catchError((e) {
        print('❌ _endCurrentFanSession 오류: $e');
      });
      _endCurrentFaceTrackingSession().catchError((e) {
        print('❌ _endCurrentFaceTrackingSession 오류: $e');
      });
    }

    _currentUser = newUser;
    print('👤 사용자 변경됨: $newUser');
  }

  /// 선풍기 전원 켜짐 (속도 > 0)
  static Future<void> onFanPowerOn(int speed) async {
    if (_currentUser == null) return;

    // 이미 세션이 있으면 종료
    await _endCurrentFanSession();

    // 새 세션 시작
    _currentFanSession = FanSession(
      startTime: DateTime.now(),
      endTime: DateTime.now(), // 임시로 현재 시간 설정
      speed: speed,
    );
  }

  /// 선풍기 전원 꺼짐 (속도 = 0)
  static Future<void> onFanPowerOff() async {
    await _endCurrentFanSession();
  }

  /// 속도 변경
  static void onSpeedChanged(int newSpeed) {
    if (_currentUser == null) return;

    if (newSpeed > 0) {
      // 속도가 있으면 세션 시작 또는 업데이트
      if (_currentFanSession == null) {
        onFanPowerOn(newSpeed).catchError((e) {
          print('❌ onFanPowerOn 오류: $e');
        });
      } else {
        // 현재 세션의 속도 업데이트
        _currentFanSession = FanSession(
          startTime: _currentFanSession!.startTime,
          endTime: DateTime.now(),
          speed: newSpeed,
        );
      }
    } else {
      // 속도가 0이면 세션 종료
      onFanPowerOff().catchError((e) {
        print('❌ onFanPowerOff 오류: $e');
      });
    }
  }

  /// 수동 제어 기록
  static void onManualControl(String direction, int? speed) {
    if (_currentUser == null) return;

    final control = ManualControl(
      timestamp: DateTime.now(),
      direction: direction,
      speed: speed,
    );

    // 비동기로 처리하되 결과를 기다리지 않음
    getUserAnalytics(_currentUser!).then((analytics) {
      final userAnalytics = analytics ?? UserAnalytics(username: _currentUser!);
      final updatedAnalytics = userAnalytics.copyWith(
        manualControls: [...userAnalytics.manualControls, control],
      );
      return _updateUserAnalytics(updatedAnalytics);
    }).catchError((e) {
      print('❌ onManualControl 오류: $e');
    });
  }

  /// 얼굴 추적 시작
  static void onFaceTrackingStart() {
    if (_currentUser == null) return;

    _endCurrentFaceTrackingSession().catchError((e) {
      print('❌ _endCurrentFaceTrackingSession 오류: $e');
    });

    _currentFaceTrackingSession = FaceTrackingSession(
      startTime: DateTime.now(),
      endTime: DateTime.now(),
    );
  }

  /// 얼굴 추적 종료
  static void onFaceTrackingStop() {
    _endCurrentFaceTrackingSession().catchError((e) {
      print('❌ _endCurrentFaceTrackingSession 오류: $e');
    });
  }

  /// 현재 팬 세션 종료
  static Future<void> _endCurrentFanSession() async {
    if (_currentUser == null || _currentFanSession == null) return;

    final session = FanSession(
      startTime: _currentFanSession!.startTime,
      endTime: DateTime.now(),
      speed: _currentFanSession!.speed,
    );

    final analytics = await getUserAnalytics(_currentUser!) ??
        UserAnalytics(username: _currentUser!);

    // 속도별 사용 횟수 업데이트
    final speedCount = Map<int, int>.from(analytics.speedUsageCount);
    speedCount[session.speed] = (speedCount[session.speed] ?? 0) + 1;

    final updatedAnalytics = analytics.copyWith(
      fanSessions: [...analytics.fanSessions, session],
      speedUsageCount: speedCount,
    );

    await _updateUserAnalytics(updatedAnalytics);
    _currentFanSession = null;
  }

  /// 현재 얼굴 추적 세션 종료
  static Future<void> _endCurrentFaceTrackingSession() async {
    if (_currentUser == null || _currentFaceTrackingSession == null) return;

    final session = FaceTrackingSession(
      startTime: _currentFaceTrackingSession!.startTime,
      endTime: DateTime.now(),
    );

    final analytics = await getUserAnalytics(_currentUser!) ??
        UserAnalytics(username: _currentUser!);

    final updatedAnalytics = analytics.copyWith(
      faceTrackingSessions: [...analytics.faceTrackingSessions, session],
    );

    await _updateUserAnalytics(updatedAnalytics);
    _currentFaceTrackingSession = null;
  }

  /// 사용자 분석 데이터 업데이트
  static Future<void> _updateUserAnalytics(UserAnalytics analytics) async {
    final allAnalytics = await loadAllAnalytics();
    allAnalytics[analytics.username] = analytics;
    await saveAnalytics(allAnalytics);
  }

  /// 일간 분석 데이터 생성
  static Future<AnalyticsData> getDailyAnalytics(
      String username, DateTime date) async {
    final analytics = await getUserAnalytics(username);
    if (analytics == null) return _emptyAnalyticsData();

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    // 해당 날짜의 팬 세션들 필터링
    final daySessions = analytics.fanSessions.where((session) {
      return session.startTime.isAfter(startOfDay) &&
          session.startTime.isBefore(endOfDay);
    }).toList();

    // 총 사용 시간 계산
    final totalUsageTime = daySessions.fold<Duration>(
      Duration.zero,
      (sum, session) => sum + session.duration,
    );

    // 속도별 사용 시간 계산
    final speedUsageTime = <int, Duration>{};
    for (final session in daySessions) {
      speedUsageTime[session.speed] =
          (speedUsageTime[session.speed] ?? Duration.zero) + session.duration;
    }

    // 수동 제어 횟수
    final manualControlCount = analytics.manualControls.where((control) {
      return control.timestamp.isAfter(startOfDay) &&
          control.timestamp.isBefore(endOfDay);
    }).length;

    // 얼굴 추적 시간
    final faceTrackingTime = analytics.faceTrackingSessions.where((session) {
      return session.startTime.isAfter(startOfDay) &&
          session.startTime.isBefore(endOfDay);
    }).fold<Duration>(Duration.zero, (sum, session) => sum + session.duration);

    return AnalyticsData(
      totalUsageTime: totalUsageTime,
      speedUsageTime: speedUsageTime,
      manualControlCount: manualControlCount,
      faceTrackingTime: faceTrackingTime,
      dailyUsages: [_createDailyUsage(date, totalUsageTime, speedUsageTime)],
    );
  }

  /// 주간 분석 데이터 생성
  static Future<AnalyticsData> getWeeklyAnalytics(
      String username, DateTime weekStart) async {
    final analytics = await getUserAnalytics(username);
    if (analytics == null) return _emptyAnalyticsData();

    final weekEnd = weekStart.add(const Duration(days: 7));
    final dailyUsages = <DailyUsage>[];

    // 주간의 각 날짜별로 분석
    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final dayData = await getDailyAnalytics(username, date);
      dailyUsages.add(dayData.dailyUsages.first);
    }

    // 주간 총합 계산
    final totalUsageTime = dailyUsages.fold<Duration>(
      Duration.zero,
      (sum, day) => sum + day.usageTime,
    );

    final speedUsageTime = <int, Duration>{};
    for (final day in dailyUsages) {
      for (final entry in day.speedBreakdown.entries) {
        speedUsageTime[entry.key] =
            (speedUsageTime[entry.key] ?? Duration.zero) + entry.value;
      }
    }

    final manualControlCount = analytics.manualControls.where((control) {
      return control.timestamp.isAfter(weekStart) &&
          control.timestamp.isBefore(weekEnd);
    }).length;

    final faceTrackingTime = analytics.faceTrackingSessions.where((session) {
      return session.startTime.isAfter(weekStart) &&
          session.startTime.isBefore(weekEnd);
    }).fold<Duration>(Duration.zero, (sum, session) => sum + session.duration);

    return AnalyticsData(
      totalUsageTime: totalUsageTime,
      speedUsageTime: speedUsageTime,
      manualControlCount: manualControlCount,
      faceTrackingTime: faceTrackingTime,
      dailyUsages: dailyUsages,
    );
  }

  /// 빈 분석 데이터 생성
  static AnalyticsData _emptyAnalyticsData() => AnalyticsData(
        totalUsageTime: Duration.zero,
        speedUsageTime: {},
        manualControlCount: 0,
        faceTrackingTime: Duration.zero,
        dailyUsages: [],
      );

  /// 테스트 데이터 생성 (개발용)
  static Future<void> generateTestData(String username) async {
    print('🧪 generateTestData 시작 - username: $username');
    final now = DateTime.now();
    final testSessions = <FanSession>[];
    final testManualControls = <ManualControl>[];
    final testFaceTrackingSessions = <FaceTrackingSession>[];
    final testSpeedCount = <int, int>{};

    // 최근 7일간의 테스트 데이터 생성
    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: i));

      // 각 날짜마다 2-4개의 선풍기 세션 생성
      final sessionCount = 2 + (i % 3);
      for (int j = 0; j < sessionCount; j++) {
        final startTime =
            DateTime(date.year, date.month, date.day, 9 + j * 3, 0);
        final endTime =
            startTime.add(Duration(hours: 1 + (j % 3), minutes: 30));
        final speed = 1 + (j % 5); // 1-5단계 랜덤

        testSessions.add(FanSession(
          startTime: startTime,
          endTime: endTime,
          speed: speed,
        ));

        // 속도별 사용 횟수 증가
        testSpeedCount[speed] = (testSpeedCount[speed] ?? 0) + 1;
      }

      // 수동 제어 데이터 생성 (각 날짜마다 5-15회)
      final controlCount = 5 + (i % 11);
      for (int k = 0; k < controlCount; k++) {
        final controlTime =
            DateTime(date.year, date.month, date.day, 10 + k, 0);
        final directions = ['up', 'down', 'left', 'right', 'center'];

        testManualControls.add(ManualControl(
          timestamp: controlTime,
          direction: directions[k % directions.length],
          speed: 1 + (k % 5),
        ));
      }

      // 얼굴 추적 세션 생성 (50% 확률로)
      if (i % 2 == 0) {
        final startTime = DateTime(date.year, date.month, date.day, 14, 0);
        final endTime = startTime.add(Duration(hours: 2, minutes: 30));

        testFaceTrackingSessions.add(FaceTrackingSession(
          startTime: startTime,
          endTime: endTime,
        ));
      }
    }

    // 테스트 데이터로 사용자 분석 생성
    final testAnalytics = UserAnalytics(
      username: username,
      fanSessions: testSessions,
      manualControls: testManualControls,
      faceTrackingSessions: testFaceTrackingSessions,
      speedUsageCount: testSpeedCount,
    );

    // 기존 데이터에 추가
    print('💾 데이터 저장 시작...');
    final allAnalytics = await loadAllAnalytics();
    allAnalytics[username] = testAnalytics;
    await saveAnalytics(allAnalytics);
    print('💾 데이터 저장 완료');

    print('🧪 테스트 데이터 생성 완료: $username');
    print('   - 선풍기 세션: ${testSessions.length}개');
    print('   - 수동 제어: ${testManualControls.length}회');
    print('   - 얼굴 추적: ${testFaceTrackingSessions.length}회');
  }

  /// 일별 사용량 생성
  static DailyUsage _createDailyUsage(
      DateTime date, Duration usageTime, Map<int, Duration> speedBreakdown) {
    return DailyUsage(
      date: date,
      usageTime: usageTime,
      speedBreakdown: speedBreakdown,
    );
  }
}
