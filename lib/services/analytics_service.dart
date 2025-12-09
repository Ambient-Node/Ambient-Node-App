import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_analytics.dart';

class AnalyticsService {
  static const String _analyticsKey = 'user_analytics';
  static const String _testModeStatsKey = 'test_mode_stats';
  static const String _testTimerStatsKey = 'test_timer_stats';

  static FanSession? _currentFanSession;
  static FaceTrackingSession? _currentFaceTrackingSession;
  static String? _currentUser;

  // ✨ 테스트용 모드 통계 저장
  static Future<void> saveTestModeStats(String username, Map<String, double> stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_testModeStatsKey}_$username', jsonEncode(stats));
    print('💾 테스트 모드 통계 저장: $stats');
  }

  // ✨ 테스트용 모드 통계 로드
  static Future<Map<String, double>> loadTestModeStats(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('${_testModeStatsKey}_$username');
    if (json == null) return {};

    final Map<String, dynamic> data = jsonDecode(json);
    return data.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  // ✨ 테스트용 타이머 통계 저장
  static Future<void> saveTestTimerStats(String username, int count, double totalMinutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_testTimerStatsKey}_$username', jsonEncode({
      'count': count,
      'total_minutes': totalMinutes,
    }));
    print('💾 테스트 타이머 통계 저장: $count회, ${totalMinutes}분');
  }

  // ✨ 테스트용 타이머 통계 로드
  static Future<Map<String, dynamic>> loadTestTimerStats(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('${_testTimerStatsKey}_$username');
    if (json == null) return {'count': 0, 'total_minutes': 0.0};
    return jsonDecode(json);
  }

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

  static Future<UserAnalytics?> getUserAnalytics(String username) async {
    final allAnalytics = await loadAllAnalytics();
    return allAnalytics[username];
  }

  static Future<void> saveAnalytics(
      Map<String, UserAnalytics> analytics) async {
    final prefs = await SharedPreferences.getInstance();
    final analyticsJson = jsonEncode(analytics.map(
          (key, value) => MapEntry(key, value.toJson()),
    ));
    await prefs.setString(_analyticsKey, analyticsJson);
  }

  static void onUserChanged(String? newUser) {
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

  static Future<void> onFanPowerOn(int speed) async {
    if (_currentUser == null) return;

    await _endCurrentFanSession();

    _currentFanSession = FanSession(
      startTime: DateTime.now(),
      endTime: DateTime.now(),
      speed: speed,
    );
  }

  static Future<void> onFanPowerOff() async {
    await _endCurrentFanSession();
  }

  static void onSpeedChanged(int newSpeed) {
    if (_currentUser == null) return;

    if (newSpeed > 0) {
      if (_currentFanSession == null) {
        onFanPowerOn(newSpeed).catchError((e) {
          print('❌ onFanPowerOn 오류: $e');
        });
      } else {
        _currentFanSession = FanSession(
          startTime: _currentFanSession!.startTime,
          endTime: DateTime.now(),
          speed: newSpeed,
        );
      }
    } else {
      onFanPowerOff().catchError((e) {
        print('❌ onFanPowerOff 오류: $e');
      });
    }
  }

  static void onManualControl(String direction, int? speed) {
    if (_currentUser == null) return;

    final control = ManualControl(
      timestamp: DateTime.now(),
      direction: direction,
      speed: speed,
    );

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

  static void onFaceTrackingStop() {
    _endCurrentFaceTrackingSession().catchError((e) {
      print('❌ _endCurrentFaceTrackingSession 오류: $e');
    });
  }

  static Future<void> _endCurrentFanSession() async {
    if (_currentUser == null || _currentFanSession == null) return;

    final session = FanSession(
      startTime: _currentFanSession!.startTime,
      endTime: DateTime.now(),
      speed: _currentFanSession!.speed,
    );

    final analytics = await getUserAnalytics(_currentUser!) ??
        UserAnalytics(username: _currentUser!);

    final speedCount = Map<int, int>.from(analytics.speedUsageCount);
    speedCount[session.speed] = (speedCount[session.speed] ?? 0) + 1;

    final updatedAnalytics = analytics.copyWith(
      fanSessions: [...analytics.fanSessions, session],
      speedUsageCount: speedCount,
    );

    await _updateUserAnalytics(updatedAnalytics);
    _currentFanSession = null;
  }

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

  static Future<void> _updateUserAnalytics(UserAnalytics analytics) async {
    final allAnalytics = await loadAllAnalytics();
    allAnalytics[analytics.username] = analytics;
    await saveAnalytics(allAnalytics);
  }

  static Future<AnalyticsData> getDailyAnalytics(
      String username, DateTime date) async {
    final analytics = await getUserAnalytics(username);
    if (analytics == null) return _emptyAnalyticsData();

    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final daySessions = analytics.fanSessions.where((session) {
      return session.startTime.isAfter(startOfDay) &&
          session.startTime.isBefore(endOfDay);
    }).toList();

    final totalUsageTime = daySessions.fold<Duration>(
      Duration.zero,
          (sum, session) => sum + session.duration,
    );

    final speedUsageTime = <int, Duration>{};
    for (final session in daySessions) {
      speedUsageTime[session.speed] =
          (speedUsageTime[session.speed] ?? Duration.zero) + session.duration;
    }

    final manualControlCount = analytics.manualControls.where((control) {
      return control.timestamp.isAfter(startOfDay) &&
          control.timestamp.isBefore(endOfDay);
    }).length;

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

  static Future<AnalyticsData> getWeeklyAnalytics(
      String username, DateTime weekStart) async {
    final analytics = await getUserAnalytics(username);
    if (analytics == null) return _emptyAnalyticsData();

    final weekEnd = weekStart.add(const Duration(days: 7));
    final dailyUsages = <DailyUsage>[];

    for (int i = 0; i < 7; i++) {
      final date = weekStart.add(Duration(days: i));
      final dayData = await getDailyAnalytics(username, date);
      dailyUsages.add(dayData.dailyUsages.first);
    }

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

  static AnalyticsData _emptyAnalyticsData() => AnalyticsData(
    totalUsageTime: Duration.zero,
    speedUsageTime: {},
    manualControlCount: 0,
    faceTrackingTime: Duration.zero,
    dailyUsages: [],
  );

  // ✨ 테스트 데이터 생성 - 모든 모드별 데이터 포함
  static Future<void> generateTestData(String username) async {
    print('🧪 generateTestData 시작 - username: $username');
    final now = DateTime.now();
    final testSessions = <FanSession>[];
    final testManualControls = <ManualControl>[];
    final testFaceTrackingSessions = <FaceTrackingSession>[];
    final testSpeedCount = <int, int>{};

    // 최근 7일간 데이터 생성
    for (int i = 0; i < 7; i++) {
      final date = now.subtract(Duration(days: i));
      final sessionCount = 6 + (i % 5);

      for (int j = 0; j < sessionCount; j++) {
        final startTime = DateTime(
          date.year,
          date.month,
          date.day,
          9 + (j * 2),
          (j * 15) % 60,
        );

        final durationHours = 0 + (j % 3);
        final durationMinutes = 30 + (j * 10) % 60;
        final endTime = startTime.add(
            Duration(hours: durationHours, minutes: durationMinutes));

        final speed = 1 + (j % 5);

        testSessions.add(FanSession(
          startTime: startTime,
          endTime: endTime,
          speed: speed,
        ));

        testSpeedCount[speed] = (testSpeedCount[speed] ?? 0) + 1;
      }

      final controlCount = 5 + (i % 11);
      final directions = ['up', 'down', 'left', 'right', 'center'];

      for (int k = 0; k < controlCount; k++) {
        final controlTime = DateTime(
          date.year,
          date.month,
          date.day,
          10 + (k % 12),
          (k * 7) % 60,
        );

        testManualControls.add(ManualControl(
          timestamp: controlTime,
          direction: directions[k % directions.length],
          speed: 1 + (k % 5),
        ));
      }

      if (i % 2 == 0) {
        final trackingCount = 1 + (i % 3);
        for (int t = 0; t < trackingCount; t++) {
          final startTime = DateTime(
            date.year,
            date.month,
            date.day,
            13 + (t * 3),
            0,
          );
          final endTime = startTime.add(
              Duration(hours: 1 + (t % 2), minutes: 20 + (t * 10)));

          testFaceTrackingSessions.add(FaceTrackingSession(
            startTime: startTime,
            endTime: endTime,
          ));
        }
      }
    }

    final testAnalytics = UserAnalytics(
      username: username,
      fanSessions: testSessions,
      manualControls: testManualControls,
      faceTrackingSessions: testFaceTrackingSessions,
      speedUsageCount: testSpeedCount,
    );

    print('💾 데이터 저장 시작...');
    final allAnalytics = await loadAllAnalytics();
    allAnalytics[username] = testAnalytics;
    await saveAnalytics(allAnalytics);

    // ✨ 모드별 & 타이머 테스트 데이터 생성
    final modeStats = {
      'natural_wind': 65.0 + (username.length % 20).toDouble(),
      'ai_tracking': 150.0 + (username.length % 30).toDouble(),
      'rotation': 95.0 + (username.length % 25).toDouble(),
      'manual_control': 75.0 + (username.length % 15).toDouble(),
    };
    await saveTestModeStats(username, modeStats);

    final timerCount = 8 + (username.length % 7);
    final timerTotalMinutes = 240.0 + (username.length % 120).toDouble();
    await saveTestTimerStats(username, timerCount, timerTotalMinutes);

    print('💾 데이터 저장 완료');
    print('✅ 테스트 데이터 생성 완료: $username');
    print('   - 선풍기 세션: ${testSessions.length}개');
    print('   - 수동 제어: ${testManualControls.length}회');
    print('   - 얼굴 추적: ${testFaceTrackingSessions.length}회');
    print('   - 속도별 사용: $testSpeedCount');
    print('   - 모드별 사용: $modeStats');
    print('   - 타이머: ${timerCount}회, ${timerTotalMinutes}분');
  }

  static Future<void> seedAnalyticsForUser(String username) async {
    await generateTestData(username);
  }

  static Future<List<String>> generateInsights(String username,
      {bool weekly = false}) async {
    final analytics = await getUserAnalytics(username);
    if (analytics == null)
      return ['데이터가 없습니다. 먼저 샘플 데이터를 시드하거나 사용 기록이 있어야 합니다.'];

    final now = DateTime.now();
    DateTime? periodStart;
    DateTime? periodEnd;
    if (weekly) {
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      periodStart = DateTime(weekStart.year, weekStart.month, weekStart.day);
      periodEnd = periodStart.add(const Duration(days: 7));
    } else {
      periodStart = DateTime(now.year, now.month, now.day);
      periodEnd = periodStart.add(const Duration(days: 1));
    }

    bool inPeriod(DateTime t) =>
        !t.isBefore(periodStart!) && t.isBefore(periodEnd!);

    final hourCounts = <int, int>{};
    final manualHourCounts = <int, int>{};
    final faceHourCounts = <int, int>{};
    final speedCounts = <int, int>{};
    final directionCounts = <String, int>{};

    void addHourCount(Map<int, int> map, int hour) {
      map[hour] = (map[hour] ?? 0) + 1;
    }

    for (final s in analytics.fanSessions) {
      if (!inPeriod(s.startTime)) continue;
      final start = s.startTime;
      final end = s.endTime.isBefore(periodEnd) ? s.endTime : periodEnd;
      for (var hour = start.hour;; hour = (hour + 1) % 24) {
        addHourCount(hourCounts, hour);
        if (hour == end.hour) break;
      }
      speedCounts[s.speed] = (speedCounts[s.speed] ?? 0) + 1;
    }

    for (final c in analytics.manualControls) {
      if (!inPeriod(c.timestamp)) continue;
      addHourCount(manualHourCounts, c.timestamp.hour);
      directionCounts[c.direction] = (directionCounts[c.direction] ?? 0) + 1;
      if (c.speed != null)
        speedCounts[c.speed!] = (speedCounts[c.speed!] ?? 0) + 1;
    }

    for (final f in analytics.faceTrackingSessions) {
      if (!inPeriod(f.startTime)) continue;
      addHourCount(faceHourCounts, f.startTime.hour);
    }

    int? _topHour(Map<int, int> m) {
      if (m.isEmpty) return null;
      return m.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    T? _topKey<T>(Map<T, int> m) {
      if (m.isEmpty) return null;
      return m.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    }

    final List<String> sentences = [];
    final periodLabel = weekly ? '이번 주' : '오늘';

    final topHour = _topHour(hourCounts);
    if (topHour != null) {
      sentences.add('$periodLabel 주로 ${topHour}시경에 선풍기를 많이 사용하셨네요.');
    }

    final topManualHour = _topHour(manualHourCounts);
    final topDirection = _topKey(directionCounts);
    if (topManualHour != null && topDirection != null) {
      sentences.add(
          '$periodLabel ${topManualHour}시에 수동으로 조작하는 경우가 많고, 주로 "$topDirection" 방향을 사용했어요.');
    } else if (topManualHour != null) {
      sentences.add('$periodLabel ${topManualHour}시에 수동 조작이 많이 발생했네요.');
    }

    final topSpeed = _topKey(speedCounts);
    if (topSpeed != null) {
      sentences.add('$periodLabel 가장 선호하는 풍속은 Lv.$topSpeed!');
    }

    final topFaceHour = _topHour(faceHourCounts);
    if (topFaceHour != null) {
      sentences.add('$periodLabel 얼굴 추적은 ${topFaceHour}시에 활성화되는 경향이 있습니다.');
    }

    if (sentences.isEmpty) sentences.add('분석할 충분한 데이터가 없습니다.');
    return sentences;
  }

  static DailyUsage _createDailyUsage(
      DateTime date, Duration usageTime, Map<int, Duration> speedBreakdown) {
    return DailyUsage(
      date: date,
      usageTime: usageTime,
      speedBreakdown: speedBreakdown,
    );
  }
}
