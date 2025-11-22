import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:ambient_node/services/analytics_service.dart';
import 'package:ambient_node/models/user_analytics.dart';

class AnalyticsScreen extends StatefulWidget {
  final DashboardAnalytics? analyticsData;
  final bool isLoading;
  final Function(String period) onPeriodChanged;

  const AnalyticsScreen({
    super.key,
    this.analyticsData,
    this.isLoading = false,
    required this.onPeriodChanged,
  });

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _selectedPeriod = 'day';

  // ✨ Nature Theme Colors
  static const Color _primaryGreen = Color(0xFF4CAF50);
  static const Color _lightGreen = Color(0xFF81C784);
  static const Color _bgWhite = Colors.white;
  static const Color _bgGrey = Color(0xFFF1F8E9); // Very light green tint
  static const Color _textDark = Color(0xFF2D3142);
  static const Color _textGrey = Color(0xFF9095A5);

  final TextStyle _fontSen = const TextStyle(fontFamily: 'Sen');

  @override
  Widget build(BuildContext context) {
    final data = widget.analyticsData;
    final hasData = data != null && !widget.isLoading;

    return Scaffold(
      backgroundColor: _bgGrey,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Analytics",
                        style: _fontSen.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, yyyy').format(DateTime.now()),
                        style: _fontSen.copyWith(fontSize: 14, color: _textGrey, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  _buildPeriodToggle(),
                ],
              ),
              const SizedBox(height: 32),

              // 2. Summary Hero (Green Gradient)
              _buildSummaryCard(hasData, data),

              const SizedBox(height: 24),

              // 3. Usage Trend
              _SectionHeader(title: "Usage Trend", icon: Icons.bar_chart_rounded),
              const SizedBox(height: 12),
              Container(
                height: 300,
                decoration: _cardDecoration(),
                padding: const EdgeInsets.all(24),
                child: hasData
                    ? _UsageBarChart(stats: data!.usageStats, period: _selectedPeriod)
                    : _buildLoadingShimmer(),
              ),

              const SizedBox(height: 24),

              // 4. Smart Analysis
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _SectionHeader(title: "AI Mode", icon: Icons.pie_chart_rounded),
                        const SizedBox(height: 12),
                        Container(
                          height: 220,
                          decoration: _cardDecoration(),
                          padding: const EdgeInsets.all(20),
                          child: hasData
                              ? _ModeDonutChart(stats: data!.modeRatioStats)
                              : _buildLoadingShimmer(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        _SectionHeader(title: "Speed", icon: Icons.wind_power_rounded),
                        const SizedBox(height: 12),
                        Container(
                          height: 220,
                          decoration: _cardDecoration(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          child: hasData
                              ? _SpeedPreferenceList(stats: data!.speedDistStats)
                              : _buildLoadingShimmer(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Components ---

  Widget _buildPeriodToggle() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          _toggleButton("Day", 'day'),
          _toggleButton("Week", 'week'),
        ],
      ),
    );
  }

  Widget _toggleButton(String label, String value) {
    final isSelected = _selectedPeriod == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedPeriod = value);
        widget.onPeriodChanged(value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? _textDark : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: _fontSen.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : _textGrey,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(bool hasData, DashboardAnalytics? data) {
    double totalMinutes = 0;
    if (hasData && data != null) {
      for (var item in data.usageStats) totalMinutes += item.minutes;
    }
    final hours = (totalMinutes / 60).floor();
    final minutes = (totalMinutes % 60).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        // ✨ Green Gradient
        gradient: const LinearGradient(
          colors: [_primaryGreen, Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _primaryGreen.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.eco_rounded, color: Colors.white, size: 28), // Nature Icon
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Total Usage", style: _fontSen.copyWith(color: Colors.white.withOpacity(0.9), fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              hasData
                  ? RichText(
                text: TextSpan(
                  style: _fontSen.copyWith(color: Colors.white),
                  children: [
                    TextSpan(text: "$hours", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                    const TextSpan(text: " h  ", style: TextStyle(fontSize: 16)),
                    TextSpan(text: "$minutes", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700)),
                    const TextSpan(text: " min", style: TextStyle(fontSize: 16)),
                  ],
                ),
              )
                  : Container(height: 32, width: 100, color: Colors.white.withOpacity(0.2)),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
    );
  }

  Widget _buildLoadingShimmer() {
    return Center(child: CircularProgressIndicator(color: _primaryGreen.withOpacity(0.5), strokeWidth: 2));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF9095A5)),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontFamily: 'Sen', fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF2D3142))),
      ],
    );
  }
}

// --- Charts (Green Colors) ---

class _UsageBarChart extends StatelessWidget {
  final List<UsageStatItem> stats;
  final String period;
  const _UsageBarChart({required this.stats, required this.period});

  @override
  Widget build(BuildContext context) {
    double maxY = 0;
    for (var s in stats) { if (s.minutes > maxY) maxY = s.minutes; }
    maxY = (maxY * 1.2).clamp(10.0, double.infinity);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceBetween,
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF2D3142),
            tooltipRoundedRadius: 8,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem('${rod.toY.round()} min', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12));
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= stats.length) return const SizedBox();
                final item = stats[index];
                String text = period == 'day' ? DateFormat('H').format(item.time) : DateFormat('E').format(item.time);
                if (stats.length > 12 && index % 2 != 0) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(text, style: const TextStyle(color: Color(0xFF9EA3B2), fontSize: 11, fontFamily: 'Sen')),
                );
              },
              reservedSize: 30,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: stats.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isMax = item.minutes == stats.map((e) => e.minutes).reduce((a, b) => a > b ? a : b);
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: item.minutes,
                // ✨ Green Bar
                color: isMax ? const Color(0xFF4CAF50) : const Color(0xFFE0E3E7),
                width: 12,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxY, color: const Color(0xFFF6F8FB)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ModeDonutChart extends StatelessWidget {
  final List<ModeRatioItem> stats;
  const _ModeDonutChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final aiItem = stats.firstWhere((e) => e.mode == 'ai', orElse: () => ModeRatioItem(mode: 'ai', hours: 0, percentage: 0));

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sectionsSpace: 4,
            centerSpaceRadius: 40,
            startDegreeOffset: 270,
            sections: stats.map((item) {
              final isAi = item.mode == 'ai';
              return PieChartSectionData(
                // ✨ Green AI / Orange Manual
                color: isAi ? const Color(0xFF4CAF50) : const Color(0xFFFFA726),
                value: item.percentage,
                title: '${item.percentage.round()}%',
                radius: isAi ? 18 : 14,
                titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
              );
            }).toList(),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${aiItem.percentage.round()}%", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF2D3142), fontFamily: 'Sen')),
            const Text("AI Mode", style: TextStyle(fontSize: 10, color: Color(0xFF9095A5), fontWeight: FontWeight.w500)),
          ],
        )
      ],
    );
  }
}

class _SpeedPreferenceList extends StatelessWidget {
  final List<SpeedDistItem> stats;
  const _SpeedPreferenceList({required this.stats});

  @override
  Widget build(BuildContext context) {
    final sorted = List<SpeedDistItem>.from(stats)..sort((a, b) => b.minutes.compareTo(a.minutes));
    final top3 = sorted.take(3).toList();
    final total = sorted.fold(0.0, (sum, item) => sum + item.minutes);

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: top3.map((item) {
        final ratio = total == 0 ? 0.0 : (item.minutes / total);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Level ${item.speed}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF2D3142))),
                Text("${(ratio * 100).round()}%", style: const TextStyle(fontSize: 10, color: Color(0xFF9095A5))),
              ],
            ),
            const SizedBox(height: 6),
            Stack(
              children: [
                Container(height: 8, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFF0F2F5), borderRadius: BorderRadius.circular(4))),
                FractionallySizedBox(
                  widthFactor: ratio.clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      // ✨ Speed Colors (Soft Green -> Strong Green)
                      color: item.speed <= 2 ? const Color(0xFFAED581) : (item.speed <= 4 ? const Color(0xFF4CAF50) : const Color(0xFF2E7D32)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      }).toList(),
    );
  }
}