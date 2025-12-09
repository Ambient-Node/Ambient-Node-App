import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/user_analytics.dart';
import '../services/analytics_service.dart';
import '../services/ble_service.dart'; // BleService 사용
import 'dart:async';
import '../utils/snackbar_helper.dart';

class AnalyticsScreen extends StatefulWidget {
  final String? selectedUserName;

  const AnalyticsScreen({
    super.key,
    this.selectedUserName,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  bool _isWeekly = false;
  AnalyticsData? _analyticsData;
  List<String>? _insights;

  // 서버 데이터 저장 변수
  Map<String, double> _serverModeStats = {};
  double? _naturalWindMinutes;
  int _timerCount = 0;
  double _timerTotalMinutes = 0.0;

  StreamSubscription<Map<String, dynamic>>? _bleSub;
  bool _isLoading = true;

  static const double cardGap = 16.0;  // 카드 간 간격
  static const double sectionGap = 24.0;  // 섹션 간 간격
  static const double cardPadding = 16.0;  // 카드 내부 패딩
  static const double cardRadius = 20.0;  // 카드 모서리 반경
  static const double smallCardHeight = 120.0;  // 작은 카드 높이

  static const Color primaryBlue = Color(0xFF3A91FF);
  static const Color textDark = Color(0xFF2D3142);
  static const Color textGrey = Color(0xFF9098B1);
  static const Color bgGrey = Color(0xFFF4F6F8);

  final Map<String, Color> _modeColors = {
    'natural_wind': const Color(0xFF4CAF50), // 초록
    'ai_tracking': const Color(0xFF9C27B0),  // 보라
    'rotation': const Color(0xFFFF9800),     // 주황
    'manual_control': const Color(0xFF2196F3), // 파랑
    'unknown': Colors.grey,
  };

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
    _initBleListener();
  }

  void _initBleListener() {
    _bleSub = BleService().dataStream.listen((msg) {
      if (!mounted) return;

      final type = msg['type'];
      final data = msg['data'];

      // 1. 모드 통계 (자연풍 포함)
      if (type == 'mode_usage' && data is List) {
        final stats = <String, double>{};
        double naturalMin = 0.0;

        for (var item in data) {
          if (item is Map) {
            final mode = item['mode']?.toString() ?? 'unknown';
            final minutes = (item['minutes'] is num)
                ? (item['minutes'] as num).toDouble()
                : double.tryParse(item['minutes'].toString()) ?? 0.0;
            stats[mode] = minutes;
            if (mode == 'natural_wind') naturalMin = minutes;
          }
        }

        if (mounted) {
          setState(() {
            _serverModeStats = stats;
            _naturalWindMinutes = naturalMin;
          });
        }
      }

      // 2. 타이머 통계
      if (type == 'timer_count' && data is Map) {
        final count = (data['count'] as num?)?.toInt() ?? 0;
        final totalMin = (data['total_minutes'] as num?)?.toDouble() ?? 0.0;
        if (mounted) {
          setState(() {
            _timerCount = count;
            _timerTotalMinutes = totalMin;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(AnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedUserName != widget.selectedUserName) {
      _loadAnalytics();
    }
  }

  Future<void> _loadAnalytics() async {
    if (widget.selectedUserName == null) {
      if (mounted) {
        setState(() {
          _analyticsData = null;
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final now = DateTime.now();

      // 1. 로컬 데이터 로드 (SharedPreferences)
      final data = _isWeekly
          ? await AnalyticsService.getWeeklyAnalytics(
          widget.selectedUserName!,
          now.subtract(Duration(days: now.weekday - 1)))
          : await AnalyticsService.getDailyAnalytics(widget.selectedUserName!, now);

      // 2. 서버 통계 요청 (BLE → MQTT)
      _requestStatsFromServer('mode_usage');
      _requestStatsFromServer('timer_count');

      // ✨ 3. 테스트 데이터 로드 (로컬에 저장된 데이터)
      final testModeStats = await AnalyticsService.loadTestModeStats(widget.selectedUserName!);
      final testTimerStats = await AnalyticsService.loadTestTimerStats(widget.selectedUserName!);

      // 4. 인사이트 생성
      List<String>? insights;
      try {
        insights = await AnalyticsService.generateInsights(
          widget.selectedUserName!,
          weekly: _isWeekly,
        );
      } catch (_) {
        insights = ['데이터를 분석하고 있어요.'];
      }

      if (mounted) {
        setState(() {
          _analyticsData = data;
          _insights = insights;

          // ✨ 테스트 데이터 먼저 적용 (서버 응답 전까지 표시)
          if (testModeStats.isNotEmpty) {
            _serverModeStats = testModeStats;
            _naturalWindMinutes = testModeStats['natural_wind'];
          }
          if (testTimerStats['count'] > 0) {
            _timerCount = testTimerStats['count'] as int;
            _timerTotalMinutes = (testTimerStats['total_minutes'] as num).toDouble();
          }

          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ _loadAnalytics 오류: $e');
      if (mounted) {
        setState(() {
          _analyticsData = null;
          _isLoading = false;
        });
      }
    }
  }


  void _requestStatsFromServer(String statType) {
    final payload = {
      'action': 'mqtt_publish',
      'topic': 'ambient/stats/request',
      'payload': {
        'request_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'type': statType,
        'period': _isWeekly ? 'week' : 'day',
        'user_id': widget.selectedUserName!
      }
    };

    BleService().sendJson(payload).catchError((e) {
      print('통계 요청 전송 실패: $e');
    });
  }

  // [복구 완료] 테스트 데이터 생성 함수
  Future<void> _seedTestData() async {
    if (widget.selectedUserName == null) return;

    await AnalyticsService.seedAnalyticsForUser(widget.selectedUserName!);
    await _loadAnalytics();

    if (mounted) {
      showAppSnackBar(context, '테스트 데이터가 생성되었습니다!', type: AppSnackType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Row(
                children: [
                  const Text(
                    "인사이트",
                    style: TextStyle(
                      fontFamily: 'Sen',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: textDark,
                    ),
                  ),
                  const Spacer(),
                  _buildSegmentedControl(),
                  const SizedBox(width: 8),

                  // [복구 완료] 번개 아이콘
                  IconButton(
                    tooltip: '테스트 데이터 생성',
                    onPressed: _seedTestData,
                    icon: const Icon(Icons.bolt_rounded, color: Colors.amber),
                  ),

                  // 새로고침 아이콘
                  IconButton(
                    tooltip: '새로고침',
                    onPressed: _loadAnalytics,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: primaryBlue))
                  : widget.selectedUserName == null
                  ? _buildEmptyState()
                  : _analyticsData == null
                  ? _buildEmptyState(hasUser: true)
                  : _buildDashboardContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardContent() {
    final data = _analyticsData!;
    final totalHours = data.totalUsageTime.inHours;
    final totalMinutes = data.totalUsageTime.inMinutes % 60;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 총 사용 시간 카드 (맨 위 큰 카드)
          FadeInSlide(
            delay: 0,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFE3F2FD),
                        child: Text(
                          widget.selectedUserName![0].toUpperCase(),
                          style: const TextStyle(color: primaryBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${widget.selectedUserName!}님,",
                            style: const TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.bold, color: textDark),
                          ),
                          Text(
                            _isWeekly ? "이번 주 리포트입니다." : "오늘도 시원하게 보내셨나요?",
                            style: const TextStyle(fontFamily: 'Sen', fontSize: 13, color: textGrey),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text("총 사용 시간", style: TextStyle(fontFamily: 'Sen', fontSize: 13, fontWeight: FontWeight.w600, color: textGrey)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "$totalHours",
                        style: const TextStyle(fontFamily: 'Sen', fontSize: 48, fontWeight: FontWeight.w800, color: primaryBlue, height: 1.0),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4, right: 12),
                        child: Text("시간", style: TextStyle(fontFamily: 'Sen', fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
                      ),
                      Text(
                        "$totalMinutes",
                        style: const TextStyle(fontFamily: 'Sen', fontSize: 48, fontWeight: FontWeight.w800, color: primaryBlue, height: 1.0),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8, left: 4),
                        child: Text("분", style: TextStyle(fontFamily: 'Sen', fontSize: 20, fontWeight: FontWeight.bold, color: textDark)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 2. 상단 2개 카드 (자동 회전, 타이머) - _buildBentoCard로 통일
          // 2. 상단 2개 카드
          FadeInSlide(
            delay: 100,
            child: SizedBox(
              height: 130, // 120 → 130으로 변경
              child: Row(
                children: [
                  Expanded(
                    child: _buildBentoCard(
                      title: "자동 회전 시간",
                      value: "${(_serverModeStats['rotation'] ?? 0.0).toStringAsFixed(0)}분",
                      icon: Icons.sync_rounded,
                      accentColor: const Color(0xFFFF9800),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildBentoCard(
                      title: "타이머 설정",
                      value: "$_timerCount회",
                      icon: Icons.timer_rounded,
                      accentColor: const Color(0xFFFF9800),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

// 3. 중간 2개 카드
          FadeInSlide(
            delay: 150,
            child: SizedBox(
              height: 130, // 120 → 130으로 변경
              child: Row(
                children: [
                  Expanded(
                    child: _buildBentoCard(
                      title: "직접 조작 횟수",
                      value: "${data.manualControlCount}번",
                      icon: Icons.touch_app_rounded,
                      accentColor: const Color(0xFFFF7F50),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildBentoCard(
                      title: "평균 바람 세기",
                      value: "Lv.${_getAverageSpeed(data)}",
                      icon: Icons.wind_power_rounded,
                      accentColor: const Color(0xFF3A91FF),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

// 4. 하단 2개 카드
          FadeInSlide(
            delay: 200,
            child: SizedBox(
              height: 130, // 120 → 130으로 변경
              child: Row(
                children: [
                  Expanded(
                    child: _buildBentoCard(
                      title: "AI가 따라간 시간",
                      value: "${data.faceTrackingTime.inMinutes}분",
                      icon: Icons.face_retouching_natural_rounded,
                      accentColor: const Color(0xFF00C896),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildBentoCard(
                      title: "자연풍 모드",
                      value: "${(_naturalWindMinutes ?? 0).toStringAsFixed(0)}분",
                      icon: Icons.grass_rounded,
                      accentColor: const Color(0xFF4CAF50),
                    ),
                  ),
                ],
              ),
            ),
          ),


          const SizedBox(height: 24),

          // 5. 인사이트 카드 (Full Width)
          FadeInSlide(
            delay: 250,
            child: _buildInsightCard(_insights),
          ),

          const SizedBox(height: 24),

          // 6. 모드별 점유율 (도넛 차트)
          if (_serverModeStats.isNotEmpty)
            FadeInSlide(
              delay: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("가장 많이 쓴 모드는?", style: TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.w800, color: textDark)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        SizedBox(height: 140, width: 140, child: _buildModeDonutChart()),
                        const SizedBox(width: 24),
                        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: _buildModeLegend())),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 24),

          // 7. 사용 히스토리 (Bar Chart)
          FadeInSlide(
            delay: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("시간별 사용량", style: TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.w800, color: textDark)),
                const SizedBox(height: 16),
                Container(
                  height: 240,
                  padding: const EdgeInsets.fromLTRB(16, 32, 16, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: _buildUsageBarChart(data),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 8. 선호 풍속
          FadeInSlide(
            delay: 500,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("어떤 바람을 좋아하세요?", style: TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.w800, color: textDark)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      SizedBox(height: 140, width: 140, child: _buildCombinedWindChart(data)),
                      const SizedBox(width: 24),
                      Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: _buildCombinedWindLegend(data))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }


  // --- 위젯 빌더 함수들 ---

  Widget _buildRotationStatsCard() {
    double rotationMinutes = _serverModeStats['rotation'] ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E0E0).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min, // 추가
        children: [
          Row(
            children: [
              const Icon(Icons.sync_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 6),
              const Flexible( // Text를 Flexible로 감싸기
                child: Text(
                  "자동 회전",
                  style: TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${rotationMinutes.toStringAsFixed(1)}분",
            style: const TextStyle(
              fontFamily: 'Sen',
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: textDark,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const Flexible( // 추가
            child: Text(
              "넓은 범위를 커버했어요",
              style: TextStyle(
                fontFamily: 'Sen',
                fontSize: 10,
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildTimerStatsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E0E0).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min, // 추가
        children: [
          Row(
            children: [
              const Icon(Icons.timer_rounded, color: Colors.orange, size: 18),
              const SizedBox(width: 6),
              const Flexible( // 추가
                child: Text(
                  "타이머 습관",
                  style: TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "$_timerCount회 설정",
            style: const TextStyle(
              fontFamily: 'Sen',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: textDark,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Flexible( // 추가
            child: Text(
              "총 ${_timerTotalMinutes.toStringAsFixed(0)}분 예약",
              style: const TextStyle(fontFamily: 'Sen', fontSize: 10, color: textGrey),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildNaturalWindCard() {
    double minutes = _naturalWindMinutes ?? 0.0;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E0E0).withOpacity(0.5)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              const Icon(Icons.grass_rounded, color: Color(0xFF4CAF50), size: 18),
              const SizedBox(width: 6),
              const Text("자연풍", style: TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey)),
            ],
          ),
          const SizedBox(height: 8),
          Text("${minutes.toStringAsFixed(1)}분", style: const TextStyle(fontFamily: 'Sen', fontSize: 22, fontWeight: FontWeight.w800, color: textDark)),
          const Text("편안한 바람과 함께", style: TextStyle(fontFamily: 'Sen', fontSize: 10, color: Color(0xFF4CAF50), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // --- Chart Helpers ---

  Map<String, double> _getCombinedWindStats(AnalyticsData data) {
    final Map<String, double> stats = {};

    data.speedUsageTime.forEach((speed, duration) {
      if (duration.inMinutes > 0) {
        stats['Lv.$speed'] = duration.inMinutes.toDouble();
      }
    });

    if (_serverModeStats.containsKey('natural_wind') && _serverModeStats['natural_wind']! > 0) {
      stats['자연풍'] = _serverModeStats['natural_wind']!;
    }

    return stats;
  }

  Widget _buildCombinedWindChart(AnalyticsData data) {
    final stats = _getCombinedWindStats(data);
    final total = stats.values.fold(0.0, (sum, val) => sum + val);

    if (total == 0) return _buildEmptyChart();

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: stats.entries.map((e) {
          final percentage = (e.value / total) * 100;
          return PieChartSectionData(
            color: e.key == '자연풍' ? const Color(0xFF4CAF50) : _getSpeedColor(int.tryParse(e.key.replaceAll('Lv.', '')) ?? 0),
            value: percentage,
            radius: 20,
            showTitle: false,
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildCombinedWindLegend(AnalyticsData data) {
    final stats = _getCombinedWindStats(data);
    final total = stats.values.fold(0.0, (sum, val) => sum + val);

    if (total == 0) return [const Text("데이터 없음", style: TextStyle(color: textGrey, fontSize: 12))];

    final sorted = stats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(4).map((e) {
      final percentage = (e.value / total) * 100;
      final isNatural = e.key == '자연풍';
      final color = isNatural ? const Color(0xFF4CAF50) : _getSpeedColor(int.tryParse(e.key.replaceAll('Lv.', '')) ?? 0);

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(e.key, style: const TextStyle(fontFamily: 'Sen', fontSize: 12, fontWeight: FontWeight.bold, color: textDark)),
            const Spacer(),
            Text("${percentage.toStringAsFixed(0)}%", style: const TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey)),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildModeDonutChart() {
    double total = _serverModeStats.values.fold(0, (sum, item) => sum + item);
    if (total == 0) return _buildEmptyChart();

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: _serverModeStats.entries.map((e) {
          final percentage = (e.value / total) * 100;
          return PieChartSectionData(
            color: _getModeColor(e.key),
            value: percentage,
            radius: 20,
            showTitle: false,
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildModeLegend() {
    double total = _serverModeStats.values.fold(0, (sum, item) => sum + item);
    if (total == 0) return [const Text("데이터 없음")];

    final sorted = _serverModeStats.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return sorted.map((e) {
      final percentage = (e.value / total) * 100;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _getModeColor(e.key),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _getModeName(e.key),
              style: const TextStyle(fontFamily: 'Sen', fontSize: 12, fontWeight: FontWeight.bold, color: textDark),
            ),
            const Spacer(),
            Text(
              "${percentage.toStringAsFixed(0)}%",
              style: const TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildUsageBarChart(AnalyticsData data) {
    double maxVal = 0;
    List<BarChartGroupData> barGroups = [];

    if (_isWeekly) {
      for (int i = 0; i < data.dailyUsages.length; i++) {
        double hours = data.dailyUsages[i].usageTime.inMinutes / 60.0;
        if (hours > maxVal) maxVal = hours;
        barGroups.add(_makeBarGroup(i, hours));
      }
    } else {
      double hours = data.totalUsageTime.inMinutes / 60.0;
      maxVal = hours;
      barGroups.add(_makeBarGroup(0, hours));
    }

    if (maxVal == 0) maxVal = 1;

    return BarChart(
      BarChartData(
        maxY: maxVal * 1.2,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipRoundedRadius: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.toStringAsFixed(1)}h',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}h',
                style: const TextStyle(fontSize: 10, color: textGrey),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (_isWeekly) {
                  if (value.toInt() >= data.dailyUsages.length) return const SizedBox();
                  const weekdays = ["월", "화", "수", "목", "금", "토", "일"];
                  int weekdayIndex = data.dailyUsages[value.toInt()].date.weekday - 1;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      weekdays[weekdayIndex],
                      style: const TextStyle(fontSize: 12, color: textGrey),
                    ),
                  );
                } else {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      "오늘",
                      style: TextStyle(fontSize: 12, color: textGrey),
                    ),
                  );
                }
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxVal / 4,
        ),
        barGroups: barGroups,
      ),
    );
  }

  BarChartGroupData _makeBarGroup(int x, double y) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: primaryBlue,
          width: 14,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: y == 0 ? 1 : y * 1.2,
            color: const Color(0xFFF5F7FA),
          ),
        ),
      ],
    );
  }

  Widget _buildSpeedDonutChart(AnalyticsData data) {
    final totalMin = data.speedUsageTime.values.fold<Duration>(Duration.zero, (s, d) => s + d).inMinutes;
    if (totalMin == 0) return _buildEmptyChart();

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: data.speedUsageTime.entries.map((e) {
          final percentage = (e.value.inMinutes / totalMin) * 100;
          return PieChartSectionData(
            color: _getSpeedColor(e.key),
            value: percentage,
            radius: 20,
            showTitle: false,
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildSpeedLegend(AnalyticsData data) {
    if (data.speedUsageTime.isEmpty) return [const Text("데이터 없음", style: TextStyle(color: textGrey, fontSize: 12))];
    final totalMin = data.speedUsageTime.values.fold<Duration>(Duration.zero, (s, d) => s + d).inMinutes;
    final sortedEntries = data.speedUsageTime.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries.take(3).map((e) {
      final percentage = (e.value.inMinutes / totalMin) * 100;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _getSpeedColor(e.key),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "Lv.${e.key}",
              style: const TextStyle(fontFamily: 'Sen', fontSize: 12, fontWeight: FontWeight.bold, color: textDark),
            ),
            const Spacer(),
            Text(
              "${percentage.toStringAsFixed(0)}%",
              style: const TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildEmptyChart() {
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sections: [
              PieChartSectionData(
                value: 1,
                color: Colors.grey[200],
                radius: 15,
                showTitle: false,
              )
            ],
            centerSpaceRadius: 40,
          ),
        ),
        const Text(
          "Empty",
          style: TextStyle(fontFamily: 'Sen', fontSize: 10, color: textGrey),
        ),
      ],
    );
  }

  // --- 기존 Helper Methods ---

  Widget _buildSegmentedControl() {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildSegmentBtn("일간", !_isWeekly),
          _buildSegmentBtn("주간", _isWeekly),
        ],
      ),
    );
  }

  Widget _buildSegmentBtn(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() => _isWeekly = !_isWeekly);
          _loadAnalytics();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? textDark : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Sen',
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : textGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildBentoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12), // 16 → 12로 변경
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8), // 10 → 8로 변경
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 20), // 22 → 20으로 변경
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Sen',
                  fontSize: 18, // 20 → 18로 변경
                  fontWeight: FontWeight.w800,
                  color: textDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Sen',
                  fontSize: 11, // 12 → 11로 변경
                  fontWeight: FontWeight.w500,
                  color: textGrey,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ],
      ),
    );
  }




  Widget _buildInsightCard(List<String>? insights) {
    final displayedText = (insights == null || insights.isEmpty)
        ? "데이터를 분석하고 있어요."
        : insights.first;

    return Container(
      width: double.infinity, // 가로 꽉 채우기
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.1)), // 보라색 테두리 포인트
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row( // 가로 배치
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF), // 연한 보라 배경
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.lightbulb_rounded, color: Color(0xFF9333EA), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("AI 분석 인사이트", style: TextStyle(fontFamily: 'Sen', fontSize: 12, fontWeight: FontWeight.bold, color: textGrey)),
                const SizedBox(height: 4),
                Text(
                  displayedText,
                  style: const TextStyle(
                    fontFamily: 'Sen',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({bool hasUser = false}) {
    return Center(
      child: FadeInSlide(
        delay: 0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasUser ? Icons.bar_chart_rounded : Icons.person_search_rounded,
              size: 64,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 24),
            Text(
              hasUser ? "데이터 없음" : "사용자 선택",
              style: const TextStyle(fontFamily: 'Sen', fontSize: 20, fontWeight: FontWeight.w800, color: textDark),
            ),
            const SizedBox(height: 8),
            Text(
              hasUser ? "아직 분석할 데이터가 충분하지 않아요." : "분석할 사용자를 유저 탭에서 선택해주세요!",
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Sen', fontSize: 14, color: textGrey),
            ),
          ],
        ),
      ),
    );
  }

  String _getAverageSpeed(AnalyticsData data) {
    if (data.speedUsageTime.isEmpty) return '0';
    final totalMin = data.speedUsageTime.values.fold<Duration>(Duration.zero, (s, d) => s + d).inMinutes;
    if (totalMin == 0) return '0';
    final weightedSum = data.speedUsageTime.entries.fold<double>(0, (s, e) => s + (e.key * e.value.inMinutes));
    return (weightedSum / totalMin).toStringAsFixed(1);
  }

  Color _getSpeedColor(int speed) {
    const colors = [
      Colors.grey,
      Color(0xFFE3F2FD),
      Color(0xFF90CAF9),
      Color(0xFF42A5F5),
      Color(0xFF1E88E5),
      Color(0xFF1565C0),
    ];
    return colors[speed.clamp(0, 5)];
  }

  String _getModeName(String key) {
    switch (key) {
      case 'natural_wind':
        return '자연풍';
      case 'ai_tracking':
        return 'AI 트래킹';
      case 'rotation':
        return '회전';
      case 'manual_control':
        return '수동';
      default:
        return key;
    }
  }

  Color _getModeColor(String key) {
    return _modeColors[key] ?? Colors.grey;
  }
}

class FadeInSlide extends StatelessWidget {
  final Widget child;
  final int delay;
  const FadeInSlide({super.key, required this.child, required this.delay});
  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - value)),
        child: Opacity(opacity: value, child: child),
      ),
      child: child,
    );
  }
}