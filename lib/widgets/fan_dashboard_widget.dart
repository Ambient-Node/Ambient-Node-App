import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';
import 'package:ambient_node/screens/timer_setting_screen.dart';
import 'package:ambient_node/widgets/remote_control_dpad.dart';

class FanDashboardWidget extends StatefulWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed; // 0~5 단계
  final Function(double) setSpeed;

  // 모드 및 상태
  final String currentMode;
  final Function(String) onModeChange;
  final Function(int) onTimerSet;

  final VoidCallback openAnalytics;
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
    required this.currentMode,
    required this.onModeChange,
    required this.onTimerSet,
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

  bool _isRemoteActive = false;
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
    // 연결, 속도, 모드 변경 시 애니메이션 및 상태 업데이트
    if (widget.connected != oldWidget.connected ||
        widget.speed != oldWidget.speed ||
        widget.currentMode != oldWidget.currentMode) {
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
    if (!widget.connected) {
      _controller.stop();
      return;
    }

    final bool isNature = widget.currentMode == 'natural_wind';

    // 속도가 있거나 자연풍 모드일 때 회전
    if (widget.speed > 0 || isNature) {
      int durationMs;
      if (isNature) {
        // 자연풍: 속도 1과 동일하게 (느리게)
        durationMs = 2400;
      } else {
        // 일반: 속도에 따라 (속도 1=2400ms ~ 속도 5=480ms)
        durationMs = 2400 ~/ widget.speed;
      }
      _controller.duration = Duration(milliseconds: durationMs);
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  Future<void> _handleTimerSetting() async {
    final result = await Navigator.push<Duration>(
      context,
      MaterialPageRoute(builder: (context) => TimerSettingScreen(initialDuration: _remainingTime)),
    );

    if (result != null) {
      widget.onTimerSet(result.inSeconds); // 메인으로 전송

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

  // ★ [안내 메시지] 자연풍 모드일 때 조작 시도 시 호출
  void _showNatureModeWarning() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "자연풍 모드에서는 풍량을 조절할 수 없습니다.\n자연풍을 먼저 꺼주세요.",
          style: TextStyle(fontFamily: 'Sen', color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2D3142),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSpeed = widget.speed;
    final bool isNature = widget.currentMode == 'natural_wind';

    // ★ 자연풍이거나 연결 끊김 상태면 컨트롤 색상을 회색으로 처리
    final bool canControlSpeed = widget.connected && !isNature;
    final Color controlColor = canControlSpeed ? _fanBlue : Colors.grey.shade300;

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

                  // 2. 메인 팬 & 속도 제어 패널
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Column(
                      children: [
                        // A. 팬 비주얼
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
                              _buildFanBlades(canControlSpeed || isNature ? _fanBlue : Colors.grey.shade400), // 비주얼은 자연풍일 때도 파란색 유지
                              if (isNature && widget.connected)
                                Positioned(top: 0, right: 0, child: Icon(Icons.grass, color: Colors.green[400], size: 28)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ★ [수정됨] B. 속도 조절 (자연풍 모드 시 버튼 잠금 로직 적용)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // (-) 버튼
                            _roundControlButton(
                              icon: Icons.remove,
                              color: controlColor, // 회색 or 파란색
                              onTap: canControlSpeed
                                  ? () => widget.setSpeed(((currentSpeed - 1).clamp(0, 5)).toDouble())
                                  : () {
                                // 자연풍 모드인데 버튼 누르면 경고 메시지
                                if (isNature && widget.connected) _showNatureModeWarning();
                              },
                            ),
                            const SizedBox(width: 24),

                            // 중앙 텍스트
                            Column(
                              children: [
                                Text(
                                  isNature ? "Nature" : '$currentSpeed',
                                  style: TextStyle(
                                    fontSize: isNature ? 24 : 36,
                                    fontWeight: FontWeight.w800,
                                    color: isNature ? Colors.green[400] : (widget.connected ? _fanBlue : Colors.grey),
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                    isNature ? "MODE ACTIVE" : "FAN SPEED",
                                    style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold)
                                ),
                              ],
                            ),

                            const SizedBox(width: 24),

                            // (+) 버튼
                            _roundControlButton(
                              icon: Icons.add,
                              color: controlColor, // 회색 or 파란색
                              onTap: canControlSpeed
                                  ? () => widget.setSpeed(((currentSpeed + 1).clamp(0, 5)).toDouble())
                                  : () {
                                if (isNature && widget.connected) _showNatureModeWarning();
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. 하단 패널
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 400),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: _isRemoteActive
                          ? _buildRemoteControlPanel()
                          : _buildFunctionButtonsRow(),
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

  Widget _buildFunctionButtonsRow() {
    return Row(
      key: const ValueKey('buttons'),
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
          label: "Tracking",
          isActive: widget.currentMode == 'ai_tracking',
          onTap: () {
            final nextMode = widget.currentMode == 'ai_tracking' ? 'manual_control' : 'ai_tracking';
            widget.onModeChange(nextMode);
          },
        ),
        _buildFunctionButton(
          icon: Icons.grass,
          label: "Nature",
          isActive: widget.currentMode == 'natural_wind',
          onTap: () {
            final nextMode = widget.currentMode == 'natural_wind' ? 'manual_control' : 'natural_wind';
            widget.onModeChange(nextMode);
          },
        ),
        _buildFunctionButton(
          icon: Icons.gamepad_outlined,
          label: "Remote",
          isActive: false,
          onTap: () {
            setState(() {
              _isRemoteActive = true;
            });
            // 리모컨 진입 시 수동 모드 변경
            if (widget.currentMode != 'manual_control') {
              widget.onModeChange('manual_control');
            }
          },
        ),
      ],
    );
  }

  Widget _buildRemoteControlPanel() {
    return Column(
      key: const ValueKey('remote'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 8, right: 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Manual Control",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2D3142)),
              ),
              IconButton(
                onPressed: () => setState(() => _isRemoteActive = false),
                icon: const Icon(Icons.close_rounded, color: Colors.grey),
                visualDensity: VisualDensity.compact,
              )
            ],
          ),
        ),
        SizedBox(
          height: 240,
          child: RemoteControlDpad(
            size: 220,
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
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _roundControlButton({required IconData icon, required VoidCallback onTap, required Color color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, size: 24, color: color),
      ),
    );
  }

  Widget _buildFunctionButton({required IconData icon, required String label, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: widget.connected ? onTap : null,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: isActive ? _fanBlue : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(18),
              boxShadow: isActive ? [BoxShadow(color: _fanBlue.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
            ),
            child: Icon(icon, color: isActive ? Colors.white : Colors.grey[500], size: 24),
          ),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? _fanBlue : Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildFanBlades(Color color) {
    Widget blade(double angle) {
      return Transform.rotate(
        angle: angle,
        child: Container(
          width: 20, height: 85,
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
          children: [
            blade(0),
            blade(2 * math.pi / 3),
            blade(4 * math.pi / 3),
            Container(width: 32, height: 32, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]))
          ],
        ),
      ),
    );
  }
}