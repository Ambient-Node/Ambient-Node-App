# BLE 서비스 사용 가이드

## 개요

이 문서는 Flutter 앱에서 BLE (Bluetooth Low Energy) 디바이스와 직접 통신하기 위한 `BleService` 클래스의 사용 방법을 설명합니다.

Python BLE Gateway 없이 앱이 단독으로 BLE 디바이스를 제어할 수 있습니다.

## 주요 기능

- ✅ BLE 디바이스 스캔 및 검색
- ✅ 디바이스 연결/해제 및 상태 모니터링
- ✅ JSON 형식 데이터 송수신
- ✅ 대용량 데이터 청크 전송 지원
- ✅ 자동 재연결 로직
- ✅ 상세한 에러 핸들링

## 설치 및 설정

### 1. 의존성 확인

`pubspec.yaml`에 다음 패키지가 포함되어 있어야 합니다:

```yaml
dependencies:
  flutter_blue_plus: ^1.34.5
  permission_handler: ^11.3.1
```

### 2. Android 권한 설정

`android/app/src/main/AndroidManifest.xml`에 다음 권한이 필요합니다:

```xml
<uses-permission android:name="android.permission.BLUETOOTH"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

### 3. iOS 권한 설정

`ios/Runner/Info.plist`에 다음 키가 필요합니다:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>BLE 디바이스와 통신하기 위해 블루투스 권한이 필요합니다.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>BLE 디바이스와 통신하기 위해 블루투스 권한이 필요합니다.</string>
```

## 기본 사용법

### 1. 서비스 초기화

```dart
import 'package:ambient_node/services/ble_service.dart';

final bleService = BleService();
```

### 2. 콜백 설정

```dart
// 연결 상태 변경 콜백
bleService.onConnectionStateChanged = (isConnected) {
  print('연결 상태: ${isConnected ? "연결됨" : "연결 해제됨"}');
  // UI 업데이트 등
};

// 디바이스 이름 변경 콜백
bleService.onDeviceNameChanged = (deviceName) {
  print('디바이스 이름: $deviceName');
};

// 데이터 수신 콜백
bleService.onDataReceived = (data) {
  print('수신 데이터: $data');
  // 수신된 데이터 처리
};

// 에러 콜백
bleService.onError = (error) {
  print('BLE 오류: $error');
  // 에러 처리 (사용자 알림 등)
};
```

### 3. 디바이스 스캔

```dart
// 스캔 시작
final scanStream = bleService.startScan(
  timeout: const Duration(seconds: 30),
  namePrefix: 'Ambient', // 디바이스 이름 필터
);

// 스캔 결과 수신
scanStream.listen((devices) {
  print('발견된 디바이스: ${devices.length}개');
  for (final device in devices) {
    print('- ${device.platformName} (${device.remoteId})');
  }
});

// 스캔 중지
bleService.stopScan();
```

### 4. 디바이스 연결

```dart
// 특정 디바이스에 연결
final success = await bleService.connectToDevice(
  device,
  timeout: const Duration(seconds: 15),
  autoReconnect: true, // 자동 재연결 활성화
);

if (success) {
  print('연결 성공!');
} else {
  print('연결 실패');
}
```

### 5. 데이터 전송

```dart
// JSON 데이터 전송
await bleService.sendJson({
  'speed': 80,
  'trackingOn': true,
  'action': 'manual_control',
  'direction': 'up',
});

// 대용량 데이터는 자동으로 청크 단위로 분할되어 전송됩니다.
```

### 6. 연결 해제

```dart
await bleService.disconnect();
```

### 7. 리소스 정리

```dart
await bleService.dispose();
```

## 고급 사용법

### 연결 상태 확인

```dart
if (bleService.isConnected) {
  print('연결됨');
  final device = bleService.connectedDevice;
  print('연결된 디바이스: ${device?.platformName}');
}
```

### 스캔된 디바이스 목록 확인

```dart
final devices = bleService.scannedDevices;
print('스캔된 디바이스: ${devices.length}개');
```

### 권한 확인 및 요청

```dart
final hasPermission = await bleService.requestPermissions();
if (!hasPermission) {
  print('권한이 필요합니다');
}
```

### 블루투스 상태 확인

```dart
final isEnabled = await bleService.isBluetoothEnabled();
if (!isEnabled) {
  print('블루투스를 켜주세요');
}
```

## 데이터 형식

### 전송 데이터 예시

```dart
// 팬 속도 제어
await bleService.sendJson({
  'speed': 80, // 0-100
  'trackingOn': true,
});

// 수동 제어
await bleService.sendJson({
  'action': 'manual_control',
  'direction': 'up', // 'up', 'down', 'left', 'right', 'center'
});

// 사용자 선택
await bleService.sendJson({
  'action': 'select_user',
  'user_id': 'user123',
});

// 사용자 등록
await bleService.sendJson({
  'action': 'register_user',
  'name': '홍길동',
  'image_base64': '...', // Base64 인코딩된 이미지
});
```

### 수신 데이터 예시

```dart
bleService.onDataReceived = (data) {
  final type = data['type'];
  
  if (type == 'ACK') {
    print('전송 확인: ${data['topic']}');
  } else if (type == 'STATUS_UPDATE') {
    print('상태 업데이트: ${data['data']}');
  }
};
```

## 에러 처리

### 일반적인 에러

1. **권한 오류**: `requestPermissions()` 호출 필요
2. **블루투스 꺼짐**: 사용자에게 블루투스 활성화 요청
3. **연결 타임아웃**: 디바이스가 범위 내에 있는지 확인
4. **서비스 발견 실패**: UUID가 올바른지 확인

### 에러 핸들링 예시

```dart
bleService.onError = (error) {
  if (error.contains('권한')) {
    // 권한 요청 UI 표시
  } else if (error.contains('블루투스')) {
    // 블루투스 활성화 안내
  } else if (error.contains('연결')) {
    // 재연결 시도 또는 사용자 알림
  }
};
```

## 자동 재연결

`connectToDevice()` 호출 시 `autoReconnect: true`로 설정하면, 연결이 끊어졌을 때 자동으로 재연결을 시도합니다.

```dart
await bleService.connectToDevice(
  device,
  autoReconnect: true, // 자동 재연결 활성화
);
```

재연결은 3초 간격으로 시도되며, 수동으로 연결 해제한 경우에는 재연결하지 않습니다.

## 청크 전송

480 바이트를 초과하는 데이터는 자동으로 청크 단위로 분할되어 전송됩니다.

```dart
// 대용량 데이터 (자동 청크 분할)
await bleService.sendJson({
  'action': 'register_user',
  'name': '홍길동',
  'image_base64': '...', // 큰 Base64 문자열
});
```

청크 전송 과정은 자동으로 처리되며, 수신 측에서도 자동으로 재조립됩니다.

## UUID 설정

BLE 서비스는 다음 UUID를 사용합니다 (라즈베리파이 `ble_gateway.py`와 동일):

- **Service UUID**: `12345678-1234-5678-1234-56789abcdef0`
- **Write Characteristic UUID**: `12345678-1234-5678-1234-56789abcdef1`
- **Notify Characteristic UUID**: `12345678-1234-5678-1234-56789abcdef2`

이 값들은 `ble_service.dart` 파일 상단의 상수로 정의되어 있습니다.

## 디버깅

모든 BLE 작업은 콘솔에 상세한 로그를 출력합니다:

```
[BLE] 스캔 시작 (타임아웃: 30초)
[BLE] 디바이스 발견: AmbientNode (AA:BB:CC:DD:EE:FF)
[BLE] 연결 시도: AmbientNode (AA:BB:CC:DD:EE:FF)
[BLE] GATT 연결 성공
[BLE] 서비스 발견 시작...
[BLE] 대상 서비스 발견: 12345678-1234-5678-1234-56789abcdef0
[BLE] 연결 완료: AmbientNode
[BLE] 데이터 전송: 45 바이트
[BLE] 전송 완료
```

## 테스트 시나리오

### 1. 기본 연결 테스트

1. 앱 실행
2. 블루투스 권한 승인
3. 디바이스 선택 화면에서 "다시 스캔" 클릭
4. "Ambient"로 시작하는 디바이스 확인
5. 디바이스 선택하여 연결
6. 연결 상태 확인 (상단바 아이콘 변경)

### 2. 데이터 전송 테스트

1. 연결 후 대시보드 화면으로 이동
2. 팬 속도 조절 슬라이더 조작
3. 콘솔에서 전송 로그 확인
4. 디바이스에서 데이터 수신 확인

### 3. 자동 재연결 테스트

1. 디바이스 연결
2. 디바이스 전원 끄기 또는 범위 밖으로 이동
3. 3초 후 자동 재연결 시도 확인
4. 디바이스 전원 켜기 또는 범위 내로 이동
5. 자동 재연결 성공 확인

### 4. 연결 해제 테스트

1. 연결된 상태에서 상단바 블루투스 아이콘 클릭
2. 연결 해제 확인
3. 상태 초기화 확인 (속도 0, 추적 OFF)

## 문제 해결

### 연결이 안 될 때

1. 블루투스가 켜져 있는지 확인
2. 권한이 모두 승인되었는지 확인
3. 디바이스가 스캔 범위 내에 있는지 확인
4. 디바이스 이름이 "Ambient"로 시작하는지 확인
5. 콘솔 로그 확인

### 데이터 전송이 안 될 때

1. 연결 상태 확인 (`bleService.isConnected`)
2. Write Characteristic이 올바르게 설정되었는지 확인
3. 콘솔 로그에서 에러 메시지 확인
4. 전송 데이터 형식 확인 (JSON)

### 권한 오류

1. Android 12+ 에서는 `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` 권한 필요
2. Android 10 이하에서는 `ACCESS_FINE_LOCATION` 권한 필요
3. 앱 설정에서 권한 수동 확인

## 참고 자료

- [flutter_blue_plus 문서](https://pub.dev/packages/flutter_blue_plus)
- [permission_handler 문서](https://pub.dev/packages/permission_handler)
- [BLE GATT 서비스 가이드](https://www.bluetooth.com/specifications/specs/core-specification/)

## 변경 이력

- **v1.0.0** (2024): 초기 구현
  - BLE 디바이스 스캔 및 연결
  - JSON 데이터 송수신
  - 자동 재연결 로직
  - 청크 전송 지원

