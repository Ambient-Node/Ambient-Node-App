class UserAnalytics {
  final String username;
  final List<FanSession> fanSessions;
  final List<ManualControl> manualControls;
  final List<FaceTrackingSession> faceTrackingSessions;
  final Map<int, int> speedUsageCount;

  UserAnalytics({
    required this.username,
    this.fanSessions = const [],
    this.manualControls = const [],
    this.faceTrackingSessions = const [],
    this.speedUsageCount = const {},
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'fanSessions': fanSessions.map((s) => s.toJson()).toList(),
    'manualControls': manualControls.map((c) => c.toJson()).toList(),
    'faceTrackingSessions':
    faceTrackingSessions.map((s) => s.toJson()).toList(),
    'speedUsageCount':
    speedUsageCount.map((k, v) => MapEntry(k.toString(), v)),
  };

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

class FanSession {
  final DateTime startTime;
  final DateTime endTime;
  final int speed;
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

class ManualControl {
  final DateTime timestamp;
  final String direction;
  final int? speed;

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

class AnalyticsData {
  final Duration totalUsageTime;
  final Map<int, Duration> speedUsageTime;
  final int manualControlCount;
  final Duration faceTrackingTime;
  final List<DailyUsage> dailyUsages;

  AnalyticsData({
    required this.totalUsageTime,
    required this.speedUsageTime,
    required this.manualControlCount,
    required this.faceTrackingTime,
    required this.dailyUsages,
  });
}

class DailyUsage {
  final DateTime date;
  final Duration usageTime;
  final Map<int, Duration> speedBreakdown;

  DailyUsage({
    required this.date,
    required this.usageTime,
    required this.speedBreakdown,
  });
}
