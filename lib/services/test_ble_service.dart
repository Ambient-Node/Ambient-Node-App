import 'dart:async';
import 'dart:math';
import 'package:flutter_blue_plus/flutter_blue_plus.dart'; // 타입 호환용
import 'package:ambient_node/services/ble_service.dart'; // Enum 사용을 위해

class TestBleService implements BleService {
  // 1. 상태 스트림 (가짜)
  final _stateController = StreamController<BleConnectionState>.broadcast();
  @override
  Stream<BleConnectionState> get connectionStateStream => _stateController.stream;

  // 2. 데이터 스트림 (가짜)
  final _dataController = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get dataStream => _dataController.stream;

  BleConnectionState _currentState = BleConnectionState.disconnected;
  @override
  BleConnectionState get currentState => _currentState;

  Timer? _dummyDataTimer;

  @override
  Future<bool> initialize() async {
    print("🧪 [TestBle] 가짜 서비스 초기화됨");
    _updateState(BleConnectionState.disconnected);
    return true;
  }

  @override
  Stream<List<ScanResult>> startScan() {
    print("🧪 [TestBle] 가짜 스캔 시작");
    // 가짜 디바이스 검색 결과 리턴
    return Stream.value([
      // BluetoothDevice 생성자가 private일 수 있으므로 mock 라이브러리가 없다면
      // 스캔 화면 테스트는 제한적일 수 있습니다.
      // 하지만 메인 대시보드 테스트에는 문제 없습니다.
    ]);
  }

  @override
  Future<void> stopScan() async {
    print("🧪 [TestBle] 가짜 스캔 중지");
  }

  @override
  Future<void> connect(BluetoothDevice device) async {
    // 스캔 화면에서 호출되지만, 우리는 강제 연결 기능을 쓸 것이므로 비워둡니다.
  }

  // ★ 강제 연결 함수 (테스트용)
  Future<void> forceConnect() async {
    print("🧪 [TestBle] 연결 시도 중...");
    _updateState(BleConnectionState.connecting);

    await Future.delayed(const Duration(seconds: 1)); // 1초 딜레이 연출

    _updateState(BleConnectionState.connected);
    print("🧪 [TestBle] 연결 성공!");

    _startGeneratingDummyData();
  }

  @override
  Future<void> disconnect() async {
    print("🧪 [TestBle] 연결 해제 중...");
    _updateState(BleConnectionState.disconnected);
    _dummyDataTimer?.cancel();
  }

  @override
  Future<void> sendJson(Map<String, dynamic> data) async {
    print("🧪 [TestBle] 데이터 전송(가짜): $data");
    // 명령을 보내면 0.5초 뒤에 잘 받았다는 가짜 응답을 줌 (ACK 시뮬레이션)
    await Future.delayed(const Duration(milliseconds: 500));

    // 만약 통계 요청이면 가짜 통계 데이터 리턴
    if (data['type'] == 'usage' || data['action'] == 'mqtt_publish') {
      // 여기서 가짜 통계 데이터를 _dataController.add(...) 하면 분석 탭 테스트 가능
    }
  }

  void _updateState(BleConnectionState state) {
    _currentState = state;
    _stateController.add(state);
  }

  void _startGeneratingDummyData() {
    // 3초마다 가짜 얼굴 인식 데이터 등을 보냄 (UI 반응 테스트용)
    _dummyDataTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      // 예: 얼굴 감지 이벤트 시뮬레이션
      // _dataController.add({
      //   "type": "FACE_DETECTED",
      //   "user_id": "test_user_1",
      // });
    });
  }

  // Interface 준수를 위한 더미 메서드들
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}