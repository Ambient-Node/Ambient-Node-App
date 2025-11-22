import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

/// 1. [공통] 서버로부터 받는 통계 응답 껍데기
/// topic: ambient/stats/response
class AnalyticsResponse {
  final String requestId;
  final String type; // 'usage', 'speed_dist', 'mode_ratio', 'pattern', 'user_comparison'
  final String period; // 'day', 'week'
  final dynamic data; // 실제 리스트 데이터 (타입에 따라 다름)
  final DateTime timestamp;
  final String? error;

  AnalyticsResponse({
    required this.requestId,
    required this.type,
    required this.period,
    this.data,
    required this.timestamp,
    this.error,
  });

  factory AnalyticsResponse.fromJson(Map<String, dynamic> json) {
    return AnalyticsResponse(
      requestId: json['request_id'] ?? '',
      type: json['type'] ?? '',
      period: json['period'] ?? 'day',
      data: json['data'],
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      error: json['error'],
    );
  }

  /// 데이터가 에러인지 확인
  bool get hasError => error != null;

  /// 각 타입별로 데이터를 파싱해서 리스트로 반환하는 헬퍼 메서드들

  // 1. 시간대별 사용량 (type: usage)
  List<UsageStatItem> get usageStats {
    if (data is! List) return [];
    return (data as List).map((e) => UsageStatItem.fromJson(e)).toList();
  }

  // 2. 풍속별 분포 (type: speed_dist)
  List<SpeedDistItem> get speedDistStats {
    if (data is! List) return [];
    return (data as List).map((e) => SpeedDistItem.fromJson(e)).toList();
  }

  // 3. 모드 비율 (type: mode_ratio)
  List<ModeRatioItem> get modeRatioStats {
    if (data is! List) return [];
    return (data as List).map((e) => ModeRatioItem.fromJson(e)).toList();
  }

  // 4. 사용 패턴 (type: pattern)
  List<PatternItem> get patternStats {
    if (data is! List) return [];
    return (data as List).map((e) => PatternItem.fromJson(e)).toList();
  }

  // 5. 사용자 비교 (type: user_comparison)
  List<UserCompItem> get userCompStats {
    if (data is! List) return [];
    return (data as List).map((e) => UserCompItem.fromJson(e)).toList();
  }
}

/// ----------------------------------------------------------------
/// 하위 데이터 모델들 (라즈베리파이 DB 쿼리 결과와 1:1 매칭)
/// ----------------------------------------------------------------

/// 1. 시간대별/일별 사용량 데이터 모델
class UsageStatItem {
  final DateTime time; // 'time' (시간별) or 'date' (일별)
  final double minutes;

  UsageStatItem({required this.time, required this.minutes});

  factory UsageStatItem.fromJson(Map<String, dynamic> json) {
    // Python에서 'time' 혹은 'date'로 옴
    String timeStr = json['time'] ?? json['date'] ?? DateTime.now().toString();
    return UsageStatItem(
      time: DateTime.tryParse(timeStr) ?? DateTime.now(),
      minutes: (json['minutes'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// 2. 풍속별 사용 분포 데이터 모델
class SpeedDistItem {
  final int speed;
  final double minutes;

  SpeedDistItem({required this.speed, required this.minutes});

  factory SpeedDistItem.fromJson(Map<String, dynamic> json) {
    return SpeedDistItem(
      speed: json['speed'] as int? ?? 0,
      minutes: (json['minutes'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// 3. 모드(AI/Manual) 비율 데이터 모델
class ModeRatioItem {
  final String mode; // DB에서 오는 원본 값: 'ai' 또는 'manual'
  final double hours; // 누적 사용 시간 (단위: 시간)
  final double percentage; // 전체 중 비율 (0~100)

  ModeRatioItem({
    required this.mode,
    required this.hours,
    required this.percentage,
  });

  factory ModeRatioItem.fromJson(Map<String, dynamic> json) {
    return ModeRatioItem(
      mode: json['mode'] ?? 'unknown',
      hours: (json['hours'] as num?)?.toDouble() ?? 0.0,
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String get displayLabel {
    if (mode == 'ai') return 'AI Tracking';
    if (mode == 'manual') return 'Manual Control';
    return 'Unknown';
  }

  /// 차트에 표시할 색상 (AI는 파랑, 수동은 주황/회색 등)
  Color get displayColor {
    if (mode == 'ai') return const Color(0xFF3A91FF); // Ambient Blue
    if (mode == 'manual') return const Color(0xFFFF9F0A); // Warning Orange or Grey
    return Colors.grey;
  }
}

/// 4. 주간 사용 패턴 (시간대별 빈도) 데이터 모델
class PatternItem {
  final int hour; // 0~23
  final int count; // 세션 수
  final double avgMinutes; // 평균 사용 시간

  PatternItem({
    required this.hour,
    required this.count,
    required this.avgMinutes,
  });

  factory PatternItem.fromJson(Map<String, dynamic> json) {
    return PatternItem(
      hour: json['hour'] as int? ?? 0,
      count: json['count'] as int? ?? 0,
      avgMinutes: (json['avg_minutes'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // 차트 표시용 시간 포맷 (예: 14 -> "14:00")
  String get hourLabel => '${hour.toString().padLeft(2, '0')}:00';
}

/// 5. 사용자별 사용량 비교 데이터 모델
class UserCompItem {
  final String username;
  final DateTime date;
  final double minutes;

  UserCompItem({
    required this.username,
    required this.date,
    required this.minutes,
  });

  factory UserCompItem.fromJson(Map<String, dynamic> json) {
    return UserCompItem(
      username: json['username'] ?? 'Unknown',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      minutes: (json['minutes'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
