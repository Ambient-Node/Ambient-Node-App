import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/user_analytics.dart';

class UsageTimeChart extends StatelessWidget {
  final AnalyticsData data;
  final bool isWeekly;

  const UsageTimeChart({
    super.key,
    required this.data,
    this.isWeekly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
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
            '사용 시간',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: isWeekly ? _buildWeeklyChart() : _buildDailyChart(),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyChart() {
    final hours = data.totalUsageTime.inMinutes / 60;
    final maxHours = hours > 0 ? (hours * 1.2).ceil().toDouble() : 10.0;

    return BarChart(
      BarChartData(
        maxY: maxHours,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.blue.withOpacity(0.8),
            tooltipRoundedRadius: 8,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${rod.toY.toStringAsFixed(1)}시간',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Sen',
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}h',
                style: const TextStyle(fontSize: 12, fontFamily: 'Sen'),
              ),
              reservedSize: 40,
              interval: maxHours / 5,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: hours,
                color: const Color(0xFF3A91FF),
                width: 40,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
              ),
            ],
          ),
        ],
        gridData: FlGridData(show: false),
      ),
    );
  }

  Widget _buildWeeklyChart() {
    final maxHours = data.dailyUsages.isEmpty
        ? 10.0
        : data.dailyUsages
                .map((d) => d.usageTime.inMinutes / 60)
                .reduce((a, b) => a > b ? a : b) *
            1.2;

    return BarChart(
      BarChartData(
        maxY: maxHours,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (touchedSpot) => Colors.blue.withOpacity(0.8),
            tooltipRoundedRadius: 8,
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final day = data.dailyUsages[group.x];
              final hours = day.usageTime.inMinutes / 60;
              return BarTooltipItem(
                '${day.date.month}/${day.date.day}\n${hours.toStringAsFixed(1)}시간',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Sen',
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Text(
                '${value.toInt()}h',
                style: const TextStyle(fontSize: 12, fontFamily: 'Sen'),
              ),
              reservedSize: 40,
              interval: maxHours / 5,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= data.dailyUsages.length)
                  return const Text('');
                final day = data.dailyUsages[value.toInt()];
                return Text(
                  '${day.date.month}/${day.date.day}',
                  style: const TextStyle(fontSize: 12, fontFamily: 'Sen'),
                );
              },
              reservedSize: 30,
            ),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        barGroups: data.dailyUsages.asMap().entries.map((entry) {
          final index = entry.key;
          final day = entry.value;
          final hours = day.usageTime.inMinutes / 60;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: hours,
                color: const Color(0xFF3A91FF),
                width: 20,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }).toList(),
        gridData: FlGridData(show: false),
      ),
    );
  }
}

class SpeedUsagePieChart extends StatelessWidget {
  final AnalyticsData data;

  const SpeedUsagePieChart({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    if (data.speedUsageTime.isEmpty) {
      return Container(
        height: 220,
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
        child: Center(
          child: Text(
            '사용 데이터가 없습니다',
            style: TextStyle(
              color: Colors.grey[600],
              fontFamily: 'Sen',
            ),
          ),
        ),
      );
    }

    final totalMinutes = data.speedUsageTime.values
        .fold<Duration>(Duration.zero, (sum, duration) => sum + duration)
        .inMinutes;

    if (totalMinutes == 0) {
      return Container(
        height: 220,
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
        child: Center(
          child: Text(
            '사용 데이터가 없습니다',
            style: TextStyle(
              color: Colors.grey[600],
              fontFamily: 'Sen',
            ),
          ),
        ),
      );
    }

    final pieData = data.speedUsageTime.entries.map((entry) {
      final speed = entry.key;
      final duration = entry.value;
      final percentage = (duration.inMinutes / totalMinutes) * 100;

      return PieChartSectionData(
        color: _getSpeedColor(speed),
        value: percentage,
        title: '${speed}단계',
        radius: 45,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontFamily: 'Sen',
        ),
      );
    }).toList();

    return Container(
      height: 220,
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
            '속도별 사용 비율',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey[800],
              fontFamily: 'Sen',
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: PieChart(
                    PieChartData(
                      sections: pieData,
                      centerSpaceRadius: 25,
                      sectionsSpace: 2,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: data.speedUsageTime.entries.map((entry) {
                      final speed = entry.key;
                      final duration = entry.value;
                      final percentage =
                          (duration.inMinutes / totalMinutes) * 100;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: _getSpeedColor(speed),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${speed}단계: ${percentage.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'Sen',
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  fontFamily: 'Sen',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
              fontFamily: 'Sen',
            ),
          ),
        ],
      ),
    );
  }
}
