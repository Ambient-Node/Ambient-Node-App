import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/user_analytics.dart';
import '../services/analytics_service.dart';
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
  bool _isLoading = true;

  // PageController for horizontal insight cards
  final PageController _pageController = PageController(viewportFraction: 0.9);
  int _currentPage = 0;

  static const Color primaryBlue = Color(0xFF3A91FF);
  static const Color textDark = Color(0xFF2D3142);
  static const Color textGrey = Color(0xFF9098B1);
  static const Color bgGrey = Color(0xFFF4F6F8);

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  @override
  void dispose() {
    _pageController.dispose();
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
      final data = _isWeekly
          ? await AnalyticsService.getWeeklyAnalytics(widget.selectedUserName!, now.subtract(Duration(days: now.weekday - 1)))
          : await AnalyticsService.getDailyAnalytics(widget.selectedUserName!, now);

      if (mounted) {
        setState(() {
          _analyticsData = data;
          _isLoading = false;
        });
      }
      
      try {
        final insights = await AnalyticsService.generateInsights(widget.selectedUserName!, weekly: _isWeekly);
        if (mounted) setState(() => _insights = insights);
      } catch (_) {
        if (mounted) setState(() => _insights = ['인사이트를 생성할 수 없습니다.']);
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
                  IconButton(
                    tooltip: 'Seed Test Data',
                    onPressed: () async {
                      if (widget.selectedUserName == null) {
                        showAppSnackBar(context, '사용자를 선택하세요', type: AppSnackType.info);
                        return;
                      }
                      await AnalyticsService.seedAnalyticsForUser(widget.selectedUserName!);
                      await _loadAnalytics();
                      showAppSnackBar(context, '샘플 분석 데이터가 로드되었습니다', type: AppSnackType.success);
                    },
                    icon: const Icon(Icons.bolt_rounded, color: Colors.black54),
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

  // ... (SegmentedControl 등 기존 위젯 유지) ...
  Widget _buildSegmentedControl() {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
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
        padding: const EdgeInsets.symmetric(horizontal: 16),
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

  // [신규] 가로 스크롤 가능한 고급 인사이트 카드 섹션
  Widget _buildInsightCarousel(List<String>? insights) {
    if (insights == null || insights.isEmpty) {
      return _buildSingleInsightCard(
        text: "데이터가 충분하지 않아 인사이트를 분석할 수 없습니다.",
        icon: Icons.analytics_outlined,
        color: Colors.grey,
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 140, // 카드 높이
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (idx) => setState(() => _currentPage = idx),
            itemCount: insights.length,
            itemBuilder: (context, index) {
              final text = insights[index];
              // 텍스트 내용에 따라 아이콘/색상 자동 매칭
              IconData icon = Icons.lightbulb_outline;
              Color color = const Color(0xFF6366F1); // Default Indigo

              if (text.contains("풍속")) {
                icon = Icons.wind_power_rounded;
                color = const Color(0xFF00C896); // Green
              } else if (text.contains("수동") || text.contains("조작")) {
                icon = Icons.touch_app_rounded;
                color = const Color(0xFFFF7F50); // Orange
              } else if (text.contains("시간") || text.contains("시경")) {
                icon = Icons.access_time_filled_rounded;
                color = const Color(0xFF3A91FF); // Blue
              } else if (text.contains("얼굴")) {
                icon = Icons.face_retouching_natural_rounded;
                color = const Color(0xFF9C27B0); // Purple
              }

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _buildSingleInsightCard(text: text, icon: icon, color: color),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // 페이지 인디케이터
        if (insights.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(insights.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _currentPage == index ? 20 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _currentPage == index ? primaryBlue : Colors.grey[300],
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
      ],
    );
  }

  Widget _buildSingleInsightCard({required String text, required IconData icon, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.1), width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "AI 분석 리포트",
                  style: TextStyle(
                    fontFamily: 'Sen',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color.withOpacity(0.8),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    fontFamily: 'Sen',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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

  Widget _buildBentoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Sen',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Sen',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    final data = _analyticsData!;
    final totalHours = data.totalUsageTime.inHours;
    final totalMinutes = data.totalUsageTime.inMinutes % 60;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 상단 요약 카드 (기존 유지)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeInSlide(
              delay: 0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3A91FF), Color(0xFF6B4DFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF3A91FF).withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 8)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.3), width: 2)),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            child: Text(
                              widget.selectedUserName![0].toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.selectedUserName!,
                              style: const TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            Text(
                              _isWeekly ? "이번 주 리포트" : "오늘의 리포트",
                              style: TextStyle(fontFamily: 'Sen', fontSize: 12, color: Colors.white.withOpacity(0.8)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text("Total Usage", style: TextStyle(fontFamily: 'Sen', fontSize: 12, color: Colors.white70)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          "$totalHours",
                          style: const TextStyle(fontFamily: 'Sen', fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white, height: 1.0),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6, left: 4, right: 8),
                          child: Text("h", style: TextStyle(fontFamily: 'Sen', fontSize: 18, color: Colors.white70)),
                        ),
                        Text(
                          "$totalMinutes",
                          style: const TextStyle(fontFamily: 'Sen', fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white, height: 1.0),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 6, left: 4),
                          child: Text("m", style: TextStyle(fontFamily: 'Sen', fontSize: 18, color: Colors.white70)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // [수정됨] 2. 가로 스크롤 인사이트 카드 (Carousel)
          FadeInSlide(
            delay: 100,
            child: _buildInsightCarousel(_insights),
          ),

          const SizedBox(height: 24),

          // 3. 통계 카드 그리드 (기존 유지)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeInSlide(
              delay: 200,
              child: Row(
                children: [
                  Expanded(
                    child: _buildBentoCard(
                      title: "수동 조작",
                      value: "${data.manualControlCount}회",
                      icon: Icons.touch_app_rounded,
                      accentColor: const Color(0xFFFF7F50),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildBentoCard(
                      title: "얼굴 추적",
                      value: "${data.faceTrackingTime.inMinutes}m",
                      icon: Icons.face_retouching_natural_rounded,
                      accentColor: const Color(0xFF00C896),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // 4. 히스토리 차트 (기존 유지)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeInSlide(
              delay: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("사용 히스토리", style: TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.w800, color: textDark)),
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
          ),

          const SizedBox(height: 32),

          // 5. 선호 풍속 차트 (기존 유지)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeInSlide(
              delay: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("선호 풍속", style: TextStyle(fontFamily: 'Sen', fontSize: 18, fontWeight: FontWeight.w800, color: textDark)),
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
                        SizedBox(height: 140, width: 140, child: _buildDonutChart(data)),
                        const SizedBox(width: 24),
                        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: _buildSpeedLegend(data))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ... (기존 _buildBarChart, _makeBarGroup, _buildDonutChart, _buildSpeedLegend, _buildEmptyState, _getAverageSpeed, _getSpeedColor 등 유지) ...
  Widget _buildBarChart(AnalyticsData data) {
    double maxDataValue = 0;
    if (_isWeekly) {
      for (var day in data.dailyUsages) {
        double hours = day.usageTime.inMinutes / 60;
        if (hours > maxDataValue) maxDataValue = hours;
      }
    } else {
      maxDataValue = data.totalUsageTime.inMinutes / 60;
    }

    double chartMaxY = maxDataValue * 1.2;
    if (chartMaxY < 5) chartMaxY = 5;

    return BarChart(
      BarChartData(
        maxY: chartMaxY,
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (_isWeekly) {
                  if (value.toInt() >= data.dailyUsages.length) return const SizedBox();
                  final date = data.dailyUsages[value.toInt()].date;
                  const weekdays = ["", "월", "화", "수", "목", "금", "토", "일"];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      weekdays[date.weekday],
                      style: const TextStyle(color: textGrey, fontSize: 12, fontFamily: 'Sen'),
                    ),
                  );
                } else {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text("오늘", style: TextStyle(color: textGrey, fontSize: 12, fontFamily: 'Sen')),
                  );
                }
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
        barGroups: _isWeekly
            ? data.dailyUsages.asMap().entries.map((e) {
          return _makeBarGroup(e.key, e.value.usageTime.inMinutes / 60, chartMaxY);
        }).toList()
            : [ _makeBarGroup(0, data.totalUsageTime.inMinutes / 60, chartMaxY) ],
      ),
    );
  }

  BarChartGroupData _makeBarGroup(int x, double y, double maxY) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: primaryBlue,
          width: 16,
          borderRadius: BorderRadius.circular(8),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: maxY,
            color: const Color(0xFFF0F2F5),
          ),
        ),
      ],
    );
  }

  Widget _buildDonutChart(AnalyticsData data) {
    final totalMin = data.speedUsageTime.values.fold<Duration>(Duration.zero, (s, d) => s + d).inMinutes;

    if (totalMin == 0) {
      return Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
              PieChartData(
                sections: [PieChartSectionData(value: 1, color: Colors.grey[200], radius: 15, showTitle: false)],
                centerSpaceRadius: 40,
              )
          ),
          const Text("데이터 없음", style: TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey)),
        ],
      );
    }

    return PieChart(
      PieChartData(
        sectionsSpace: 0,
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
    if (data.speedUsageTime.isEmpty) return [const Text("-")];

    final totalMin = data.speedUsageTime.values.fold<Duration>(Duration.zero, (s, d) => s + d).inMinutes;
    final sortedEntries = data.speedUsageTime.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedEntries.take(3).map((e) {
      final percentage = (e.value.inMinutes / totalMin) * 100;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: _getSpeedColor(e.key), shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text("Lv.${e.key}", style: const TextStyle(fontFamily: 'Sen', fontSize: 12, fontWeight: FontWeight.bold, color: textDark)),
            const Spacer(),
            Text("${percentage.toStringAsFixed(0)}%", style: const TextStyle(fontFamily: 'Sen', fontSize: 12, color: textGrey)),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildEmptyState({bool hasUser = false, String? title, String? subtitle, String? buttonText, VoidCallback? onTap}) {
    return Center(
      child: FadeInSlide(
        delay: 0,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                hasUser ? Icons.bar_chart_rounded : Icons.person_search_rounded,
                size: 64, color: Colors.grey[300]
            ),
            const SizedBox(height: 24),
            Text(title ?? "사용자 선택", style: const TextStyle(fontFamily: 'Sen', fontSize: 20, fontWeight: FontWeight.w800, color: textDark)),
            const SizedBox(height: 8),
            Text(
              subtitle ?? "분석하고자 하는 사용자를 유저 탭에서 선택하세요.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Sen', fontSize: 14, color: textGrey),
            ),
            if (buttonText != null) ...[
              const SizedBox(height: 32),
              TextButton(
                onPressed: onTap,
                child: Text(buttonText, style: const TextStyle(color: primaryBlue, fontWeight: FontWeight.bold)),
              )
            ]
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
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value,child: child),
        );
      },
      child: child,
    );
  }
}