import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class TimerSettingScreen extends StatefulWidget {
  final Duration? initialDuration;

  const TimerSettingScreen({super.key, this.initialDuration});

  @override
  State<TimerSettingScreen> createState() => _TimerSettingScreenState();
}

class _TimerSettingScreenState extends State<TimerSettingScreen> {
  Duration _selectedDuration = const Duration(minutes: 60);

  @override
  void initState() {
    super.initState();
    if (widget.initialDuration != null && widget.initialDuration!.inSeconds > 0) {
      _selectedDuration = widget.initialDuration!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("타이머 설정", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 40),
          const Text(
            "종료 예약",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            "설정된 시간 후에 기기가 자동으로 꺼집니다.",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),

          Expanded(
            child: CupertinoTimerPicker(
              mode: CupertinoTimerPickerMode.hm,
              initialTimerDuration: _selectedDuration,
              onTimerDurationChanged: (Duration newDuration) {
                setState(() => _selectedDuration = newDuration);
              },
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, Duration.zero);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    child: const Text("해제"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context, _selectedDuration);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3A91FF),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    child: const Text("설정 완료"),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}