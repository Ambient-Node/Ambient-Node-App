import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';
// [필수] Analytics 모델과 서비스 import
import 'package:ambient_node/models/user_analytics.dart'; // UserAnalytics 모델 파일 경로 확인
import 'package:ambient_node/services/analytics_service.dart';
// [필수] TimerSettingScreen import
import 'package:ambient_node/screens/timer_setting_screen.dart';

class FanDashboardWidget extends StatefulWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed;
  final Function(double) setSpeed;
  final bool trackingOn;
  final Function(bool) setTrackingOn;
  final VoidCallback openAnalytics;
  final VoidCallback onRemoteTap;
  final String deviceName;
  final String? selectedUserName;
  final String? selectedUserImagePath;

  const FanDashboardWidget({
    super.key,
    required this.connected,
    required this.onConnect,
    required this.speed,
    required this.setSpeed,
    required this.trackingOn,
    required this.setTrackingOn,
    required this.openAnalytics,
    required this.onRemoteTap,
    this.deviceName = 'Ambient',
    this.selectedUserName,
    this.selectedUserImagePath,
  });

  @override
  State<FanDashboardWidget> createState() => _FanDashboardWidgetState();
}

class _FanDashboardWidgetState extends State<FanDashboardWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const Color _fanBlue = Color(0xFF3A91FF);

  bool _isNatureMode = false;
  Timer? _countdownTimer;
  Duration? _remainingTime;

  // 분석 데이터 상태
  String _todayUsageText = "-분";
  String _todayManualCountText = "-회";

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    if (widget.connected) _updateRotation();
    _loadAnalyticsData(); // 초기 데이터 로드
  }

  @override
  void didUpdateWidget(FanDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected != oldWidget.connected ||
        widget.speed != oldWidget.speed) {
      _updateRotation();
    }
    // 사용자가 바뀌거나 연결 상태가 바뀌면 데이터 갱신
    if (widget.selectedUserName != oldWidget.selectedUserName ||
        widget.connected != oldWidget.connected) {
      _loadAnalyticsData();
    }
  }

  // ★ [핵심 로직] 데이터 로드 및 포맷팅
  Future<void> _loadAnalyticsData() async {
    if (widget.selectedUserName == null) {
      if (mounted) {
        setState(() {
          _todayUsageText = "-분";
          _todayManualCountText = "-회";
        });
      }
      return;
    }

    try {
      // AnalyticsService에서 데이터 가져오기 (비동기 가정)
      UserAnalytics? analytics = await AnalyticsService.getUserAnalytics(widget.selectedUserName!);

      if (analytics == null) return;

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // 1. 오늘 사용 시간 계산
      Duration totalDuration = Duration.zero;
      for (var session in analytics.fanSessions) {
        // 세션이 오늘 날짜 범위에 걸쳐있는지 확인 (단순화: 시작 시간이 오늘인 경우)
        if (session.startTime.isAfter(todayStart) && session.startTime.isBefore(todayEnd)) {
          totalDuration += session.duration;
        }
      }

      // 2. 오늘 수동 제어 횟수 계산
      int manualCount = 0;
      for (var control in analytics.manualControls) {
        if (control.timestamp.isAfter(todayStart) && control.timestamp.isBefore(todayEnd)) {
          manualCount++;
        }
      }

      // 3. 포맷팅 및 UI 업데이트
      if (mounted) {
        setState(() {
          // 시간 포맷팅
          int totalMin = totalDuration.inMinutes;
          if (totalMin < 60) {
            _todayUsageText = "${totalMin}분";
          } else {
            int hours = totalMin ~/ 60;
            int mins = totalMin % 60;
            _todayUsageText = "${hours}시간 ${mins}분";
          }

          // 횟수 포맷팅
          _todayManualCountText = "${manualCount}회";
        });
      }

    } catch (e) {
      print("Analytics load error: $e");
    }
  }

  // ... (기존 _updateRotation, _handleTimerSetting, dispose 로직 유지) ...
  @override
  void dispose() {
    _controller.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _updateRotation() {
    if (widget.connected && widget.speed > 0) {
      final durationMs = 2400 ~/ widget.speed;
      _controller.duration = Duration(milliseconds: durationMs);
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  Future<void> _handleTimerSetting() async {
    // (기존과 동일하여 생략, 필요시 이전 답변 코드 참조)
    final result = await Navigator.push<Duration>(
      context,
      MaterialPageRoute(
        builder: (context) => TimerSettingScreen(initialDuration: _remainingTime),
      ),
    );

    if (result != null) {
      _countdownTimer?.cancel();

      if (result.inSeconds == 0) {
        setState(() => _remainingTime = null); // 해제
      } else {
        setState(() => _remainingTime = result);
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) return;
          setState(() {
            if (_remainingTime!.inSeconds > 0) {
              _remainingTime = _remainingTime! - const Duration(seconds: 1);
            } else {
              widget.setSpeed(0);
              _remainingTime = null;
              timer.cancel();
            }
          });
        });
      }
    }
  }

  // ... (기존 _wrapMaxWidth 로직 유지) ...
  Widget _wrapMaxWidth(Widget child) {
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: child,
      ),
    );
  }

  // ... (기존 _roundControlButton 로직 유지) ...
  Widget _roundControlButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    double iconSize = 15,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              )
            ]
        ),
        child: Icon(icon, size: iconSize, color: color),
      ),
    );
  }

  // ... (기존 _buildFunctionButton 로직 유지) ...
  Widget _buildFunctionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: widget.connected ? onTap : null,
      child: Column(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: isActive ? _fanBlue.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: isActive
                  ? Border.all(color: _fanBlue, width: 1.5)
                  : null,
            ),
            child: Icon(
              icon,
              color: widget.connected
                  ? (isActive ? _fanBlue : Colors.grey[600])
                  : Colors.grey[300],
              size: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.connected
                  ? (isActive ? _fanBlue : Colors.grey[600])
                  : Colors.grey[300],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String hours = twoDigits(d.inHours);
    String minutes = twoDigits(d.inMinutes.remainder(60));
    String seconds = twoDigits(d.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    // ... (기존 build 구조 유지, 하단 infoCard 부분만 수정) ...
    final currentSpeed = widget.speed;
    final color = (widget.connected && currentSpeed > 0)
        ? _fanBlue
        : Colors.grey.shade400;

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Sen'),
      child: Column(
        children: [
          AppTopBar(
            deviceName: widget.connected ? widget.deviceName : "Ambient",
            subtitle: widget.selectedUserName != null
                ? '${widget.selectedUserName} 선택 중'
                : "Lab Fan",
            connected: widget.connected,
            onConnectToggle: widget.onConnect,
            userImagePath: widget.selectedUserImagePath,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                children: [
                  // 타이머 표시 (기존 코드)
                  if (_remainingTime != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _fanBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _fanBlue.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.timer_outlined, size: 16, color: _fanBlue),
                            const SizedBox(width: 8),
                            Text(
                              "${_formatDuration(_remainingTime!)} 후 종료",
                              style: const TextStyle(color: _fanBlue, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 메인 팬 컨트롤 (기존 코드 유지)
                  _wrapMaxWidth(Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 240,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 220, height: 220,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const RadialGradient(colors: [Colors.white, Color(0xFFF0F5FA)]),
                                  border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
                                ),
                              ),
                              _buildFanBlades(color),
                              if (_isNatureMode && widget.connected)
                                Positioned(top: 10, right: 10, child: Icon(Icons.grass, color: Colors.green[400])),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _roundControlButton(
                              icon: Icons.remove,
                              onTap: widget.connected ? () => widget.setSpeed(((currentSpeed - 1).clamp(0, 5)).toDouble()) : () {},
                              color: widget.connected ? _fanBlue : Colors.grey.shade300,
                              iconSize: 24,
                            ),
                            Column(
                              children: [
                                Text(
                                  _isNatureMode ? "자연풍" : '$currentSpeed',
                                  style: TextStyle(
                                    fontSize: _isNatureMode ? 24 : 40,
                                    fontWeight: FontWeight.w700,
                                    color: widget.connected ? _fanBlue : Colors.grey,
                                  ),
                                ),
                                Text(
                                  _isNatureMode ? "Nature Mode" : "Speed Level",
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                            _roundControlButton(
                              icon: Icons.add,
                              onTap: widget.connected ? () => widget.setSpeed(((currentSpeed + 1).clamp(0, 5)).toDouble()) : () {},
                              color: widget.connected ? _fanBlue : Colors.grey.shade300,
                              iconSize: 24,
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),

                  const SizedBox(height: 20),

                  // 기능 버튼 4개 (기존 코드 유지)
                  _wrapMaxWidth(Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildFunctionButton(icon: Icons.timer_outlined, label: "타이머", isActive: _remainingTime != null, onTap: _handleTimerSetting),
                        _buildFunctionButton(icon: Icons.sync, label: "회전", isActive: widget.trackingOn, onTap: () => widget.setTrackingOn(!widget.trackingOn)),
                        _buildFunctionButton(icon: Icons.grass, label: "자연풍", isActive: _isNatureMode, onTap: () { setState(() { _isNatureMode = !_isNatureMode; }); }),
                        _buildFunctionButton(icon: Icons.gamepad_outlined, label: "리모컨", isActive: false, onTap: widget.onRemoteTap),
                      ],
                    ),
                  )),

                  const SizedBox(height: 20),

                  // ★ [수정됨] 실시간 분석 데이터 카드
                  _wrapMaxWidth(Row(
                    children: [
                      Expanded(
                          child: _infoCard(
                            label: "오늘 사용",
                            value: _todayUsageText, // 계산된 값 사용
                            icon: Icons.access_time_filled,
                            iconColor: Colors.orangeAccent,
                          )
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                          child: _infoCard(
                            label: "수동 제어",
                            value: _todayManualCountText, // 계산된 값 사용
                            icon: Icons.touch_app,
                            iconColor: _fanBlue,
                          )
                      ),
                    ],
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ... (기존 _buildFanBlades 로직 유지) ...
  Widget _buildFanBlades(Color color) {
    Widget blade(double angle) {
      return Transform.rotate(
        angle: angle,
        child: Container(
          width: 24, height: 110,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [color.withOpacity(0.9), color.withOpacity(0.2)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Transform.rotate(
        angle: _controller.value * 2 * math.pi,
        child: Stack(
          alignment: Alignment.center,
          children: [blade(0), blade(2 * math.pi / 3), blade(4 * math.pi / 3), Container(width: 38, height: 38, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]))],
        ),
      ),
    );
  }

  // ★ [디자인 개선] 정보 카드 위젯
  Widget _infoCard({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF838699),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, size: 18, color: iconColor),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20, // 폰트 사이즈 조정 (긴 텍스트 대응)
              fontWeight: FontWeight.w700,
              color: Color(0xFF32343E),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}