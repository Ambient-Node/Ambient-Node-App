# 📱 Ambient Node Mobile App

<div align="center">

<img src="https://github.com/user-attachments/assets/5e25ce86-18bc-45bd-af71-83aaa49a8bd1" width="600" />
<img src="https://github.com/user-attachments/assets/7771c3ae-8c8d-48a4-9146-af55a92fa531" width="600" />
<img src="https://github.com/user-attachments/assets/ba5c1b0f-8bbb-4f6d-b063-aef408e8dde9" width="600" />

<br>
</div><br>

**스마트 에어 서큘레이터 제어 및 모니터링을 위한 Flutter 어플리케이션**

> **기술 스택:** Flutter (Dart), BLE (flutter_blue_plus)

본 앱은 **BLE 기반의 오프라인 제어**를 핵심으로 하며, 대용량 데이터 전송을 위한 **자체 Chunking 프로토콜**과 **ACK 기반 신뢰성 통신**을 구현하였습니다.

---

## 🛠️ Tech Stack

<div align="center">

**Frontend & Mobile**<br>
![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white)

**Communication Protocol**<br>
![BLE](https://img.shields.io/badge/Bluetooth_LE-0082FC?style=for-the-badge&logo=bluetooth&logoColor=white)
![MQTT](https://img.shields.io/badge/MQTT-660066?style=for-the-badge&logo=mqtt&logoColor=white)

**Design & Tools**<br>
![Figma](https://img.shields.io/badge/Figma-F24E1E?style=for-the-badge&logo=figma&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![iOS](https://img.shields.io/badge/iOS-000000?style=for-the-badge&logo=apple&logoColor=white)

</div>

### Key Libraries
- `flutter_blue_plus` - BLE 통신
- `provider` - 상태 관리
- `shared_preferences` - 로컬 저장소
- `fl_chart` - 데이터 시각화

---

## 📂 앱 아키텍처 (App Architecture)

```text
lib/
├── main.dart                 # 앱 엔트리 및 상태 관리 (Lifted State)
├── screens/                  # UI 화면 (Dashboard, Control, Analytics)
├── services/                 # 비즈니스 로직 및 통신
├── models/                   # 데이터 모델 (User, AnalyticsData)
└── utils/                    # 유틸리티 (SnackBar Helper, Constants)
```

---

## 📡 핵심 통신 기술 (Communication Protocol)

### 1. BLE 데이터 전송 (Custom Protocol)
BLE의 MTU(패킷 크기) 제한을 극복하고 데이터 무결성을 보장하기 위해 자체 프로토콜을 설계했습니다.

*   **Chunking (분할 전송):** 이미지는 480바이트 단위로 분할되어 `<CHUNK:i/total>` 헤더와 함께 전송되며, 수신 측에서 재조립합니다.
*   **Reliability (ACK):** 중요 명령(`user_register`, `delete`, `timer`)은 기기로부터 처리 완료 응답(ACK)을 수신해야만 성공으로 간주하는 **트랜잭션 방식**을 사용합니다.

```dart
// ACK 대기 예시 (비동기 트랜잭션)
bool success = await ble.sendRequestWithAck({
  'action': 'user_register',
  'user_id': '...',
  // ...
});
```

### 2. MQTT 연동 (Optional Statistics)
로컬 제어 외에 서버에 축적된 빅데이터 통계를 조회하기 위해 MQTT를 보조적으로 활용합니다.
*   **요청:** `ambient/stats/request` (기간별 사용량, 선호 모드 등)
*   **응답:** `ambient/stats/response` (JSON 포맷의 통계 데이터)

---

## 📊 데이터 분석 및 인사이트 (Analytics Engine)

앱 내부에서 `SharedPreferences`에 저장된 로그를 분석하여 사용자 맞춤형 리포트를 생성합니다.

*   **In-App Analytics:** 별도의 서버 연산 없이 앱 내부 알고리즘으로 주 사용 시간대(`Top Hour`), 선호 풍속 등을 실시간으로 분석합니다.
*   **Natural Language Insight:** 분석된 데이터를 "주로 14시에 선풍기를 사용합니다"와 같은 자연어 문장으로 변환하여 제공합니다.
*   **Visualization:** 일간/주간 사용 패턴을 시각화된 그래프(Bar/Donut Chart)로 표현합니다.

---

## 🛠️ 개발 및 빌드 가이드 (Development)

### 1. 환경 설정
Flutter SDK 설치 후 의존성을 설치합니다.

```bash
flutter pub get
```

### 2. 실행 및 테스트
디바이스를 연결하고 앱을 실행합니다.

```bash
# 디바이스 실행
flutter run

# 단위 테스트 실행
flutter test
```


