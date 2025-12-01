import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/user_analytics.dart'; // 기존 모델 사용
import '../services/analytics_service.dart'; // 로컬 서비스
import '../services/mqtt_service.dart'; // MQTT 서비스
import 'dart:async';
import '../utils/snackbar_helper.dart'; // 스낵바 헬퍼

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
  
  // [수정] 서버에서 받아온 모드별 사용 시간 저장용 Map
  Map<String, double> _serverModeStats = {}; 
  
  StreamSubscription<Map<String, dynamic>>? _mqttSub;
  bool _isLoading = true;

  static const Color primaryBlue = Color(0xFF3A91FF);
  static const Color textDark = Color(0xFF2D3142);
  static const Color textGrey = Color(0xFF9098B1);
  static const Color bgGrey = Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
    
    // MQTT 초기화 및 구독
    _initMqtt();
  }

  void _initMqtt() async {
    try {
      await MqttService().initialize();
      MqttService().subscribe('ambient/stats/response');
      
      _mqttSub = MqttService().messages.listen((msg) {
        if (!mounted) return;
        
        final topic = msg['__topic'] as String?;
        if (topic != 'ambient/stats/response') return;

        // [수정] 응답 타입 확인 및 데이터 파싱
        final type = msg['type'];
        final data = msg['data'];

        if (type == 'mode_usage' && data is List) {
          // 데이터 예시: [{"mode": "natural_wind", "minutes": 10.5}, ...]
          final newStats = <String, double>{};
          for (var item in data) {
            if (item is Map) {
              final mode = item['mode']?.toString() ?? 'unknown';
              final minutes = (item['minutes'] is num) 
                  ? (item['minutes'] as num).toDouble() 
                  : double.tryParse(item['minutes'].toString()) ?? 0.0;
              newStats[mode] = minutes;
            }
          }
          setState(() {
            _serverModeStats = newStats;
          });
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _mqttSub?.cancel();
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
      if (mounted) setState(() { _analyticsData = null; _isLoading = false; });
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      
      // 1. 로컬 분석 데이터 로드 (기존 로직 유지)
      final data = _isWeekly
          ? await AnalyticsService.getWeeklyAnalytics(widget.selectedUserName!, now.subtract(Duration(days: now.weekday - 1)))
          : await AnalyticsService.getDailyAnalytics(widget.selectedUserName!, now);

      // 2. 서버에 최신 모드 사용 통계 요청 (MQTT)
      try {
        MqttService().publish('ambient/stats/request', {
          'type': 'mode_usage', // 핸들러에서 새로 만든 타입 요청
          'period': _isWeekly ? 'week' : 'day',
          'user_id': widget.selectedUserName!
        });
      } catch (_) {}

      // 3. 인사이트 생성
      List<String>? insights;
      try {
        insights = await AnalyticsService.generateInsights(widget.selectedUserName!, weekly: _isWeekly);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _analyticsData = data;
          _insights = insights;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _analyticsData = null; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey,
      body: SafeArea(
        child: Column(
          children: [
            // --- 상단 헤더 ---
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Row(
                children: [
                  const Text(
                    "인사이트",
                    style: TextStyle(fontFamily: 'Sen', fontSize: 28, fontWeight: FontWeight.w800, color: textDark),
                  ),
                  const Spacer(),
                  _buildSegmentedControl(),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '새로고침',
                    onPressed: _loadAnalytics, // 새로고침 버튼으로 변경
                    icon: const Icon(Icons.refresh_rounded, color: textDark),
                  ),
                ],
              ),
            ),

            // --- 메인 컨텐츠 ---
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. [디자인 복구] 흰색 배경의 깔끔한 총 사용 시간 카드
          FadeInSlide(
            delay: 0,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white, // 그라데이션 제거 -> 흰색 배경
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05), // 은은한 그림자
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
                      // 프로필 아이콘
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFE3F2FD),
                        child: Text(
                          widget.selectedUserName![0].toUpperCase(),
                          style: const TextStyle(color: primaryBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // 문구 수정: 친근하게
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${widget.selectedUserName!}님,",
                            style: const TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.bold, color: textDark),
                          ),
                          Text(
                            _isWeekly ? "이번 주는 이만큼 사용하셨네요!" : "오늘도 시원하게 보내셨나요?",
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

          // 2. 자연풍 사용 시간 (데이터 있을 때만 표시)
          if (_naturalWindMinutes != null && _naturalWindMinutes! > 0)
            FadeInSlide(
              delay: 80,
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE0E0E0).withOpacity(0.5)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.grass_rounded, color: Color(0xFF4CAF50), size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("자연풍과 함께", style: TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey)),
                          Text(
                            '${_naturalWindMinutes!.toStringAsFixed(1)}분 동안 힐링했어요!',
                            style: const TextStyle(fontFamily: 'Sen', fontSize: 15, fontWeight: FontWeight.bold, color: textDark),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3. 작은 정보 카드들
          FadeInSlide(
            delay: 100,
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

          const SizedBox(height: 16),

          FadeInSlide(
            delay: 200,
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
                // 인사이트 카드
                Expanded(
                  child: _buildInsightCard(_insights),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // 4. 시간대별 사용량 차트
          FadeInSlide(
            delay: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("언제 많이 사용했을까요?", style: TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.w800, color: textDark)),
                const SizedBox(height: 16),
                Container(
                  height: 220,
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: _buildBarChart(data),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // 5. 선호 풍속 차트
          FadeInSlide(
            delay: 400,
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
                      SizedBox(
                        height: 140,
                        width: 140,
                        child: _buildDonutChart(data),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: _buildSpeedLegend(data),
                        ),
                      ),
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
  // --- 위젯 헬퍼 함수들 ---

  Widget _buildModeUsageCard(String mode, double minutes) {
    String title = mode;
    IconData icon = Icons.settings;
    Color color = Colors.grey;

    if (mode == 'natural_wind') {
      title = '자연풍 모드';
      icon = Icons.grass_rounded;
      color = Colors.green;
    } else if (mode == 'ai_tracking') {
      title = 'AI 트래킹';
      icon = Icons.remove_red_eye_rounded;
      color = Colors.purple;
    } else if (mode == 'rotation') {
      title = '자동 회전';
      icon = Icons.sync;
      color = Colors.orange;
    } else if (mode == 'manual_control') {
      title = '수동 제어';
      icon = Icons.tune;
      color = Colors.blue;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontFamily: 'Sen', fontSize: 14, fontWeight: FontWeight.bold, color: textDark)),
          const Spacer(),
          Text("${minutes.toStringAsFixed(1)}분", style: const TextStyle(fontFamily: 'Sen', fontSize: 16, fontWeight: FontWeight.w800, color: textDark)),
        ],
      ),
    );
  }

  
  Widget _buildSegmentedControl() {
    return Container(
      height: 40, padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)]),
      child: Row(children: [_buildSegmentBtn("일간", !_isWeekly), _buildSegmentBtn("주간", _isWeekly)]),
    );
  }
  Widget _buildSegmentBtn(String label, bool isSelected) {
    return GestureDetector(
      onTap: () { if (!isSelected) { setState(() => _isWeekly = !_isWeekly); _loadAnalytics(); } },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: isSelected ? textDark : Colors.transparent, borderRadius: BorderRadius.circular(16)),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : textGrey, fontWeight: FontWeight.bold)),
      ),
    );
  }
  Widget _buildBentoCard({required String title, required String value, required IconData icon, required Color accentColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: accentColor), const SizedBox(height: 16),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Text(title, style: const TextStyle(fontSize: 12, color: textGrey)),
      ]),
    );
  }
  Widget _buildInsightCard(List<String>? insights) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.lightbulb_outline, color: Colors.purple), const SizedBox(height: 12),
        Text(insights?.first ?? "데이터 수집 중...", style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
  String _getAverageSpeed(AnalyticsData data) {
    if (data.speedUsageTime.isEmpty) return '0';
    final totalMin = data.speedUsageTime.values.fold<Duration>(Duration.zero, (s, d) => s + d).inMinutes;
    if (totalMin == 0) return '0';
    final sum = data.speedUsageTime.entries.fold<double>(0, (s, e) => s + (e.key * e.value.inMinutes));
    return (sum / totalMin).toStringAsFixed(1);
  }
  Widget _buildEmptyState({bool hasUser = false}) {
    return Center(child: Text(hasUser ? "데이터가 없습니다" : "사용자를 선택해주세요"));
  }
  
  Widget _buildBarChart(AnalyticsData data) => const Center(child: Text("Chart Placeholder"));
  Widget _buildDonutChart(AnalyticsData data) => const Center(child: Text("Donut Placeholder"));
  List<Widget> _buildSpeedLegend(AnalyticsData data) => [const Text("Speed Legend Placeholder")];
}

class FadeInSlide extends StatelessWidget {
  final Widget child;
  final int delay;
  const FadeInSlide({super.key, required this.child, required this.delay});
  @override
  Widget build(BuildContext context) => child; // 간소화
}