import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ambient_node/widgets/app_top_bar.dart';
import 'package:ambient_node/screens/timer_setting_screen.dart';
import 'package:ambient_node/widgets/remote_control_dpad.dart';
import 'package:ambient_node/utils/snackbar_helper.dart';

class DashboardScreen extends StatelessWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed;
  final Function(int) setSpeed;
  final String movementMode;
  final bool isNaturalWind;
  final Function(String) onMovementModeChange;
  final Function(bool) onNaturalWindChange;
  final Future<Map<String, dynamic>?> Function(int) onTimerSet;
  final Function(String, int) onManualControl;
  final VoidCallback openAnalytics;
  final String deviceName;
  final String? selectedUserName;
  final String? selectedUserImagePath;

  const DashboardScreen({
    super.key,
    required this.connected,
    required this.onConnect,
    required this.speed,
    required this.setSpeed,
    required this.movementMode,
    required this.isNaturalWind,
    required this.onMovementModeChange,
    required this.onNaturalWindChange,
    required this.onTimerSet,
    required this.onManualControl,
    required this.openAnalytics,
    required this.deviceName,
    this.selectedUserName,
    this.selectedUserImagePath,
  });

  @override
  Widget build(BuildContext context) {
    return FanDashboardWidget(
      connected: connected,
      onConnect: onConnect,
      speed: speed,
      setSpeed: (val) => setSpeed(val.toInt()),
      movementMode: movementMode,
      isNaturalWind: isNaturalWind,
      onMovementModeChange: onMovementModeChange,
      onNaturalWindChange: onNaturalWindChange,
      onTimerSet: onTimerSet,
      onManualControl: onManualControl,
      openAnalytics: openAnalytics,
      deviceName: deviceName,
      selectedUserName: selectedUserName,
      selectedUserImagePath: selectedUserImagePath,
    );
  }
}

class FanDashboardWidget extends StatefulWidget {
  final bool connected;
  final VoidCallback onConnect;
  final int speed;
  final Function(double) setSpeed;
  final String movementMode; 
  final bool isNaturalWind;  
  final Function(String) onMovementModeChange;
  final Function(bool) onNaturalWindChange;
  final Future<Map<String, dynamic>?> Function(int) onTimerSet;
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
    required this.movementMode,
    required this.isNaturalWind,
    required this.onMovementModeChange,
    required this.onNaturalWindChange,
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
    _restoreTimerState();
  }

  @override
  void didUpdateWidget(FanDashboardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.movementMode != oldWidget.movementMode) {
      if (widget.movementMode != 'manual') {
        _isRemoteActive = false;
      }
      _updateRotation();
    }

    if (widget.isNaturalWind != oldWidget.isNaturalWind) {
      _updateRotation();
    }

    if (widget.connected != oldWidget.connected) {
      if (!widget.connected) {
        _isRemoteActive = false;
        _controller.stop();
      } else {
        _updateRotation();
      }
    } else if (widget.speed != oldWidget.speed) {
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

    if (widget.speed > 0 || widget.isNaturalWind) {
      int durationMs;
      if (widget.isNaturalWind) {
        durationMs = 2400;
      } else {
        durationMs = 2400 ~/ widget.speed;
      }
      _controller.duration = Duration(milliseconds: durationMs);
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  Future<void> _restoreTimerState() async {
    final prefs = await SharedPreferences.getInstance();
    final endTimeIso = prefs.getString('timer_end_time');

    if (endTimeIso != null) {
      final endTime = DateTime.parse(endTimeIso);
      final now = DateTime.now();

      if (endTime.isAfter(now)) {
        final remaining = endTime.difference(now);
        setState(() {
          _remainingTime = remaining;
        });
        _startLocalCountdown(endTime);
      } else {
        await prefs.remove('timer_end_time');
      }
    }
  }

  void _startLocalCountdown(DateTime endTime) {
    _countdownTimer?.cancel();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final remaining = endTime.difference(now);

      setState(() {
        if (remaining.inSeconds > 0) {
          _remainingTime = remaining;
        } else {
          // [타이머 종료 시점] UI 강제 초기화
          _remainingTime = null;
          timer.cancel();
          SharedPreferences.getInstance().then((prefs) => prefs.remove('timer_end_time'));

          widget.setSpeed(0.0);
          widget.onNaturalWindChange(false);
          widget.onMovementModeChange('manual');
          
          if(mounted) {
            showAppSnackBar(context, '타이머가 종료되어 전원을 끕니다.', type: AppSnackType.info);
          }
        }
      });
    });
  }

  Future<void> _handleTimerSetting() async {
    final result = await Navigator.push<Duration>(
      context,
      MaterialPageRoute(builder: (context) => TimerSettingScreen(initialDuration: _remainingTime)),
    );

    if (result == null) return;

    final ackData = await widget.onTimerSet(result.inSeconds);

    if (ackData != null) {
      final prefs = await SharedPreferences.getInstance();
      _countdownTimer?.cancel();

      if (result.inSeconds == 0) {
        setState(() => _remainingTime = null);
        await prefs.remove('timer_end_time');
        if(mounted) showAppSnackBar(context, '타이머가 취소되었습니다.', type: AppSnackType.success);
      } else {
        setState(() => _remainingTime = result);
        
        String? serverEndTime = ackData['end_time'];
        final targetEndTime = serverEndTime != null ? DateTime.parse(serverEndTime) : DateTime.now().add(result);
        
        await prefs.setString('timer_end_time', targetEndTime.toIso8601String());
        _startLocalCountdown(targetEndTime);
        
        if(mounted) showAppSnackBar(context, '${result.inMinutes}분 후 종료됩니다.', type: AppSnackType.success);
      }
    } else {
      if(mounted) showAppSnackBar(context, '설정에 실패했습니다 (응답 없음).', type: AppSnackType.error);
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  void _showNatureModeWarning() {
    showAppSnackBar(context, "자연풍 모드에서는 풍량을 조절할 수 없습니다.\n자연풍을 먼저 꺼주세요.", type: AppSnackType.info);
  }

  @override
  Widget build(BuildContext context) {
    final currentSpeed = widget.speed;
    final bool canControlSpeed = widget.connected && !widget.isNaturalWind;
    final Color controlColor = canControlSpeed ? _fanBlue : Colors.grey.shade300;

    // [수정] Scaffold 및 SafeArea 추가하여 다른 화면과 구조 통일
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // UserScreen과 동일한 배경색
      body: SafeArea(
        child: DefaultTextStyle.merge(
          style: const TextStyle(fontFamily: 'Sen'),
          child: Column(
            children: [
              AppTopBar(
                deviceName: widget.connected ? widget.deviceName : "Ambient",
                subtitle: widget.selectedUserName != null ? '${widget.selectedUserName}님' : "대시보드",
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
                                  _buildFanBlades((widget.speed > 0 || widget.isNaturalWind) ? _fanBlue : Colors.grey.shade400),
                                  if (widget.isNaturalWind && widget.connected)
                                    Positioned(top: 0, right: 0, child: Icon(Icons.grass, color: Colors.green[400], size: 28)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _roundControlButton(
                                  icon: Icons.remove,
                                  color: controlColor,
                                  onTap: canControlSpeed
                                      ? () => widget.setSpeed(((currentSpeed - 1).clamp(0, 5)).toDouble())
                                      : () { if (widget.isNaturalWind && widget.connected) _showNatureModeWarning(); },
                                ),
                                const SizedBox(width: 24),
                                Column(
                                  children: [
                                    Text(
                                      widget.isNaturalWind ? "Nature" : '$currentSpeed',
                                      style: TextStyle(
                                        fontSize: widget.isNaturalWind ? 24 : 36,
                                        fontWeight: FontWeight.w800,
                                        color: widget.isNaturalWind ? Colors.green[400] : (widget.connected ? _fanBlue : Colors.grey),
                                        height: 1.0,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                        widget.isNaturalWind ? "자연풍" : "FAN SPEED",
                                        style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold)
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 24),
                                _roundControlButton(
                                  icon: Icons.add,
                                  color: controlColor,
                                  onTap: canControlSpeed
                                      ? () => widget.setSpeed(((currentSpeed + 1).clamp(0, 5)).toDouble())
                                      : () { if (widget.isNaturalWind && widget.connected) _showNatureModeWarning(); },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

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
        ),
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
          label: "타이머",
          isActive: _remainingTime != null,
          onTap: _handleTimerSetting,
        ),

        _buildFunctionButton(
          icon: Icons.face,
          label: "AI 트래킹",
          isActive: widget.movementMode == 'ai_tracking',
          onTap: () {
            final nextMode = widget.movementMode == 'ai_tracking' ? 'manual' : 'ai_tracking';
            widget.onMovementModeChange(nextMode);
          },
        ),

        _buildFunctionButton(
          icon: Icons.sync,
          label: "회전",
          isActive: widget.movementMode == 'rotation',
          onTap: () {
            final nextMode = widget.movementMode == 'rotation' ? 'manual' : 'rotation';
            widget.onMovementModeChange(nextMode);
          },
        ),

        _buildFunctionButton(
          icon: Icons.grass,
          label: "자연풍",
          isActive: widget.isNaturalWind,
          onTap: () {
            widget.onNaturalWindChange(!widget.isNaturalWind);
          },
        ),

        _buildFunctionButton(
          icon: Icons.gamepad_outlined,
          label: "리모컨",
          isActive: false,
          onTap: () {
            if (widget.movementMode != 'manual') {
              widget.onMovementModeChange('manual');
            }
            setState(() {
              _isRemoteActive = true;
            });
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
                "수동 회전 조작",
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
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: isActive ? _fanBlue : const Color(0xFFF5F7FA),
              borderRadius: BorderRadius.circular(16),
              boxShadow: isActive ? [BoxShadow(color: _fanBlue.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))] : [],
            ),
            child: Icon(icon, color: isActive ? Colors.white : Colors.grey[500], size: 22),
          ),
          const SizedBox(height: 6),
          Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isActive ? _fanBlue : Colors.grey[400]
              )
          ),
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