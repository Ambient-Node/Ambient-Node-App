import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

/// 프로젝트 사양에 맞춘 BLE 상수 정의
class BleConstants {
  // 라즈베리파이 Gateway와 일치하는 UUID
  static const String SERVICE_UUID = '12345678-1234-5678-1234-56789abcdef0';
  static const String WRITE_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef1';
  static const String NOTIFY_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef2';

  static const String DEVICE_NAME_PREFIX = 'Ambient';
  static const int MAX_CHUNK_SIZE = 480; // MTU 최적화 크기
}

/// BLE 연결 상태 열거형
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  disconnecting,
  error
}

class BleService {
  // 싱글톤 패턴 적용
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  // 내부 상태 변수
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;  // 앱 -> 기기
  BluetoothCharacteristic? _notifyCharacteristic; // 기기 -> 앱

  // Reactive UI를 위한 스트림 컨트롤러 (RxDart BehaviorSubject 사용)
  // BehaviorSubject는 구독 즉시 가장 최근 상태를 전달해줍니다 (중복 UI 업데이트 방지 핵심)
  final _connectionStateController = BehaviorSubject<BleConnectionState>.seeded(BleConnectionState.disconnected);
  final _dataStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _logController = StreamController<String>.broadcast();

  // 외부에서 접근 가능한 스트림 Getter
  Stream<BleConnectionState> get connectionStateStream => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;
  Stream<String> get logStream => _logController.stream;

  // 현재 상태 조회용 Getter
  BleConnectionState get currentState => _connectionStateController.value;

  // 내부 헬퍼 변수들
  StreamSubscription? _deviceConnectionSubscription;
  final List<String> _chunkBuffer = [];
  Timer? _reconnectTimer;

  /// 초기화 및 권한 요청
  Future<bool> initialize() async {
    _log('BLE 서비스 초기화 중...');

    // 로그 레벨 설정 (불필요한 시스템 로그 방지)
    FlutterBluePlus.setLogLevel(LogLevel.error, color: false);

    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }

    return await _requestPermissions();
  }

  /// 스캔 시작
  Stream<List<ScanResult>> startScan() {
    if (_connectionStateController.value == BleConnectionState.connected) {
      _log('이미 연결되어 있어 스캔을 건너뜁니다.');
      return const Stream.empty();
    }

    _updateState(BleConnectionState.scanning);
    _log('${BleConstants.DEVICE_NAME_PREFIX} 디바이스 스캔 시작...');

    // 1. 결과 스트림 변환: 이름으로 필터링 (UUID 필터 대신 여기서 거릅니다)
    return FlutterBluePlus.scanResults.map((results) {
      return results.where((r) {
        // platformName(본명) 또는 advName(광고명) 확인
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;

        // 대소문자 구분 없이 'Ambient'로 시작하는지 확인
        return name.toLowerCase().startsWith(BleConstants.DEVICE_NAME_PREFIX.toLowerCase());
      }).toList();
    }).doOnListen(() {
      // 2. 실제 스캔 시작 (중요: withServices 제거!)
      // 모든 기기를 다 찾은 뒤, 위에서 이름으로만 걸러냅니다.
      FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        // withServices: [Guid(BleConstants.SERVICE_UUID)], // <--- 이 줄을 삭제했습니다.
      );
    }).doOnCancel(() {
      stopScan();
    });
  }

  /// 스캔 중지
  void stopScan() {
    FlutterBluePlus.stopScan();
    // 스캔 중 상태였다면 대기 상태로 변경
    if (_connectionStateController.value == BleConnectionState.scanning) {
      _updateState(BleConnectionState.disconnected);
    }
  }

  /// 디바이스 연결
  Future<void> connect(BluetoothDevice device) async {
    // 1. 이미 연결 중이거나 연결된 상태면 무시
    if (_connectionStateController.value == BleConnectionState.connecting ||
        _connectionStateController.value == BleConnectionState.connected) {
      return;
    }

    // 2. UI 상태를 먼저 '연결 중'으로 변경
    _updateState(BleConnectionState.connecting);
    stopScan(); // 연결 시도 전 스캔 중지 (권장사항)

    try {
      _log('${device.platformName}에 연결 시도 중...');

      // 3. 물리적 연결 시도 (여기서 딱 한 번만 호출해야 합니다)
      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false, // false가 페어링 프로세스에서 더 안정적입니다.
      );

      // ---------------------------------------------------------
      // [핵심] 안드로이드 Status 22 및 페어링 튕김 방지 딜레이
      // 연결 직후 바로 데이터를 주고받으려 하면 안드로이드가 연결을 끊어버립니다.
      // ---------------------------------------------------------
      if (Platform.isAndroid) {
        await Future.delayed(const Duration(seconds: 2));
      }

      // 4. 서비스 탐색 (딜레이 이후에 실행해야 안전함)
      // (flutter_blue_plus의 내장 함수 호출)
      await device.discoverServices();

      _connectedDevice = device;

      // 5. Notification 구독 등 커스텀 로직 실행
      // (기존 코드에 있던 _discoverServices 함수가 Notification 설정을 담당한다고 가정합니다)
      await _discoverServices(device);

      // 6. 연결 끊김 모니터링 리스너 등록
      _deviceConnectionSubscription?.cancel();
      _deviceConnectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      // 7. 최종 연결 성공 상태 업데이트
      _updateState(BleConnectionState.connected);
      _log('연결 성공.');

    } catch (e) {
      _log('연결 실패: $e');

      // 실패 시 확실하게 연결 해제 시도
      try {
        await device.disconnect();
      } catch (e) {}

      _updateState(BleConnectionState.error);

      // 에러 메시지를 보여줄 시간을 주고 상태 초기화
      Future.delayed(const Duration(seconds: 2), () {
        _updateState(BleConnectionState.disconnected);
      });
      // rethrow; // 필요하다면 주석 해제 (UI에서 에러를 따로 잡아서 처리하고 싶을 때)
    }
  }

  /// 연결 해제
  Future<void> disconnect() async {
    _updateState(BleConnectionState.disconnecting);
    _reconnectTimer?.cancel();
    await _connectedDevice?.disconnect();
    _handleDisconnection();
  }

  /// JSON 데이터 전송
  Future<void> sendJson(Map<String, dynamic> data) async {
    // [수정됨] 1. 엄격한 연결 상태 체크
    if (currentState != BleConnectionState.connected) {
      _log('⚠️ 전송 차단됨: BLE가 연결된 상태가 아닙니다. (현재 상태: $currentState)');
      return; // 또는 throw Exception('Not connected');
    }

    // [수정됨] 2. 필수 객체 존재 여부 체크
    if (_connectedDevice == null || _writeCharacteristic == null) {
      _log('⚠️ 전송 차단됨: 연결 객체 또는 Characteristic이 초기화되지 않았습니다.');
      return;
    }

    try {
      final jsonStr = json.encode(data);
      final bytes = utf8.encode(jsonStr);

      _log('📤 전송: $jsonStr');

      // MTU 크기에 따라 분할 전송 또는 직접 전송
      if (bytes.length > BleConstants.MAX_CHUNK_SIZE) {
        await _sendInChunks(_writeCharacteristic!, jsonStr);
      } else {
        await _writeCharacteristic!.write(bytes, withoutResponse: true);
      }
    } catch (e) {
      _log('❌ 전송 오류: $e');
      // 연결이 끊어진 것으로 간주되는 에러가 발생하면 상태 업데이트
      if (e.toString().contains('device not connected') ||
          e.toString().toLowerCase().contains('disconnected')) {
        _handleDisconnection();
      }
      rethrow;
    }
  }

  // ================= 내부 헬퍼 메서드 =================

  /// 상태 업데이트 (중복 이벤트 방지)
  void _updateState(BleConnectionState state) {
    if (_connectionStateController.value != state) {
      _connectionStateController.add(state);
    }
  }

  /// 연결 해제 처리
  void _handleDisconnection() {
    _connectedDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _chunkBuffer.clear();
    _updateState(BleConnectionState.disconnected);
    _log('연결이 해제되었습니다.');
  }

  /// 서비스 및 Characteristic 발견 로직
  Future<void> _discoverServices(BluetoothDevice device) async {
    _log('서비스 탐색 중...');
    final services = await device.discoverServices();

    // 타겟 서비스 찾기
    final targetService = services.firstWhere(
          (s) => s.uuid == Guid(BleConstants.SERVICE_UUID),
      orElse: () => throw Exception('서비스 ${BleConstants.SERVICE_UUID}를 찾을 수 없습니다.'),
    );

    _writeCharacteristic = null;
    _notifyCharacteristic = null;

    for (var char in targetService.characteristics) {
      if (char.uuid == Guid(BleConstants.WRITE_CHAR_UUID)) {
        _writeCharacteristic = char;
        _log('Write Characteristic 발견');
      } else if (char.uuid == Guid(BleConstants.NOTIFY_CHAR_UUID)) {
        _notifyCharacteristic = char;
        _log('Notify Characteristic 발견');

        // 알림 활성화
        await char.setNotifyValue(true);
        char.lastValueStream.listen(_onDataReceived);
      }
    }

    if (_writeCharacteristic == null || _notifyCharacteristic == null) {
      throw Exception('필수 Characteristic(Write/Notify)을 모두 찾지 못했습니다.');
    }
  }

  /// 데이터 수신 처리 (청크 조립 포함)
  void _onDataReceived(List<int> bytes) {
    try {
      final str = utf8.decode(bytes);

      // 청크 데이터 처리 (<CHUNK:index/total>...)
      if (str.startsWith('<CHUNK:') && str.contains('>')) {
        _handleChunk(str);
        return;
      }

      // 일반 JSON 데이터 처리
      final jsonMap = json.decode(str);
      if (_dataStreamController.hasListener) {
        _dataStreamController.add(jsonMap);
      }
      _log('수신: $str');
    } catch (e) {
      _log('데이터 파싱 오류: $e');
      return;
    }
  }

  /// 청크 데이터 조립 로직
  void _handleChunk(String str) {
    final headerEnd = str.indexOf('>');
    final header = str.substring(7, headerEnd); // Remove <CHUNK:

    if (header == 'END') {
      final fullStr = _chunkBuffer.join();
      _chunkBuffer.clear();
      try {
        final jsonMap = json.decode(fullStr);
        _dataStreamController.add(jsonMap);
        _log('대용량 데이터 수신 완료 (${fullStr.length} bytes)');
      } catch (e) { _log('청크 파싱 오류: $e'); }
      return;
    }

    // 간단한 무결성 검사는 생략하고 버퍼에 추가
    _chunkBuffer.add(str.substring(headerEnd + 1));
  }

  /// 대용량 데이터 분할 전송 로직
  Future<void> _sendInChunks(BluetoothCharacteristic char, String jsonStr) async {
    final total = (jsonStr.length / BleConstants.MAX_CHUNK_SIZE).ceil();

    for (int i = 0; i < total; i++) {
      final start = i * BleConstants.MAX_CHUNK_SIZE;
      final end = (start + BleConstants.MAX_CHUNK_SIZE < jsonStr.length)
          ? start + BleConstants.MAX_CHUNK_SIZE
          : jsonStr.length;

      final chunk = jsonStr.substring(start, end);
      final header = '<CHUNK:$i/$total>';
      final payload = utf8.encode('$header>$chunk');

      await char.write(payload, withoutResponse: true);
      await Future.delayed(const Duration(milliseconds: 20)); // 전송 속도 조절 (Flow Control)
    }

    await char.write(utf8.encode('<CHUNK:END>'), withoutResponse: true);
  }

  /// 권한 요청
  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      return statuses.values.every((status) => status.isGranted);
    }
    return true;
  }

  void _log(String message) {
    print('[BLE Service] $message');
    _logController.add(message);
  }
}