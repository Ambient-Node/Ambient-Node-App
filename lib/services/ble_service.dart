import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rxdart/rxdart.dart';

class BleConstants {
  static const String SERVICE_UUID = '12345678-1234-5678-1234-56789abcdef0';
  static const String WRITE_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef1';
  static const String NOTIFY_CHAR_UUID = '12345678-1234-5678-1234-56789abcdef2';
  static const String DEVICE_NAME_PREFIX = 'Ambient';
  static const int MAX_CHUNK_SIZE = 480;
}

enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  disconnecting,
  error
}

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;

  final _connectionStateController = BehaviorSubject<BleConnectionState>.seeded(
      BleConnectionState.disconnected
  );
  final _dataStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _logController = StreamController<String>.broadcast();
  
  // ACK 대기용 Completer
  final Map<String, Completer<Map<String, dynamic>?>> _pendingAcks = {};
  
  final List<String> _chunkBuffer = [];
  StreamSubscription? _deviceStateSubscription;
  Timer? _reconnectTimer;

  Stream<BleConnectionState> get connectionStateStream => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get dataStream => _dataStreamController.stream;
  Stream<String> get logStream => _logController.stream;
  BleConnectionState get currentState => _connectionStateController.value;

  /// 데이터를 보내고 ACK(전체 데이터)를 기다림
  Future<Map<String, dynamic>?> sendRequestWithAck(Map<String, dynamic> data,
      {String ackKeyField = 'user_id', Duration timeout = const Duration(seconds: 5)}) async {
    
    final action = data['action']?.toString() ?? '';
    final keyVal = data[ackKeyField]?.toString() ?? '';
    final ackKey = 'ack:$action:$keyVal';

    if (_pendingAcks.containsKey(ackKey)) {
      _log('이미 대기중인 ACK 키: $ackKey');
      return null;
    }

    final completer = Completer<Map<String, dynamic>?>();
    _pendingAcks[ackKey] = completer;

    try {
      await sendJson(data);
    } catch (e) {
      _pendingAcks.remove(ackKey);
      return null;
    }

    try {
      return await completer.future.timeout(timeout, onTimeout: () {
        _pendingAcks.remove(ackKey);
        _log('ACK 타임아웃: $ackKey');
        return null;
      });
    } catch (e) {
      _pendingAcks.remove(ackKey);
      return null;
    }
  }

  Future<bool> initialize() async {
    _log('BLE 서비스 초기화 중...');
    FlutterBluePlus.setLogLevel(LogLevel.error, color: false);

    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    }

    FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.off) {
        _log('⚠️ 블루투스 어댑터가 꺼졌습니다.');
        _handleDisconnection();
      }
    });

    return await _requestPermissions();
  }

  Stream<List<ScanResult>> startScan() {
    if (_connectionStateController.value == BleConnectionState.connected) {
      return const Stream.empty();
    }

    _updateState(BleConnectionState.scanning);
    _log('${BleConstants.DEVICE_NAME_PREFIX} 디바이스 스캔 시작...');

    return FlutterBluePlus.scanResults.map((results) {
      return results.where((r) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;
        return name.toLowerCase().startsWith(
            BleConstants.DEVICE_NAME_PREFIX.toLowerCase()
        );
      }).toList();
    }).doOnListen(() {
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    }).doOnCancel(() {
      stopScan();
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    if (_connectionStateController.value == BleConnectionState.scanning) {
      _updateState(BleConnectionState.disconnected);
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    if (_connectionStateController.value == BleConnectionState.connecting ||
        _connectionStateController.value == BleConnectionState.connected) {
      return;
    }

    _updateState(BleConnectionState.connecting);
    stopScan();

    try {
      _log('${device.platformName}에 연결 시도 중...');

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );

      if (Platform.isAndroid) {
        await Future.delayed(const Duration(seconds: 2));
      }

      _connectedDevice = device;

      _deviceStateSubscription?.cancel();
      _deviceStateSubscription = device.connectionState.listen((state) {
        _log('📡 기기 연결 상태 변경: $state');

        if (state == BluetoothConnectionState.connected) {
          if (currentState != BleConnectionState.connected) {
            _updateState(BleConnectionState.connected);
          }
        } else if (state == BluetoothConnectionState.disconnected) {
          _log('⚠️ 기기와의 연결이 끊어졌습니다.');
          _handleDisconnection();
        }
      });

      await _discoverServices(device);

      _updateState(BleConnectionState.connected);
      _log('✅ 연결 성공.');

    } catch (e) {
      _log('❌ 연결 실패: $e');
      try { await device.disconnect(); } catch (_) {}
      _updateState(BleConnectionState.error);
      Future.delayed(const Duration(seconds: 2), () {
        _updateState(BleConnectionState.disconnected);
      });
    }
  }

  Future<void> disconnect() async {
    _updateState(BleConnectionState.disconnecting);
    _reconnectTimer?.cancel();
    try {
      await _connectedDevice?.disconnect();
    } catch (e) {
      _log('연결 해제 중 오류: $e');
    } finally {
      _handleDisconnection();
    }
  }

  Future<void> sendJson(Map<String, dynamic> data) async {
    if (currentState != BleConnectionState.connected) {
      _log('⚠️ 전송 차단됨: 연결 안됨');
      return;
    }
    if (_connectedDevice == null || _writeCharacteristic == null) {
      _log('⚠️ 전송 차단됨: Characteristic 초기화 실패');
      return;
    }

    try {
      final jsonStr = json.encode(data);
      final bytes = utf8.encode(jsonStr);
      _log('📤 전송: $jsonStr');

      if (bytes.length > BleConstants.MAX_CHUNK_SIZE) {
        await _sendInChunks(_writeCharacteristic!, jsonStr);
      } else {
        await _writeCharacteristic!.write(bytes, withoutResponse: true);
      }
    } catch (e) {
      _log('❌ 전송 오류: $e');
      if (e.toString().toLowerCase().contains('disconnected')) {
        _handleDisconnection();
      }
      rethrow;
    }
  }

  void _updateState(BleConnectionState state) {
    if (_connectionStateController.value != state) {
      _connectionStateController.add(state);
    }
  }

  void _handleDisconnection() {
    _deviceStateSubscription?.cancel();
    _connectedDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _chunkBuffer.clear();
    _reconnectTimer?.cancel();
    _updateState(BleConnectionState.disconnected);
    _log('🔌 연결이 해제되었습니다.');
  }

  Future<void> _discoverServices(BluetoothDevice device) async {
    _log('🔍 서비스 탐색 중...');
    final services = await device.discoverServices();
    final targetService = services.firstWhere(
          (s) => s.uuid == Guid(BleConstants.SERVICE_UUID),
      orElse: () => throw Exception('서비스를 찾을 수 없습니다.'),
    );

    _writeCharacteristic = null;
    _notifyCharacteristic = null;

    for (var char in targetService.characteristics) {
      if (char.uuid == Guid(BleConstants.WRITE_CHAR_UUID)) {
        _writeCharacteristic = char;
        _log('✅ Write Characteristic 발견');
      } else if (char.uuid == Guid(BleConstants.NOTIFY_CHAR_UUID)) {
        _notifyCharacteristic = char;
        _log('✅ Notify Characteristic 발견');
        await char.setNotifyValue(true);
        char.lastValueStream.listen(_onDataReceived);
      }
    }

    if (_writeCharacteristic == null || _notifyCharacteristic == null) {
      throw Exception('필수 Characteristic을 찾지 못했습니다.');
    }
  }

  void _onDataReceived(List<int> bytes) {
    try {
      final str = utf8.decode(bytes);

      if (str.startsWith('<CHUNK:') && str.contains('>')) {
        _handleChunk(str);
        return;
      }

      final dynamic decoded = json.decode(str);

      // ACK 처리 로직 수정
      if (decoded is Map) {
        // dynamic Map을 String Key Map으로 변환
        final Map<String, dynamic> jsonMap = Map<String, dynamic>.from(decoded);

        try {
          final typeVal = jsonMap['type'];
          final ackFlag = jsonMap['ack'];
          final isAck = (typeVal == 'ACK') || (ackFlag == true);
          
          if (isAck) {
            final action = jsonMap['action']?.toString() ?? '';
            final userId = jsonMap['user_id']?.toString() ?? '';
            final ackKey = 'ack:$action:$userId';
            
            final completer = _pendingAcks.remove(ackKey);
            if (completer != null && !completer.isCompleted) {
              final bool success = jsonMap['success'] ?? true;
              // [수정된 부분] 성공 시 jsonMap 전체 반환 (타입 캐스팅)
              completer.complete(success ? jsonMap : null);
            }
          }
        } catch (e) {
           // ACK 파싱 무시
        }
        
        if (_dataStreamController.hasListener) {
          _dataStreamController.add(jsonMap);
        }
      }
      _log('📥 수신: $str');
    } catch (e) {
      _log('⚠️ 데이터 파싱 오류: $e');
    }
  }

  void _handleChunk(String str) {
    final headerEnd = str.indexOf('>');
    final header = str.substring(7, headerEnd);

    if (header == 'END') {
      final fullStr = _chunkBuffer.join();
      _chunkBuffer.clear();
      try {
        final jsonMap = json.decode(fullStr);
        _dataStreamController.add(jsonMap);
        _log('📦 대용량 수신 완료');
      } catch (e) {
        _log('⚠️ 청크 파싱 오류: $e');
      }
      return;
    }
    _chunkBuffer.add(str.substring(headerEnd + 1));
  }

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
      await Future.delayed(const Duration(milliseconds: 20));
    }
    await char.write(utf8.encode('<CHUNK:END>'), withoutResponse: true);
  }

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

  void dispose() {
    _deviceStateSubscription?.cancel();
    _reconnectTimer?.cancel();
    _connectionStateController.close();
    _dataStreamController.close();
    _logController.close();
  }

  void _log(String message) {
    print('[BLE Service] $message');
    _logController.add(message);
  }
}