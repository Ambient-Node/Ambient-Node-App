# 사용자 추적 및 사용량 기록 설계

## 🎯 문제 상황

**시나리오**: A의 핸드폰으로 B를 선택하고 풍량을 제어
- **선택된 사용자 (Selected User)**: B
- **제어자 (Controller)**: A (핸드폰 소유자)
- **실제 사용자 (Actual User)**: 얼굴 추적으로 감지된 사용자

**질문**: 사용량은 누구의 것인가?

---

## 💡 해결 방안: **3단계 우선순위 시스템**

### 우선순위
1. **얼굴 추적 감지 사용자** (Highest Priority)
   - 얼굴 추적이 활성화되어 있고 실제 얼굴이 감지되면 → 감지된 사용자의 사용량
   - 가장 정확함

2. **선택된 사용자** (Medium Priority)
   - 얼굴 추적이 비활성화되어 있거나 얼굴을 감지하지 못하면 → 선택된 사용자의 사용량
   - 사용자가 명시적으로 선택한 경우

3. **제어자 (핸드폰 소유자)** (Lowest Priority)
   - 사용자가 선택되지 않았고 얼굴도 감지되지 않으면 → 제어자의 사용량
   - 누군가의 핸드폰으로 제어하는 경우

---

## 📊 데이터 모델 개선

### 현재 UserAnalytics
```dart
class UserAnalytics {
  final String username;  // ← 모호함!
  final List<FanSession> fanSessions;
  // ...
}
```

### 개선된 모델
```dart
class UserAnalytics {
  final String username;  // 실제 사용자 (얼굴 추적 우선)
  final List<FanSession> fanSessions;
  // ...
}

class FanSession {
  final DateTime startTime;
  final DateTime endTime;
  final int speed;
  final String? actualUserId;      // 실제 사용자 (얼굴 추적)
  final String? selectedUserId;    // 선택된 사용자
  final String? controllerId;      // 제어자 (핸드폰 소유자)
  final SessionType type;          // auto (얼굴 추적) | manual (수동 선택)
}

enum SessionType {
  auto,     // 얼굴 추적 자동
  manual,   // 수동 선택
  controller // 제어자 (선택 안 됨)
}
```

---

## 🔄 사용량 기록 로직

### Case 1: 얼굴 추적 활성화 + 얼굴 감지됨
```
얼굴 감지: B
선택된 사용자: C
제어자: A

→ B의 사용량으로 기록 (actualUserId: B)
```

### Case 2: 얼굴 추적 비활성화 + 사용자 선택됨
```
선택된 사용자: B
제어자: A

→ B의 사용량으로 기록 (selectedUserId: B, type: manual)
```

### Case 3: 얼굴 추적 비활성화 + 사용자 선택 안 됨
```
제어자: A

→ A의 사용량으로 기록 (controllerId: A, type: controller)
```

---

## 📱 Bluetooth ID 매핑

### 사용자 등록 시
```dart
class UserProfile {
  final String name;
  final String? imagePath;
  final String? bluetoothId;  // ← 추가: 핸드폰 Bluetooth ID
  
  // 사용자 등록 시 현재 디바이스의 Bluetooth ID 저장
}
```

### Bluetooth ID 가져오기
```dart
// Flutter에서 디바이스 Bluetooth ID 가져오기
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

Future<String?> getBluetoothId() async {
  if (Platform.isAndroid) {
    // Android의 Bluetooth MAC 주소
    // 주의: Android 6.0+ 에서는 권한 필요
  } else if (Platform.isIOS) {
    // iOS의 identifierForVendor 또는 advertisingIdentifier
  }
  return null;
}
```

---

## 🗂️ 데이터베이스 스키마 개선

### RPi DB Service
```sql
CREATE TABLE users (
    user_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    photo_path TEXT,
    bluetooth_id TEXT UNIQUE,  -- 추가
    embedding_path TEXT,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE device_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    actual_user_id TEXT,      -- 실제 사용자 (얼굴 추적)
    selected_user_id TEXT,    -- 선택된 사용자
    controller_id TEXT,        -- 제어자 (Bluetooth ID)
    session_type TEXT,        -- 'auto', 'manual', 'controller'
    data TEXT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (actual_user_id) REFERENCES users(user_id),
    FOREIGN KEY (selected_user_id) REFERENCES users(user_id)
);

CREATE TABLE user_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    actual_user_id TEXT,      -- 실제 사용자
    selected_user_id TEXT,    -- 선택된 사용자
    controller_id TEXT,       -- 제어자
    session_type TEXT,        -- 'auto', 'manual', 'controller'
    session_start TIMESTAMP NOT NULL,
    session_end TIMESTAMP,
    duration_seconds INTEGER,
    FOREIGN KEY (actual_user_id) REFERENCES users(user_id),
    FOREIGN KEY (selected_user_id) REFERENCES users(user_id)
);
```

---

## 💻 코드 구현 개선

### 1. Flutter: Bluetooth ID 추가
```dart
// 사용자 등록 시
final bluetoothId = await getBluetoothId();
widget.onUserDataSend?.call({
  'action': 'register_user',
  'name': result['name']!,
  'image_base64': imageBase64,
  'bluetooth_id': bluetoothId,  // 추가
});
```

### 2. AnalyticsService: 실제 사용자 결정 로직
```dart
static String? _determineActualUser({
  String? detectedUserId,     // 얼굴 추적으로 감지된 사용자
  String? selectedUserId,    // 선택된 사용자
  String? controllerId,      // 제어자
  bool faceTrackingEnabled,  // 얼굴 추적 활성화 여부
}) {
  // 우선순위 1: 얼굴 추적 감지
  if (faceTrackingEnabled && detectedUserId != null) {
    return detectedUserId;
  }
  
  // 우선순위 2: 선택된 사용자
  if (selectedUserId != null) {
    return selectedUserId;
  }
  
  // 우선순위 3: 제어자
  return controllerId;
}
```

### 3. FanService: 사용자 정보 전달
```python
# BLE에서 받은 데이터 처리 시
def handle_ble_write(self, payload):
    controller_id = payload.get('bluetooth_id')  # 제어자
    selected_user = payload.get('selected_user')  # 선택된 사용자
    
    # MQTT 발행 시 모든 정보 포함
    self.mqtt_client.publish("ambient/command/speed", json.dumps({
        "speed": speed,
        "controller_id": controller_id,
        "selected_user_id": selected_user,
        "timestamp": datetime.now().isoformat()
    }))
```

---

## 📈 사용량 통계 표시

### 분석 탭에서 표시
```
사용자: 민수
- 실제 사용 시간: 2시간 30분 (얼굴 추적)
- 선택된 시간: 1시간 15분 (다른 사람이 선택)
- 제어 시간: 30분 (다른 사람의 핸드폰으로 제어)
```

또는 **간단하게**:
```
사용자: 민수
- 총 사용 시간: 2시간 30분
  - 자동 추적: 2시간
  - 수동 선택: 30분
```

---

## ✅ 최종 권장사항

### **옵션 A: 간단한 방식 (현재 유지)**
- **선택된 사용자**의 사용량으로 기록
- 얼굴 추적 시에는 **감지된 사용자**로 덮어쓰기
- 장점: 구현 간단
- 단점: 정확도가 약간 떨어질 수 있음

### **옵션 B: 상세한 방식 (권장)**
- **3가지 ID 모두 기록** (actual, selected, controller)
- 통계 표시 시 우선순위 적용
- 장점: 가장 정확한 데이터
- 단점: 구현 복잡도 증가

---

**결론**: **옵션 B를 권장**하되, **우선순위는 얼굴 추적 > 선택된 사용자 > 제어자**로 적용

