# MQTT 토픽 처리 명세서

## 📋 개요

각 컨테이너가 어떤 MQTT 토픽을 **subscribe**하고 **publish**하는지 정리한 문서입니다.

---

## 🏗️ 컨테이너 구조

```
docker-compose.yml
├── ambient-mqtt-broker      (Mosquitto)
├── ambient-fan-service       (Hardware Container)
├── ambient-db-service        (DB Container)
└── ambient-ai-service       (AI Container, 추후 추가)
```

---

## 🔄 데이터 흐름 다이어그램

### 1. 팬 제어 흐름
```
Flutter App (BLE)
  ↓ {"speed": 50, "trackingOn": true}
Hardware Container
  ├─ GPIO: 팬 속도 50%로 변경
  ├─ PUBLISH → ambient/command/speed (50)
  └─ PUBLISH → ambient/status/speed (50)
       ↓
MQTT Broker
  ├─ → DB Container (subscribe: ambient/db/log-event)
  │    └─ device_events 테이블에 기록
  │
  └─ → Flutter App (BLE Notification, via Hardware Container)
```

### 2. 사용자 등록 흐름
```
Flutter App (BLE)
  ↓ {"action": "register_user", "name": "민수", "image_base64": "..."}
Hardware Container
  ├─ 이미지 저장: /var/lib/ambient-node/users/minsu/face.jpg
  └─ PUBLISH → ambient/user/register {"user_id": "minsu", "name": "민수", "photo_path": "/var/lib/ambient-node/users/minsu/face.jpg"}
       ↓
MQTT Broker
  ├─ → AI Container (subscribe: ambient/user/register)
  │    ├─ 얼굴 임베딩 생성
  │    └─ PUBLISH → ambient/user/embedding-ready {"user_id": "minsu"}
  │
  └─ → DB Container (subscribe: ambient/db/log-event)
       └─ users 테이블에 INSERT
```

### 3. 얼굴 감지 흐름
```
AI Container (카메라)
  └─ PUBLISH → ambient/ai/face-detected {"user_id": "minsu", "angle": 30}
       ↓
MQTT Broker
  ├─ → Hardware Container (subscribe: ambient/ai/face-detected)
  │    └─ GPIO: 회전 모터 30도 회전
  │
  └─ → DB Container (subscribe: ambient/db/log-event)
       └─ device_events 테이블에 기록
```

---

## 📡 각 컨테이너별 토픽 처리

### 1️⃣ Hardware Container (`fan-service`)

**역할**: BLE 통신, GPIO 제어, 하드웨어 상태 관리

#### Subscribe (구독하는 토픽)

| 토픽 | 설명 | 처리 로직 |
|------|------|----------|
| `ambient/ai/face-detected` | AI 컨테이너에서 얼굴 감지 시 | 회전 모터를 `angle` 값만큼 회전 |
| `ambient/db/stats-request` | 통계 요청 (선택 사항) | 현재 하드웨어 상태 반환 |

#### Publish (발행하는 토픽)

| 토픽 | 설명 | 데이터 형식 | 발행 시점 |
|------|------|------------|----------|
| `ambient/command/power` | 전원 제어 명령 | `{"power": true/false}` | BLE에서 `speed` 값 변경 시 (0이면 power=false) |
| `ambient/command/speed` | 풍속 변경 명령 | `{"speed": 0-5}` | BLE에서 `speed` 값 변경 시 |
| `ambient/command/angle` | 각도 변경 명령 | `{"direction": "up\|down\|left\|right\|center"}` | BLE에서 `manual_control` 수신 시 |
| `ambient/command/face-tracking` | 얼굴 추적 제어 | `{"enabled": true/false}` | BLE에서 `trackingOn` 값 변경 시 |
| `ambient/status/power` | 현재 전원 상태 | `{"power": true/false}` | 전원 상태 변경 시 |
| `ambient/status/speed` | 현재 풍속 | `{"speed": 0-5}` | 풍속 변경 시 |
| `ambient/status/angle` | 현재 각도 | `{"angle": 0-360}` | 각도 변경 시 |
| `ambient/status/face-tracking` | 얼굴 추적 상태 | `{"enabled": true/false}` | 얼굴 추적 상태 변경 시 |
| `ambient/user/register` | 사용자 등록 요청 | `{"user_id": "minsu", "name": "민수", "photo_path": "..."}` | BLE에서 `register_user` 수신 시 |
| `ambient/user/select` | 사용자 선택 알림 | `{"user_id": "minsu"}` | BLE에서 사용자 선택 변경 시 (선택 사항) |
| `ambient/db/log-event` | 이벤트 로깅 요청 | `{"event_type": "fan_speed_changed", "data": {...}}` | 중요한 상태 변경 시 |

#### BLE → MQTT 변환 로직

```python
# fan_service.py 예시
def on_ble_write(payload):
    """BLE에서 받은 데이터를 MQTT로 변환"""
    
    # 팬 제어 명령
    if 'speed' in payload:
        speed = payload['speed']
        power = speed > 0
        
        # GPIO 제어
        set_fan_speed(speed)
        
        # MQTT 발행
        mqtt_client.publish('ambient/command/power', {'power': power})
        mqtt_client.publish('ambient/command/speed', {'speed': speed})
        mqtt_client.publish('ambient/status/power', {'power': power})
        mqtt_client.publish('ambient/status/speed', {'speed': speed})
        
        # 로깅
        mqtt_client.publish('ambient/db/log-event', {
            'event_type': 'fan_speed_changed',
            'speed': speed,
            'timestamp': datetime.now().isoformat()
        })
    
    if 'trackingOn' in payload:
        enabled = payload['trackingOn']
        mqtt_client.publish('ambient/command/face-tracking', {'enabled': enabled})
        mqtt_client.publish('ambient/status/face-tracking', {'enabled': enabled})
    
    # 사용자 관리
    if payload.get('action') == 'register_user':
        user_id = payload['name'].lower().replace(' ', '_')
        photo_path = save_user_image(user_id, payload['image_base64'])
        mqtt_client.publish('ambient/user/register', {
            'user_id': user_id,
            'name': payload['name'],
            'photo_path': photo_path
        })
    
    # 수동 제어
    if payload.get('action') == 'manual_control':
        mqtt_client.publish('ambient/command/angle', {
            'direction': payload['direction']
        })
```

---

### 2️⃣ DB Container (`db-service`)

**역할**: SQLite 데이터베이스 관리, 이벤트 로깅, 통계 제공

#### Subscribe (구독하는 토픽)

| 토픽 | 설명 | 처리 로직 |
|------|------|----------|
| `ambient/db/log-event` | 이벤트 로깅 요청 | `device_events` 테이블에 INSERT |
| `ambient/user/register` | 사용자 등록 알림 | `users` 테이블에 INSERT |
| `ambient/user/select` | 사용자 선택 알림 | `user_sessions` 테이블에 세션 시작/종료 기록 |
| `ambient/status/*` | 하드웨어 상태 변경 | 상태 이력 기록 (선택 사항) |

#### Publish (발행하는 토픽)

| 토픽 | 설명 | 데이터 형식 | 발행 시점 |
|------|------|------------|----------|
| `ambient/db/stats-response` | 통계 데이터 응답 | `{"stats": {...}}` | `ambient/db/stats-request` 수신 시 |

#### 처리 로직

```python
# db_service.py 예시
def on_log_event(payload):
    """이벤트 로깅"""
    event_type = payload['event_type']
    
    db.execute("""
        INSERT INTO device_events (event_type, data, timestamp)
        VALUES (?, ?, ?)
    """, (event_type, json.dumps(payload.get('data', {})), datetime.now()))
    
    db.commit()

def on_user_register(payload):
    """사용자 등록"""
    db.execute("""
        INSERT INTO users (user_id, name, photo_path, registered_at)
        VALUES (?, ?, ?, ?)
    """, (payload['user_id'], payload['name'], payload['photo_path'], datetime.now()))
    
    db.commit()

def on_stats_request(payload):
    """통계 데이터 요청 응답"""
    # 사용자별 사용 시간, 이벤트 수 등 계산
    stats = calculate_stats()
    
    mqtt_client.publish('ambient/db/stats-response', {
        'stats': stats,
        'request_id': payload.get('request_id')
    })
```

---

### 3️⃣ AI Container (`ai-service`, 추후 추가)

**역할**: 얼굴 인식, 임베딩 생성, 자동 추적

#### Subscribe (구독하는 토픽)

| 토픽 | 설명 | 처리 로직 |
|------|------|----------|
| `ambient/user/register` | 사용자 등록 알림 | 얼굴 이미지 읽기 → 임베딩 생성 |
| `ambient/command/face-tracking` | 얼굴 추적 제어 | 추적 시작/중지 |

#### Publish (발행하는 토픽)

| 토픽 | 설명 | 데이터 형식 | 발행 시점 |
|------|------|------------|----------|
| `ambient/user/embedding-ready` | 얼굴 임베딩 완료 | `{"user_id": "minsu"}` | 임베딩 생성 완료 시 |
| `ambient/ai/face-detected` | 얼굴 감지 | `{"user_id": "minsu", "angle": 30, "confidence": 0.95}` | 얼굴 감지 시 |
| `ambient/user/session-start` | 사용자 세션 시작 | `{"user_id": "minsu", "timestamp": "..."}` | 얼굴 감지 후 세션 시작 시 |
| `ambient/user/session-end` | 사용자 세션 종료 | `{"user_id": "minsu", "duration": 3600, "timestamp": "..."}` | 얼굴 사라진 후 일정 시간 경과 시 |

#### 처리 로직

```python
# ai_service.py 예시
def on_user_register(payload):
    """사용자 등록 시 얼굴 임베딩 생성"""
    photo_path = payload['photo_path']
    user_id = payload['user_id']
    
    # 얼굴 이미지 읽기
    face_image = load_image(photo_path)
    
    # 임베딩 생성
    embedding = generate_face_embedding(face_image)
    
    # 임베딩 저장
    save_embedding(user_id, embedding)
    
    # 완료 알림
    mqtt_client.publish('ambient/user/embedding-ready', {
        'user_id': user_id
    })

def face_detection_loop():
    """얼굴 감지 루프"""
    while face_tracking_enabled:
        # 카메라에서 얼굴 감지
        faces = detect_faces_from_camera()
        
        for face in faces:
            # 얼굴 임베딩 추출
            embedding = extract_embedding(face)
            
            # 등록된 사용자와 매칭
            matched_user = match_user(embedding)
            
            if matched_user:
                # 각도 계산
                angle = calculate_angle(face)
                
                # MQTT 발행
                mqtt_client.publish('ambient/ai/face-detected', {
                    'user_id': matched_user['user_id'],
                    'angle': angle,
                    'confidence': matched_user['confidence'],
                    'timestamp': datetime.now().isoformat()
                })
```

---

### 4️⃣ MQTT Broker (`mqtt-broker`)

**역할**: 메시지 라우팅만 수행 (특별한 처리 없음)

- 모든 토픽을 모든 컨테이너에 라우팅
- 설정 파일: `mosquitto.conf`

---

## 📊 토픽 매핑 테이블

### Flutter App → BLE → MQTT 변환

| Flutter App 데이터 | BLE 수신 | MQTT 토픽 | 발행 컨테이너 |
|-------------------|---------|----------|--------------|
| `{"speed": 50, "trackingOn": true}` | Hardware Container | `ambient/command/speed`<br>`ambient/command/face-tracking`<br>`ambient/status/speed`<br>`ambient/status/face-tracking` | Hardware Container |
| `{"action": "register_user", "name": "민수", "image_base64": "..."}` | Hardware Container | `ambient/user/register` | Hardware Container |
| `{"action": "update_user", ...}` | Hardware Container | `ambient/user/register` (같은 토픽) | Hardware Container |
| `{"action": "delete_user", ...}` | Hardware Container | `ambient/db/log-event` | Hardware Container |
| `{"action": "manual_control", "direction": "up"}` | Hardware Container | `ambient/command/angle` | Hardware Container |

---

## 🔄 토픽별 처리 요약

### 명령 토픽 (`ambient/command/*`)

| 토픽 | 발행자 | 구독자 | 처리 |
|------|--------|--------|------|
| `ambient/command/power` | Hardware Container | 없음 (직접 GPIO 제어) | GPIO로 팬 전원 제어 |
| `ambient/command/speed` | Hardware Container | 없음 (직접 GPIO 제어) | GPIO로 팬 속도 PWM 제어 |
| `ambient/command/angle` | Hardware Container | 없음 (직접 GPIO 제어) | GPIO로 회전 모터 제어 |
| `ambient/command/face-tracking` | Hardware Container | AI Container | AI Container에서 추적 시작/중지 |

### 상태 토픽 (`ambient/status/*`)

| 토픽 | 발행자 | 구독자 | 처리 |
|------|--------|--------|------|
| `ambient/status/power` | Hardware Container | DB Container (선택) | 상태 이력 기록 |
| `ambient/status/speed` | Hardware Container | DB Container (선택) | 상태 이력 기록 |
| `ambient/status/angle` | Hardware Container | DB Container (선택) | 상태 이력 기록 |
| `ambient/status/face-tracking` | Hardware Container | DB Container (선택) | 상태 이력 기록 |

### 사용자 관련 토픽 (`ambient/user/*`)

| 토픽 | 발행자 | 구독자 | 처리 |
|------|--------|--------|------|
| `ambient/user/register` | Hardware Container | AI Container<br>DB Container | AI: 임베딩 생성<br>DB: 사용자 등록 |
| `ambient/user/select` | Hardware Container (선택) | DB Container | DB: 세션 시작/종료 기록 |
| `ambient/user/embedding-ready` | AI Container | 없음 (로깅용) | 임베딩 생성 완료 알림 |
| `ambient/user/session-start` | AI Container | DB Container | DB: 세션 시작 기록 |
| `ambient/user/session-end` | AI Container | DB Container | DB: 세션 종료 기록 |

### 데이터베이스 토픽 (`ambient/db/*`)

| 토픽 | 발행자 | 구독자 | 처리 |
|------|--------|--------|------|
| `ambient/db/log-event` | Hardware Container<br>AI Container | DB Container | DB: 이벤트 로깅 |
| `ambient/db/stats-request` | 외부 (예: 웹 대시보드) | Hardware Container<br>DB Container | 통계 데이터 요청 |
| `ambient/db/stats-response` | DB Container | 외부 (예: 웹 대시보드) | 통계 데이터 응답 |

### AI 토픽 (`ambient/ai/*`)

| 토픽 | 발행자 | 구독자 | 처리 |
|------|--------|--------|------|
| `ambient/ai/face-detected` | AI Container | Hardware Container<br>DB Container | Hardware: 모터 회전<br>DB: 이벤트 로깅 |

---

## 💾 데이터베이스 스키마 제안

```sql
-- users 테이블
CREATE TABLE users (
    user_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    photo_path TEXT,
    embedding_path TEXT,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- device_events 테이블
CREATE TABLE device_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,
    user_id TEXT,
    data TEXT,  -- JSON string
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- user_sessions 테이블
CREATE TABLE user_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    session_start TIMESTAMP NOT NULL,
    session_end TIMESTAMP,
    duration_seconds INTEGER,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- fan_status_history 테이블 (선택 사항)
CREATE TABLE fan_status_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    speed INTEGER,
    power BOOLEAN,
    face_tracking BOOLEAN,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

## 🚀 구현 우선순위

### Phase 1 (기본 기능)
1. ✅ Hardware Container: BLE → MQTT 변환
2. ✅ Hardware Container: GPIO 제어
3. ✅ DB Container: 이벤트 로깅

### Phase 2 (사용자 관리)
4. ✅ Hardware Container: 사용자 이미지 저장
5. ✅ DB Container: 사용자 등록
6. ✅ AI Container: 얼굴 임베딩 생성

### Phase 3 (자동 추적)
7. ✅ AI Container: 얼굴 감지
8. ✅ Hardware Container: 자동 회전

### Phase 4 (고급 기능)
9. 통계 데이터 제공
10. 웹 대시보드 연동

---

**작성일**: 2024년
**최종 수정**: 현재

