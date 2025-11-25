import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';
import 'package:ambient_node/screens/timer_setting_screen.dart';
// [필수] 리모컨 위젯 import
import 'package:ambient_node/widgets/remote_control_dpad.dart';

class FanDashboardWidget extends StatefulWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed;
  final Function(double) setSpeed;
  final bool trackingOn;
  final Function(bool) setTrackingOn;
  final VoidCallback openAnalytics;
  // [수정] 직접 제어 콜백
  final Function(String, int) onManualControl;
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
    required this.onManualControl,
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.connected) _updateRotation();
  }

  @override
  void didUpdateWidget(FanDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.connected != oldWidget.connected ||
        widget.speed != oldWidget.speed) {
      _updateRotation();
    }
  }

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

  // ... (타이머 로직 등 기존 헬퍼 메소드 유지) ...
  Future<void> _handleTimerSetting() async {
    final result = await Navigator.push<Duration>(
      context,
      MaterialPageRoute(builder: (context) => TimerSettingScreen(initialDuration: _remainingTime)),
    );
    if (result != null) {
      _countdownTimer?.cancel();
      if (result.inSeconds == 0) {
        setState(() => _remainingTime = null);
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

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  @override
  Widget build(BuildContext context) {
    final currentSpeed = widget.speed;
    final color = (widget.connected && currentSpeed > 0) ? _fanBlue : Colors.grey.shade400;

    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: 'Sen'),
      child: Column(
        children: [
          AppTopBar(
            deviceName: widget.connected ? widget.deviceName : "Ambient",
            subtitle: widget.selectedUserName != null ? '${widget.selectedUserName}님' : "Dashboard",
            connected: widget.connected,
            onConnectToggle: widget.onConnect,
            userImagePath: widget.selectedUserImagePath,
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // 1. 타이머 표시
                  if (_remainingTime != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: _fanBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _fanBlue.withOpacity(0.3)),
                        ),
                        child: Text(
                          "${_formatDuration(_remainingTime!)} 후 종료",
                          style: const TextStyle(color: _fanBlue, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),

                  // 2. 통합 컨트롤 패널 (팬 비주얼 + 속도 제어 + 방향 제어)
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // A. 팬 비주얼 (크기 축소: 240 -> 180)
                        SizedBox(
                          height: 180,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 160, height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const RadialGradient(colors: [Colors.white, Color(0xFFF0F5FA)]),
                                  border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
                                ),
                              ),
                              _buildFanBlades(color), // 기존 팬 블레이드 위젯 (크기 자동 조정됨)
                              if (_isNatureMode && widget.connected)
                                Positioned(top: 0, right: 0, child: Icon(Icons.grass, color: Colors.green[400])),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // B. 속도 조절 (Speed Control)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _roundControlButton(
                              icon: Icons.remove,
                              onTap: widget.connected
                                  ? () => widget.setSpeed(((currentSpeed - 1).clamp(0, 5)).toDouble())
                                  : () {},
                              color: widget.connected ? _fanBlue : Colors.grey.shade300,
                            ),
                            const SizedBox(width: 24),
                            Column(
                              children: [
                                Text(
                                  _isNatureMode ? "Nature" : '$currentSpeed',
                                  style: TextStyle(
                                    fontSize: _isNatureMode ? 20 : 36,
                                    fontWeight: FontWeight.w800,
                                    color: widget.connected ? _fanBlue : Colors.grey,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "FAN SPEED",
                                  style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(width: 24),
                            _roundControlButton(
                              icon: Icons.add,
                              onTap: widget.connected
                                  ? () => widget.setSpeed(((currentSpeed + 1).clamp(0, 5)).toDouble())
                                  : () {},
                              color: widget.connected ? _fanBlue : Colors.grey.shade300,
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),
                        const Divider(height: 1, indent: 20, endIndent: 20),
                        const SizedBox(height: 24),

                        // C. 모터 제어 (Motor Control - D-Pad)
                        // 통계 카드 자리에 리모컨을 배치
                        Text(
                          "MOTOR CONTROL",
                          style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                        ),
                        const SizedBox(height: 16),

                        // D-Pad 위젯 (크기 적절히 조절)
                        SizedBox(
                          height: 220, // 충분한 터치 영역 확보
                          child: RemoteControlDpad(
                            size: 200, // 너무 크지 않게 조절
                            onUp: () => widget.onManualControl('up', 1),
                            onUpEnd: () => widget.onManualControl('up', 0),
                            onDown: () => widget.onManualControl('down', 1),
                            onDownEnd: () => widget.onManualControl('down', 0),
                            onLeft: () => widget.onManualControl('left', 1),
                            onLeftEnd: () => widget.onManualControl('left', 0),
                            onRight: () => widget.onManualControl('right', 1),
                            onRightEnd: () => widget.onManualControl('right', 0),
                            onCenter: () => widget.onManualControl('center', 1),
                            onCenterEnd: () => widget.onManualControl('center', 0),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. 부가 기능 버튼들 (가로 배치)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildFunctionButton(
                          icon: Icons.timer_outlined,
                          label: "Timer",
                          isActive: _remainingTime != null,
                          onTap: _handleTimerSetting,
                        ),
                        _buildFunctionButton(
                          icon: Icons.sync,
                          label: "Tracking", // AI 모드
                          isActive: widget.trackingOn,
                          onTap: () => widget.setTrackingOn(!widget.trackingOn),
                        ),
                        _buildFunctionButton(
                          icon: Icons.grass,
                          label: "Nature",
                          isActive: _isNatureMode,
                          onTap: () => setState(() => _isNatureMode = !_isNatureMode),
                        ),
                        // 리모컨 버튼은 이제 필요 없으므로 삭제하거나 다른 기능(예: 설정)으로 대체 가능
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 버튼 스타일 위젯들 (기존 로직 사용)
  Widget _roundControlButton({required IconData icon, required VoidCallback onTap, required Color color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 24, color: color),
      ),
    );
  }

  // 기능 버튼 빌더 (기존과 동일)
  Widget _buildFunctionButton({required IconData icon, required String label, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: widget.connected ? onTap : null,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isActive ? _fanBlue : Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              boxShadow: isActive ? [BoxShadow(color: _fanBlue.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
            ),
            child: Icon(icon, color: isActive ? Colors.white : Colors.grey[500], size: 22),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? _fanBlue : Colors.grey[400])),
        ],
      ),
    );
  }

  // 팬 날개 빌드 함수 (기존과 동일)
  Widget _buildFanBlades(Color color) {
    Widget blade(double angle) {
      return Transform.rotate(
        angle: angle,
        child: Container(
          width: 20, height: 85, // 사이즈 축소
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
          children: [blade(0), blade(2 * math.pi / 3), blade(4 * math.pi / 3), Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]))],
        ),
      ),
    );
  }
}