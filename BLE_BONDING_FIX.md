# BLE 본딩 문제 해결 가이드

## 문제 요약
- Android에서 "등록하시겠습니까?" 팝업이 두 번 나타남
- 본딩 실패 후 연결 해제 (status=22: CONNECTION_TERMINATED_BY_LOCAL_HOST)
- 매번 연결 전 캐시 삭제 필요

## 해결 방법

### 1. Flutter 앱 측 수정 (완료)
- `autoConnect: false` 설정으로 자동 재연결 방지
- 연결 전 기존 연결 상태 확인 및 정리
- 연결 후 상태 확인 로직 추가
- 재시도 로직 개선

### 2. 라즈베리파이 측 설정 (필수)

#### 2.1 BlueZ 설정 수정
```bash
sudo nano /etc/bluetooth/main.conf
```

다음 설정을 확인/수정:
```ini
[General]
# 본딩 자동 요청 비활성화
AutoEnable=true
AlwaysPairable=false
PairableTimeout=0

# 보안 모드 설정 (SSP 비활성화)
Class=0x000414
```

#### 2.2 GATT Characteristic 보안 레벨 낮추기
bluezero를 사용하는 경우, characteristic 정의 시 `secure` 매개변수를 빈 리스트로 설정:

```python
from bluezero import characteristic

# 보안 요구사항 없는 characteristic
char = characteristic.Characteristic(
    uuid='12345678-1234-5678-1234-56789abcdef1',
    service=service_path,
    flags=['read', 'write', 'notify'],
    secure=[]  # 빈 리스트 = 보안 요구사항 없음
)
```

또는 bluezero의 다른 방식:
```python
# 보안 없이 characteristic 생성
char = characteristic.Characteristic(
    uuid='12345678-1234-5678-1234-56789abcdef1',
    service=service_path,
    flags=['read', 'write', 'notify']
)
# secure 속성을 명시적으로 설정하지 않으면 기본적으로 보안 없음
```

#### 2.3 기존 본딩 정보 삭제 (필요시)
```bash
# 기존 본딩 정보 확인
ls -la /var/lib/bluetooth/*/

# 특정 기기 본딩 정보 삭제 (MAC 주소 확인 후)
sudo rm -rf /var/lib/bluetooth/*/[MAC_ADDRESS]/

# BlueZ 재시작
sudo systemctl restart bluetooth
```

#### 2.4 SSP 모드 비활성화 (이미 시도함)
```bash
sudo hciconfig hci0 sspmode 0
```

### 3. Android 측 추가 설정

#### 3.1 AndroidManifest.xml 확인
현재 설정은 적절합니다. 추가 권한은 필요 없습니다.

#### 3.2 앱에서 본딩 정보 삭제 (선택사항)
앱 시작 시 또는 연결 전에 기존 본딩 정보를 삭제하려면, Android 플랫폼 채널을 통해 구현할 수 있습니다. 하지만 현재는 Flutter 측에서 처리하지 않습니다.

### 4. 연결 프로세스 개선 사항

#### 4.1 Flutter 앱 변경사항
- `autoConnect: false` 명시적 설정
- 연결 전 기존 연결 상태 확인 및 정리
- 연결 후 상태 확인 로직 추가
- 재시도 시 점진적 대기 시간 적용

#### 4.2 연결 흐름
1. 기존 연결 확인 및 해제
2. `autoConnect: false`로 연결 시도
3. 연결 후 500ms 대기 (본딩 프로세스 완료 대기)
4. 연결 상태 확인
5. 서비스 발견 및 characteristic 설정

### 5. 디버깅 팁

#### 5.1 Android 로그 확인
```bash
adb logcat | grep -E "Bluetooth|FBP|BLE"
```

#### 5.2 라즈베리파이 로그 확인
```bash
sudo journalctl -u bluetooth -f
```

#### 5.3 BlueZ 상태 확인
```bash
bluetoothctl
[bluetooth]# show
[bluetooth]# devices
[bluetooth]# info [MAC_ADDRESS]
```

### 6. 추가 해결 방법 (문제 지속 시)

#### 6.1 라즈베리파이에서 GATT 서버 재시작
```bash
# GATT 서버를 실행하는 스크립트/서비스 재시작
sudo systemctl restart your-gatt-service
```

#### 6.2 Android Bluetooth 캐시 삭제
- 설정 > 앱 > 앱 정보 > 저장 공간 > 캐시 삭제
- 또는 앱 삭제 후 재설치

#### 6.3 라즈베리파이 Bluetooth 어댑터 재시작
```bash
sudo hciconfig hci0 down
sudo hciconfig hci0 up
```

### 7. 예상 결과

수정 후:
- "등록하시겠습니까?" 팝업이 나타나지 않거나 한 번만 나타남
- 본딩 없이 직접 GATT 연결 성공
- 연결 후 데이터 전송 정상 동작
- 매번 캐시 삭제 불필요

### 8. 문제 지속 시 확인사항

1. **라즈베리파이 GATT 서버 설정 확인**
   - Characteristic의 보안 플래그가 올바르게 설정되었는지
   - Service의 보안 요구사항이 없는지

2. **Android 버전 확인**
   - Android 12+ 에서는 BLE 권한 처리 방식이 변경됨
   - 현재 AndroidManifest.xml 설정이 적절한지 확인

3. **flutter_blue_plus 버전**
   - 현재: 1.34.5
   - 최신 버전으로 업데이트 고려

4. **BlueZ 버전**
   - 현재: 5.66
   - 최신 버전으로 업데이트 고려

## 참고 자료

- [flutter_blue_plus 문서](https://pub.dev/packages/flutter_blue_plus)
- [BlueZ 공식 문서](http://www.bluez.org/)
- [bluezero 문서](https://github.com/ukBaz/python-bluezero)

