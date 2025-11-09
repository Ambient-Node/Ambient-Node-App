import 'package:flutter/material.dart';
import '../models/user_analytics.dart';
import '../services/analytics_service.dart';
import '../widgets/analytics_charts.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  @override
  void didUpdateWidget(AnalyticsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedUserName != widget.selectedUserName) {
      _loadAnalytics();
    }
  }

  Future<void> _loadAnalytics() async {
    print(
        '🔍 _loadAnalytics called - selectedUserName: ${widget.selectedUserName}');

    if (widget.selectedUserName == null) {
      print('❌ No user selected');
      setState(() {
        _analyticsData = null;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final now = DateTime.now();
      print('📊 Loading analytics for user: ${widget.selectedUserName}');

      final data = _isWeekly
          ? await AnalyticsService.getWeeklyAnalytics(
              widget.selectedUserName!,
              now.subtract(Duration(days: now.weekday - 1)), // 주간 시작일
            )
          : await AnalyticsService.getDailyAnalytics(
              widget.selectedUserName!,
              now,
            );

      print(
          '✅ Analytics loaded - totalUsageTime: ${data.totalUsageTime.inMinutes} minutes');

      setState(() {
        _analyticsData = data;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading analytics: $e');
      setState(() {
        _analyticsData = null;
        _isLoading = false;
      });
    }
  }

  void _toggleTimeRange() {
    setState(() {
      _isWeekly = !_isWeekly;
    });
    _loadAnalytics();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F8),
      body: SafeArea(
        child: Column(
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    '사용자 분석',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                      fontFamily: 'Sen',
                    ),
                  ),
                  const Spacer(),
                  // 일간/주간 토글 버튼과 테스트 데이터 생성 버튼
                  Row(
                    children: [
                      Container(
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
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildToggleButton('일간', !_isWeekly),
                            _buildToggleButton('주간', _isWeekly),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 테스트 데이터 생성 버튼
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A91FF),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          onPressed: () async {
                            print(
                                '🧪 테스트 데이터 생성 버튼 클릭됨 (사용자: ${widget.selectedUserName})');
                            try {
                              await AnalyticsService.generateTestData(
                                  widget.selectedUserName!);
                              print('✅ 테스트 데이터 생성 완료');
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('테스트 데이터가 생성되었습니다!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              // 데이터 새로고침
                              _loadAnalytics();
                            } catch (e) {
                              print('❌ 테스트 데이터 생성 실패: $e');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('테스트 데이터 생성 실패: $e'),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          icon: const Icon(
                            Icons.science,
                            color: Colors.white,
                            size: 20,
                          ),
                          tooltip: '테스트 데이터 생성',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 콘텐츠
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : widget.selectedUserName == null
                      ? _buildNoUserSelected()
                      : _analyticsData == null
                          ? _buildNoData()
                          : _buildAnalyticsContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleButton(String text, bool isSelected) {
    return GestureDetector(
      onTap: isSelected ? null : _toggleTimeRange,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3A91FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: FontWeight.w600,
            fontFamily: 'Sen',
          ),
        ),
      ),
    );
  }

  Widget _buildNoUserSelected() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '사용자를 선택해주세요',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '제어 탭에서 사용자를 선택하면\n분석 데이터를 확인할 수 있습니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 24),

          // 테스트 데이터 생성 버튼
          ElevatedButton.icon(
            onPressed: () async {
              print('🧪 테스트 데이터 생성 버튼 클릭됨');
              try {
                await AnalyticsService.generateTestData('테스트 사용자');
                print('✅ 테스트 데이터 생성 완료');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('테스트 데이터가 생성되었습니다!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } catch (e) {
                print('❌ 테스트 데이터 생성 실패: $e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('테스트 데이터 생성 실패: $e'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: const Icon(Icons.science),
            label: const Text('테스트 데이터 생성'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3A91FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '분석 데이터가 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '선풍기를 사용하면\n분석 데이터가 생성됩니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 24),
          // 테스트 데이터 생성 버튼
          ElevatedButton.icon(
            onPressed: () async {
              await AnalyticsService.generateTestData(widget.selectedUserName!);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('테스트 데이터가 생성되었습니다!'),
                  duration: Duration(seconds: 2),
                ),
              );
              // 데이터 새로고침
              _loadAnalytics();
            },
            icon: const Icon(Icons.science),
            label: const Text('테스트 데이터 생성'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3A91FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsContent() {
    final data = _analyticsData!;
    final totalHours = data.totalUsageTime.inHours;
    final totalMinutes = data.totalUsageTime.inMinutes % 60;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사용자 정보
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
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
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF3A91FF).withOpacity(0.1),
                  child: Text(
                    widget.selectedUserName![0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3A91FF),
                      fontFamily: 'Sen',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.selectedUserName!,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Sen',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isWeekly ? '주간 분석' : '일간 분석',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontFamily: 'Sen',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 통계 카드들
          Row(
            children: [
              Expanded(
                child: StatCard(
                  title: '총 사용시간',
                  value: '${totalHours}시간 ${totalMinutes}분',
                  icon: Icons.access_time,
                  color: const Color(0xFF3A91FF),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatCard(
                  title: '수동 제어',
                  value: '${data.manualControlCount}회',
                  icon: Icons.touch_app,
                  color: const Color(0xFF4CAF50),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: StatCard(
                  title: '얼굴 추적',
                  value: '${data.faceTrackingTime.inMinutes}분',
                  icon: Icons.face,
                  color: const Color(0xFFFF9800),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: StatCard(
                  title: '평균 속도',
                  value: _getAverageSpeed(data),
                  icon: Icons.speed,
                  color: const Color(0xFF9C27B0),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 사용 시간 차트
          UsageTimeChart(
            data: data,
            isWeekly: _isWeekly,
          ),

          const SizedBox(height: 24),

          // 속도별 사용 비율 차트
          SpeedUsagePieChart(data: data),

          const SizedBox(height: 24),

          // 상세 정보
          if (data.speedUsageTime.isNotEmpty) _buildSpeedDetails(data),
        ],
      ),
    );
  }

  Widget _buildSpeedDetails(AnalyticsData data) {
    final totalMinutes = data.speedUsageTime.values
        .fold<Duration>(Duration.zero, (sum, duration) => sum + duration)
        .inMinutes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '속도별 상세 사용량',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 16),
          ...data.speedUsageTime.entries.map((entry) {
            final speed = entry.key;
            final duration = entry.value;
            final percentage = totalMinutes > 0
                ? (duration.inMinutes / totalMinutes) * 100
                : 0.0;
            final hours = duration.inHours;
            final minutes = duration.inMinutes % 60;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _getSpeedColor(speed),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '$speed',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Sen',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${speed}단계',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Sen',
                          ),
                        ),
                        Text(
                          '${hours}시간 ${minutes}분 (${percentage.toStringAsFixed(1)}%)',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontFamily: 'Sen',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 진행률 바
                  Container(
                    width: 100,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: percentage / 100,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getSpeedColor(speed),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  String _getAverageSpeed(AnalyticsData data) {
    if (data.speedUsageTime.isEmpty) return '0단계';

    final totalMinutes = data.speedUsageTime.values
        .fold<Duration>(Duration.zero, (sum, duration) => sum + duration)
        .inMinutes;

    if (totalMinutes == 0) return '0단계';

    final weightedSum = data.speedUsageTime.entries.fold<double>(
        0, (sum, entry) => sum + (entry.key * entry.value.inMinutes));

    final average = weightedSum / totalMinutes;
    return '${average.toStringAsFixed(1)}단계';
  }

  Color _getSpeedColor(int speed) {
    switch (speed) {
      case 1:
        return const Color(0xFFE3F2FD);
      case 2:
        return const Color(0xFFBBDEFB);
      case 3:
        return const Color(0xFF90CAF9);
      case 4:
        return const Color(0xFF64B5F6);
      case 5:
        return const Color(0xFF3A91FF);
      default:
        return Colors.grey;
    }
  }
}
