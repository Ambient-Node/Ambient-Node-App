/// 사용자별 분석 데이터 모델
class UserAnalytics {
  final String username;
  final List<FanSession> fanSessions; // 선풍기 사용 세션들
  final List<ManualControl> manualControls; // 수동 제어 기록들
  final List<FaceTrackingSession> faceTrackingSessions; // 얼굴 추적 세션들
  final Map<int, int> speedUsageCount; // 속도별 사용 횟수 {1: 5, 2: 3, ...}

  UserAnalytics({
    required this.username,
    this.fanSessions = const [],
    this.manualControls = const [],
    this.faceTrackingSessions = const [],
    this.speedUsageCount = const {},
  });

  // JSON 직렬화
  Map<String, dynamic> toJson() => {
        'username': username,
        'fanSessions': fanSessions.map((s) => s.toJson()).toList(),
        'manualControls': manualControls.map((c) => c.toJson()).toList(),
        'faceTrackingSessions':
            faceTrackingSessions.map((s) => s.toJson()).toList(),
        'speedUsageCount':
            speedUsageCount.map((k, v) => MapEntry(k.toString(), v)),
      };

  // JSON 역직렬화
  factory UserAnalytics.fromJson(Map<String, dynamic> json) => UserAnalytics(
        username: json['username'] as String,
        fanSessions: (json['fanSessions'] as List?)
                ?.map((s) => FanSession.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        manualControls: (json['manualControls'] as List?)
                ?.map((c) => ManualControl.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        faceTrackingSessions: (json['faceTrackingSessions'] as List?)
                ?.map((s) =>
                    FaceTrackingSession.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        speedUsageCount: (json['speedUsageCount'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(int.parse(k), v as int)) ??
            {},
      );

  // 복사본 생성 (데이터 추가용)
  UserAnalytics copyWith({
    String? username,
    List<FanSession>? fanSessions,
    List<ManualControl>? manualControls,
    List<FaceTrackingSession>? faceTrackingSessions,
    Map<int, int>? speedUsageCount,
  }) =>
      UserAnalytics(
        username: username ?? this.username,
        fanSessions: fanSessions ?? this.fanSessions,
        manualControls: manualControls ?? this.manualControls,
        faceTrackingSessions: faceTrackingSessions ?? this.faceTrackingSessions,
        speedUsageCount: speedUsageCount ?? this.speedUsageCount,
      );
}

/// 선풍기 사용 세션 (전원 켜짐 ~ 꺼짐)
class FanSession {
  final DateTime startTime;
  final DateTime endTime;
  final int speed; // 사용된 속도 (0이면 전원 OFF)
  final Duration duration;

  FanSession({
    required this.startTime,
    required this.endTime,
    required this.speed,
  }) : duration = endTime.difference(startTime);

  Map<String, dynamic> toJson() => {
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'speed': speed,
      };

  factory FanSession.fromJson(Map<String, dynamic> json) => FanSession(
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
        speed: json['speed'] as int,
      );
}

/// 수동 제어 기록
class ManualControl {
  final DateTime timestamp;
  final String direction; // 'up', 'down', 'left', 'right', 'center'
  final int? speed; // 제어 당시 속도

  ManualControl({
    required this.timestamp,
    required this.direction,
    this.speed,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'direction': direction,
        'speed': speed,
      };

  factory ManualControl.fromJson(Map<String, dynamic> json) => ManualControl(
        timestamp: DateTime.parse(json['timestamp'] as String),
        direction: json['direction'] as String,
        speed: json['speed'] as int?,
      );
}

/// 얼굴 추적 세션
class FaceTrackingSession {
  final DateTime startTime;
  final DateTime endTime;
  final Duration duration;

  FaceTrackingSession({
    required this.startTime,
    required this.endTime,
  }) : duration = endTime.difference(startTime);

  Map<String, dynamic> toJson() => {
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
      };

  factory FaceTrackingSession.fromJson(Map<String, dynamic> json) =>
      FaceTrackingSession(
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: DateTime.parse(json['endTime'] as String),
      );
}

/// 일간/주간 분석 데이터
class AnalyticsData {
  final Duration totalUsageTime; // 총 사용 시간
  final Map<int, Duration>
      speedUsageTime; // 속도별 사용 시간 {1: Duration(minutes: 30), ...}
  final int manualControlCount; // 수동 제어 횟수
  final Duration faceTrackingTime; // 얼굴 추적 사용 시간
  final List<DailyUsage> dailyUsages; // 일별 사용량

  AnalyticsData({
    required this.totalUsageTime,
    required this.speedUsageTime,
    required this.manualControlCount,
    required this.faceTrackingTime,
    required this.dailyUsages,
  });
}

/// 일별 사용량
class DailyUsage {
  final DateTime date;
  final Duration usageTime;
  final Map<int, Duration> speedBreakdown; // 속도별 사용 시간

  DailyUsage({
    required this.date,
    required this.usageTime,
    required this.speedBreakdown,
  });
}
