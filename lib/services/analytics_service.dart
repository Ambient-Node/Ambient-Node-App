import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user_analytics.dart';

/// 화면에 보여줄 모든 통계 데이터를 모아둔 통합 모델
class DashboardAnalytics {
  final List<UsageStatItem> usageStats;
  final List<SpeedDistItem> speedDistStats;
  final List<ModeRatioItem> modeRatioStats;
  final List<PatternItem> patternStats;
  final List<UserCompItem> userCompStats;
  final DateTime lastUpdated;

  DashboardAnalytics({
    this.usageStats = const [],
    this.speedDistStats = const [],
    this.modeRatioStats = const [],
    this.patternStats = const [],
    this.userCompStats = const [],
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  // 데이터 갱신을 위한 copyWith
  DashboardAnalytics copyWith({
    List<UsageStatItem>? usageStats,
    List<SpeedDistItem>? speedDistStats,
    List<ModeRatioItem>? modeRatioStats,
    List<PatternItem>? patternStats,
    List<UserCompItem>? userCompStats,
  }) {
    return DashboardAnalytics(
      usageStats: usageStats ?? this.usageStats,
      speedDistStats: speedDistStats ?? this.speedDistStats,
      modeRatioStats: modeRatioStats ?? this.modeRatioStats,
      patternStats: patternStats ?? this.patternStats,
      userCompStats: userCompStats ?? this.userCompStats,
      lastUpdated: DateTime.now(),
    );
  }

  // 빈 데이터인지 확인
  bool get isEmpty =>
      usageStats.isEmpty &&
          speedDistStats.isEmpty &&
          modeRatioStats.isEmpty;
}

/// MQTT 통신 및 데이터 관리를 담당하는 서비스
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  // UI에서 구독할 데이터 Notifier
  final ValueNotifier<DashboardAnalytics> dashboardNotifier =
  ValueNotifier(DashboardAnalytics());

  // MQTT 발행 함수 (외부에서 주입받음)
  Function(String topic, Map<String, dynamic> payload)? _publishFunc;

  // 현재 조회 중인 기간 ('day' or 'week')
  String _currentPeriod = 'day';
  String? _currentUserId;

  static const String _cacheKey = 'dashboard_analytics_cache';

  /// 초기화: MQTT 발행 함수 설정 및 캐시 로드
  Future<void> init({
    required Function(String, Map<String, dynamic>) onPublish,
    String? userId
  }) async {
    _publishFunc = onPublish;
    _currentUserId = userId;
    await _loadCache();
  }

  /// 사용자 변경 시
  void setUserId(String? userId) {
    _currentUserId = userId;
    // 사용자 바뀌면 데이터 초기화 후 새로 요청
    dashboardNotifier.value = DashboardAnalytics();
    if (userId != null) {
      requestAllStats(_currentPeriod);
    }
  }

  /// MQTT 메시지 수신 처리 (ambient/stats/response)
  void handleResponse(Map<String, dynamic> payload) {
    try {
      // 1. 서버 응답을 모델로 파싱
      final response = AnalyticsResponse.fromJson(payload);

      // 에러 체크
      if (response.hasError) {
        debugPrint("❌ Analytics Error: ${response.error}");
        return;
      }

      // 기간이 다르면 무시 (예: 주간 데이터 요청했는데 일간 데이터가 늦게 도착한 경우)
      if (response.period != _currentPeriod) return;

      // 2. 타입에 따라 DashboardAnalytics 부분 업데이트
      DashboardAnalytics current = dashboardNotifier.value;
      DashboardAnalytics updated;

      switch (response.type) {
        case 'usage':
          updated = current.copyWith(usageStats: response.usageStats);
          break;
        case 'speed_dist':
          updated = current.copyWith(speedDistStats: response.speedDistStats);
          break;
        case 'mode_ratio':
          updated = current.copyWith(modeRatioStats: response.modeRatioStats);
          break;
        case 'pattern':
          updated = current.copyWith(patternStats: response.patternStats);
          break;
        case 'user_comparison':
          updated = current.copyWith(userCompStats: response.userCompStats);
          break;
        default:
          return; // 모르는 타입
      }

      // 3. 상태 업데이트 및 캐시 저장
      dashboardNotifier.value = updated;
      _saveCache(updated);

      debugPrint("📊 Stats Updated: ${response.type} (${response.period})");

    } catch (e) {
      debugPrint("❌ Failed to parse stats response: $e");
    }
  }

  /// 모든 통계 데이터 요청 (새로고침)
  void requestAllStats(String period) {
    if (_publishFunc == null) return;

    _currentPeriod = period;
    final requestId = const Uuid().v4();
    final timestamp = DateTime.now().toIso8601String();

    // 4가지 핵심 데이터를 각각 요청
    final types = ['usage', 'speed_dist', 'mode_ratio', 'pattern'];

    for (var type in types) {
      final payload = {
        "request_id": requestId,
        "type": type,
        "period": period,
        "user_id": _currentUserId,
        "timestamp": timestamp
      };

      _publishFunc!("ambient/stats/request", payload);
    }
  }

  // --- Local Caching Logic ---

  Future<void> _saveCache(DashboardAnalytics data) async {
    final prefs = await SharedPreferences.getInstance();
    // 간단하게 usageStats만이라도 캐싱하거나, 필요하면 전체 직렬화 구현
    // 여기서는 마지막 업데이트 시간만 저장하는 예시
    await prefs.setString(_cacheKey, DateTime.now().toIso8601String());
  }

  Future<void> _loadCache() async {
    // 실제 프로덕션에서는 DashboardAnalytics 전체를 JSON으로 저장/로드 권장
    // 현재는 앱 재실행 시 초기화 상태로 시작
    dashboardNotifier.value = DashboardAnalytics();
  }
}