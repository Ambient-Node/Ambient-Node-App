/// BLE (Bluetooth Low Energy) 서비스
///
/// Flutter 앱에서 BLE 디바이스와 직접 통신하기 위한 서비스 클래스입니다.
/// Python BLE Gateway 없이 앱이 단독으로 BLE 디바이스를 제어할 수 있습니다.
///
/// 주요 기능:
/// - BLE 디바이스 스캔 및 검색
/// - 디바이스 연결/해제 및 상태 모니터링
/// - JSON 형식 데이터 송수신
/// - 대용량 데이터 청크 전송 지원
/// - 자동 재연결 로직
///
/// 사용 예시:
/// ```dart
/// final bleService = BleService();
/// bleService.onConnectionStateChanged = (isConnected) {
///   print('연결 상태: $isConnected');
/// };
/// await bleService.scanAndConnect();
/// await bleService.sendJson({'speed': 80, 'trackingOn': true});
/// ```

import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE 서비스 UUID (라즈베리파이 ble_gateway.py와 동일)
const String SERVICE_UUID = '12345678-1234-5678-1234-56789abcdef0';

/// Write Characteristic UUID (앱 → 디바이스 데이터 전송)
const String WRITE_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef1';

/// Notify Characteristic UUID (디바이스 → 앱 데이터 수신)
const String NOTIFY_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef2';

/// 디바이스 이름 접두사 (스캔 필터링용)
const String DEVICE_NAME_PREFIX = 'Ambient';

/// BLE MTU 최대 크기 (한 번에 전송 가능한 최대 바이트)
const int MAX_CHUNK_SIZE = 480;

class BleService {
  // ==================== 내부 상태 변수 ====================

  /// 현재 연결된 BLE 디바이스
  BluetoothDevice? _connectedDevice;

  /// Write Characteristic (데이터 전송용)
  BluetoothCharacteristic? _writeCharacteristic;

  /// Notify Characteristic (데이터 수신용)
  BluetoothCharacteristic? _notifyCharacteristic;

  /// 연결 상태 모니터링 스트림 구독
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  /// 스캔 결과 스트림 구독
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  /// 스캔된 디바이스 목록
  final List<BluetoothDevice> _scannedDevices = [];

  /// 청크 수신 버퍼 (대용량 데이터 수신용)
  final List<String> _chunkBuffer = [];

  /// 총 청크 개수 (디버깅 및 로깅용)
  // ignore: unused_field
  int _chunkTotal = 0;

  /// 자동 재연결 시도 중 여부
  bool _isReconnecting = false;

  /// 재연결 타이머
  Timer? _reconnectTimer;

  // ==================== 콜백 함수 ====================

  /// 연결 상태 변경 콜백
  /// [isConnected] true: 연결됨, false: 연결 해제됨
  Function(bool isConnected)? onConnectionStateChanged;

  /// 디바이스 이름 변경 콜백
  /// [deviceName] 변경된 디바이스 이름
  Function(String deviceName)? onDeviceNameChanged;

  /// 데이터 수신 콜백
  /// [data] 수신된 JSON 데이터 (Map<String, dynamic>)
  Function(Map<String, dynamic> data)? onDataReceived;

  /// 에러 발생 콜백
  /// [error] 에러 메시지
  Function(String error)? onError;

  // ==================== 공개 메서드 ====================

  /// 권한 확인 및 요청
  ///
  /// Android 12+ 에서는 BLUETOOTH_SCAN, BLUETOOTH_CONNECT 권한이 필요합니다.
  ///
  /// Returns: 모든 권한이 승인되었으면 true
  Future<bool> requestPermissions() async {
    try {
      print('[BLE] 권한 확인 중...');

      final permissions = [
        Permission.bluetooth,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
        Permission.location, // Android 10 이하에서 필요
      ];

      final statuses = await permissions.request();
      final allGranted = statuses.values.every((status) => status.isGranted);

      if (allGranted) {
        print('[BLE] 모든 권한 승인됨');
      } else {
        print('[BLE] 일부 권한 거부됨: $statuses');
      }

      return allGranted;
    } catch (e) {
      print('[BLE] 권한 요청 오류: $e');
      onError?.call('권한 요청 실패: $e');
      return false;
    }
  }

  /// 블루투스 어댑터 상태 확인
  ///
  /// Returns: 블루투스가 켜져 있으면 true
  Future<bool> isBluetoothEnabled() async {
    try {
      final state = await FlutterBluePlus.adapterState.first;
      final isOn = state == BluetoothAdapterState.on;
      print('[BLE] 블루투스 상태: ${isOn ? "ON" : "OFF"}');
      return isOn;
    } catch (e) {
      print('[BLE] 블루투스 상태 확인 오류: $e');
      return false;
    }
  }

  /// BLE 디바이스 스캔 시작
  ///
  /// [timeout] 스캔 지속 시간 (기본 30초)
  /// [namePrefix] 디바이스 이름 필터 (기본: "Ambient")
  ///
  /// Returns: 스캔된 디바이스 목록 스트림
  Stream<List<BluetoothDevice>> startScan({
    Duration timeout = const Duration(seconds: 30),
    String namePrefix = DEVICE_NAME_PREFIX,
  }) async* {
    try {
      print('[BLE] 스캔 시작 (타임아웃: ${timeout.inSeconds}초)');

      // 권한 확인
      if (!await requestPermissions()) {
        print('[BLE] 권한 없음 - 스캔 중단');
        yield [];
        return;
      }

      // 블루투스 상태 확인
      if (!await isBluetoothEnabled()) {
        print('[BLE] 블루투스 꺼짐 - 스캔 중단');
        onError?.call('블루투스를 켜주세요');
        yield [];
        return;
      }

      // 기존 스캔 중지
      await FlutterBluePlus.stopScan();

      // 스캔 시작
      await FlutterBluePlus.startScan(timeout: timeout);

      _scannedDevices.clear();

      // 스캔 결과 스트림 구독
      await for (final results in FlutterBluePlus.scanResults) {
        _scannedDevices.clear();

        for (final result in results) {
          final device = result.device;
          final deviceName = device.platformName.isNotEmpty
              ? device.platformName
              : device.advName;

          // 이름 필터링
          if (deviceName.toLowerCase().contains(namePrefix.toLowerCase())) {
            // 중복 제거
            if (!_scannedDevices.any((d) => d.remoteId == device.remoteId)) {
              _scannedDevices.add(device);
              print('[BLE] 디바이스 발견: $deviceName (${device.remoteId})');
            }
          }
        }

        yield List.from(_scannedDevices);
      }
    } catch (e) {
      print('[BLE] 스캔 오류: $e');
      onError?.call('스캔 실패: $e');
      yield [];
    }
  }

  /// 스캔 중지
  void stopScan() {
    try {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanSubscription = null;
      print('[BLE] 스캔 중지');
    } catch (e) {
      print('[BLE] 스캔 중지 오류: $e');
    }
  }

  /// 특정 디바이스에 연결
  ///
  /// [device] 연결할 BLE 디바이스
  /// [timeout] 연결 타임아웃 (기본 15초)
  /// [autoReconnect] 자동 재연결 활성화 여부 (기본 true)
  ///
  /// Returns: 연결 성공 시 true
  Future<bool> connectToDevice(
    BluetoothDevice device, {
    Duration timeout = const Duration(seconds: 15),
    bool autoReconnect = true,
  }) async {
    try {
      print('[BLE] 연결 시도: ${device.platformName} (${device.remoteId})');

      // 기존 연결이 있으면 먼저 해제
      if (_connectedDevice != null && _connectedDevice != device) {
        await disconnect();
      }

      _connectedDevice = device;

      // 연결
      await device.connect(
        timeout: timeout,
        autoConnect: false, // 본딩 우회
      );

      // 연결 상태 확인
      final connectionState = await device.connectionState.first;
      if (connectionState != BluetoothConnectionState.connected) {
        throw Exception('연결 실패: 상태 = $connectionState');
      }

      print('[BLE] GATT 연결 성공');

      // 서비스 및 Characteristic 발견
      await _discoverServices(device);

      // 연결 상태 모니터링 시작
      _startConnectionMonitoring(device, autoReconnect);

      // 디바이스 이름 업데이트
      final deviceName =
          device.platformName.isNotEmpty ? device.platformName : device.advName;
      onDeviceNameChanged?.call(deviceName);
      onConnectionStateChanged?.call(true);

      print('[BLE] 연결 완료: $deviceName');
      return true;
    } catch (e) {
      print('[BLE] 연결 실패: $e');
      onError?.call('연결 실패: $e');
      onConnectionStateChanged?.call(false);

      // 연결 실패 시 정리
      _connectedDevice = null;
      _writeCharacteristic = null;
      _notifyCharacteristic = null;

      return false;
    }
  }

  /// 현재 연결 해제
  ///
  /// Returns: 해제 성공 시 true
  Future<bool> disconnect() async {
    try {
      print('[BLE] 연결 해제 시작...');

      // 재연결 타이머 취소
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _isReconnecting = false;

      // 연결 상태 모니터링 중지
      _connectionSubscription?.cancel();
      _connectionSubscription = null;

      // 디바이스 연결 해제
      if (_connectedDevice != null) {
        try {
          final state = await _connectedDevice!.connectionState.first;
          if (state == BluetoothConnectionState.connected) {
            await _connectedDevice!.disconnect();
            print('[BLE] 디바이스 연결 해제 완료');
          }
        } catch (e) {
          print('[BLE] 연결 해제 중 오류 (무시): $e');
        }
      }

      // 상태 초기화
      _connectedDevice = null;
      _writeCharacteristic = null;
      _notifyCharacteristic = null;
      _chunkBuffer.clear();
      _chunkTotal = 0;

      onConnectionStateChanged?.call(false);
      print('[BLE] 연결 해제 완료');

      return true;
    } catch (e) {
      print('[BLE] 연결 해제 오류: $e');
      onError?.call('연결 해제 실패: $e');
      return false;
    }
  }

  /// JSON 데이터 전송
  ///
  /// [data] 전송할 JSON 데이터 (Map<String, dynamic>)
  ///
  /// 대용량 데이터는 자동으로 청크 단위로 분할하여 전송합니다.
  ///
  /// 예시:
  /// ```dart
  /// await bleService.sendJson({
  ///   'speed': 80,
  ///   'trackingOn': true,
  ///   'action': 'manual_control',
  ///   'direction': 'up',
  /// });
  /// ```
  Future<void> sendJson(Map<String, dynamic> data) async {
    if (_writeCharacteristic == null) {
      throw Exception('BLE 연결되지 않음');
    }

    try {
      final jsonStr = json.encode(data);
      final jsonBytes = utf8.encode(jsonStr);

      print('[BLE] 데이터 전송: ${jsonStr.length} 바이트');
      print(
          '[BLE] 내용: ${jsonStr.substring(0, jsonStr.length > 100 ? 100 : jsonStr.length)}...');

      // 대용량 데이터는 청크로 분할
      if (jsonBytes.length > MAX_CHUNK_SIZE) {
        await _sendInChunks(jsonStr);
        return;
      }

      // 일반 전송
      final useWithoutResponse =
          _writeCharacteristic!.properties.writeWithoutResponse;
      await _writeCharacteristic!.write(
        jsonBytes,
        withoutResponse: useWithoutResponse,
      );

      print('[BLE] 전송 완료');
    } catch (e) {
      print('[BLE] 전송 오류: $e');
      onError?.call('데이터 전송 실패: $e');
      rethrow;
    }
  }

  /// 현재 연결 상태 확인
  ///
  /// Returns: 연결되어 있으면 true
  bool get isConnected {
    return _connectedDevice != null &&
        _writeCharacteristic != null &&
        _notifyCharacteristic != null;
  }

  /// 연결된 디바이스 정보
  ///
  /// Returns: 연결된 디바이스 또는 null
  BluetoothDevice? get connectedDevice => _connectedDevice;

  /// 스캔된 디바이스 목록
  ///
  /// Returns: 현재까지 스캔된 디바이스 목록
  List<BluetoothDevice> get scannedDevices => List.from(_scannedDevices);

  /// 리소스 정리 및 서비스 종료
  Future<void> dispose() async {
    print('[BLE] 서비스 종료 중...');

    await disconnect();
    stopScan();

    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();

    _reconnectTimer?.cancel();

    print('[BLE] 서비스 종료 완료');
  }

  // ==================== 내부 메서드 ====================

  /// GATT 서비스 및 Characteristic 발견
  Future<void> _discoverServices(BluetoothDevice device) async {
    try {
      print('[BLE] 서비스 발견 시작...');

      final services = await device.discoverServices();
      print('[BLE] 발견된 서비스 수: ${services.length}');

      bool serviceFound = false;

      for (final service in services) {
        print('[BLE] 서비스: ${service.uuid}');

        // 대상 서비스 찾기
        if (service.uuid.toString().toLowerCase() !=
            SERVICE_UUID.toLowerCase()) {
          continue;
        }

        serviceFound = true;
        print('[BLE] 대상 서비스 발견: ${service.uuid}');
        print('[BLE] Characteristic 수: ${service.characteristics.length}');

        // Characteristic 찾기
        for (final char in service.characteristics) {
          print('[BLE] Characteristic: ${char.uuid}, 속성: ${char.properties}');

          final charUuid = char.uuid.toString().toLowerCase();

          // Write Characteristic
          if (charUuid == WRITE_CHAR_UUID.toLowerCase()) {
            _writeCharacteristic = char;
            print('[BLE] Write Characteristic 설정 완료');
          }

          // Notify Characteristic
          if (charUuid == NOTIFY_CHAR_UUID.toLowerCase()) {
            _notifyCharacteristic = char;
            print('[BLE] Notify Characteristic 설정 완료');

            // Notify 활성화
            await char.setNotifyValue(true);
            print('[BLE] Notify 활성화 완료');

            // 데이터 수신 리스너 설정
            char.lastValueStream.listen(_handleNotification);
          }
        }
      }

      if (!serviceFound) {
        throw Exception('대상 서비스($SERVICE_UUID)를 찾을 수 없습니다');
      }

      if (_writeCharacteristic == null) {
        throw Exception('Write Characteristic($WRITE_CHAR_UUID)을 찾을 수 없습니다');
      }

      if (_notifyCharacteristic == null) {
        throw Exception('Notify Characteristic($NOTIFY_CHAR_UUID)을 찾을 수 없습니다');
      }

      print('[BLE] 서비스 발견 완료');
    } catch (e) {
      print('[BLE] 서비스 발견 실패: $e');
      _writeCharacteristic = null;
      _notifyCharacteristic = null;
      rethrow;
    }
  }

  /// 연결 상태 모니터링 시작
  void _startConnectionMonitoring(BluetoothDevice device, bool autoReconnect) {
    _connectionSubscription?.cancel();

    _connectionSubscription = device.connectionState.listen((state) {
      print('[BLE] 연결 상태 변경: $state');

      switch (state) {
        case BluetoothConnectionState.connected:
          print('[BLE] 연결됨');
          onConnectionStateChanged?.call(true);
          _isReconnecting = false;
          _reconnectTimer?.cancel();
          break;

        case BluetoothConnectionState.disconnected:
          print('[BLE] 연결 해제됨');
          onConnectionStateChanged?.call(false);

          // 자동 재연결 시도
          if (autoReconnect && !_isReconnecting && _connectedDevice != null) {
            _attemptReconnect();
          }
          break;

        case BluetoothConnectionState.connecting:
          print('[BLE] 연결 중...');
          break;

        case BluetoothConnectionState.disconnecting:
          print('[BLE] 연결 해제 중...');
          break;
      }
    }, onError: (error) {
      print('[BLE] 연결 모니터링 오류: $error');
      onError?.call('연결 오류: $error');
    });
  }

  /// 자동 재연결 시도
  void _attemptReconnect() {
    if (_isReconnecting || _connectedDevice == null) {
      return;
    }

    _isReconnecting = true;
    print('[BLE] 자동 재연결 시도...');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () async {
      if (_connectedDevice != null && !isConnected) {
        try {
          await connectToDevice(_connectedDevice!, autoReconnect: true);
        } catch (e) {
          print('[BLE] 재연결 실패: $e');
          // 3초 후 다시 시도
          _attemptReconnect();
        }
      } else {
        _isReconnecting = false;
      }
    });
  }

  /// Notify 데이터 수신 처리
  void _handleNotification(List<int> value) {
    try {
      final dataStr = String.fromCharCodes(value);
      print('[BLE] 데이터 수신: ${dataStr.length} 바이트');

      // 청크 헤더 확인
      if (dataStr.startsWith('<CHUNK:') && dataStr.contains('>')) {
        _handleChunk(dataStr);
        return;
      }

      // 일반 JSON 데이터 처리
      final jsonData = json.decode(dataStr) as Map<String, dynamic>;
      print('[BLE] 수신 데이터: $jsonData');
      onDataReceived?.call(jsonData);
    } catch (e) {
      print('[BLE] 데이터 수신 처리 오류: $e');
      onError?.call('데이터 수신 오류: $e');
    }
  }

  /// 청크 데이터 처리
  void _handleChunk(String dataStr) {
    try {
      final headerEnd = dataStr.indexOf('>');
      final header = dataStr.substring(7, headerEnd); // '<CHUNK:' 제거

      if (header == 'END') {
        // 청크 수신 완료
        print('[BLE] 청크 수신 완료: 총 ${_chunkBuffer.length}개');
        final fullData = _chunkBuffer.join('');
        _chunkBuffer.clear();
        _chunkTotal = 0;

        // 완전한 데이터 처리
        final jsonData = json.decode(fullData) as Map<String, dynamic>;
        print('[BLE] 수신 데이터: $jsonData');
        onDataReceived?.call(jsonData);
        return;
      }

      // 청크 번호 파싱
      final chunkInfo = header.split('/');
      if (chunkInfo.length == 2) {
        final chunkNum = int.parse(chunkInfo[0]);
        final totalChunks = int.parse(chunkInfo[1]);
        final chunkData = dataStr.substring(headerEnd + 1);

        _chunkBuffer.add(chunkData);
        _chunkTotal = totalChunks;
        print('[BLE] 청크 수신: ${chunkNum + 1}/$totalChunks');
      }
    } catch (e) {
      print('[BLE] 청크 처리 오류: $e');
      _chunkBuffer.clear();
      _chunkTotal = 0;
    }
  }

  /// 대용량 데이터 청크 전송
  Future<void> _sendInChunks(String jsonStr) async {
    if (_writeCharacteristic == null) {
      throw Exception('BLE 연결되지 않음');
    }

    try {
      final totalChunks = (jsonStr.length / MAX_CHUNK_SIZE).ceil();
      final useWithoutResponse =
          _writeCharacteristic!.properties.writeWithoutResponse;

      print('[BLE] 청크 전송 시작: 총 $totalChunks개 청크 (${jsonStr.length} 바이트)');

      for (int i = 0; i < totalChunks; i++) {
        final start = i * MAX_CHUNK_SIZE;
        final end = (start + MAX_CHUNK_SIZE > jsonStr.length)
            ? jsonStr.length
            : start + MAX_CHUNK_SIZE;
        final chunkData = jsonStr.substring(start, end);

        final header = '<CHUNK:$i/$totalChunks>';
        final chunkWithHeader = header + chunkData;
        final chunkBytes = utf8.encode(chunkWithHeader);

        await _writeCharacteristic!.write(
          chunkBytes,
          withoutResponse: useWithoutResponse,
        );

        print('[BLE] 청크 ${i + 1}/$totalChunks 전송 (${chunkBytes.length} 바이트)');

        // 다음 청크 전송 전 짧은 대기
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 종료 신호 전송
      final endSignal = utf8.encode('<CHUNK:END>');
      await _writeCharacteristic!
          .write(endSignal, withoutResponse: useWithoutResponse);

      print('[BLE] 청크 전송 완료');
    } catch (e) {
      print('[BLE] 청크 전송 오류: $e');
      rethrow;
    }
  }
}
