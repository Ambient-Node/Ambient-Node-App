import 'package:flutter/material.dart';

class FanControlWidget extends StatelessWidget {
  final int speed; // 현재 풍량 (0 ~ 100)
  final ValueChanged<int> setSpeed; // 풍량 변경 콜백 함수
  final bool powerOn; // 전원 상태

  const FanControlWidget({
    super.key,
    required this.speed,
    required this.setSpeed,
    required this.powerOn,
  });

  @override
  Widget build(BuildContext context) {
    // 0~100 값을 0~5 단계로 변환 (ChatGPT 코드와 동일)
    final int currentStep = (speed / 20).ceil().clamp(0, 5);

    return Column(
      children: [
        // 원형 프로그레스 바
        GestureDetector(
          onTap: () {
            // 전원이 켜져 있을 때만 작동
            if (!powerOn) return;

            // 다음 단계 계산 (20%씩 증가, 100% 다음은 0%)
            int nextSpeed = speed + 20;
            if (nextSpeed > 100) {
              nextSpeed = 0;
            }
            setSpeed(nextSpeed);
          },
          child: SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 원형 프로그레스 바 (배경)
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CircularProgressIndicator(
                    value: 1.0, // 항상 꽉 찬 회색 배경
                    strokeWidth: 12,
                    color: Colors.grey.shade200,
                  ),
                ),
                // 원형 프로그레스 바 (현재 값)
                SizedBox(
                  width: 200,
                  height: 200,
                  child: CircularProgressIndicator(
                    value: powerOn ? speed / 100.0 : 0, // 전원이 꺼져있으면 0
                    strokeWidth: 12,
                    strokeCap: StrokeCap.round, // 부드러운 끝 처리
                    valueColor: AlwaysStoppedAnimation<Color>(
                        powerOn ? Colors.blueAccent : Colors.grey.shade400),
                  ),
                ),
                // 중앙 텍스트 (단계 및 퍼센트)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      powerOn ? '${speed}%' : 'Off',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color:
                            powerOn ? Colors.blueAccent : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (powerOn) // 전원이 켜져 있을 때만 단계를 표시
                      Text(
                        speed == 0 ? '멈춤' : '$currentStep단계',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // 슬라이더 추가 (ChatGPT 코드의 슬라이더 스타일)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Text(
                "풍량 조절",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Slider(
                value: speed.toDouble(),
                min: 0,
                max: 100,
                divisions: 5, // 0, 20, 40, 60, 80, 100
                activeColor: Colors.blueAccent, // ChatGPT와 동일한 색상
                inactiveColor: Colors.grey.shade300,
                onChanged: (value) {
                  setSpeed(value.toInt());
                },
              ),
              Text(
                speed == 0 ? "OFF" : "$currentStep단계",
                style: TextStyle(
                  fontSize: 16,
                  color: speed == 0 ? Colors.grey : Colors.blueAccent.shade400,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
