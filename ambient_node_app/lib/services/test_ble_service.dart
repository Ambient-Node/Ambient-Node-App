import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class TestBleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final String namePrefix;
  final Guid serviceUuid;
  final Guid writeCharUuid;
  final Guid notifyCharUuid;

  Function(bool)? onConnectionStateChanged;
  Function(String)? onPairingResponse;
  Function(String)? onDeviceNameChanged;

  final List<BluetoothDevice> _scannedDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  static const int maxChunkSize = 480;

  TestBleService({
    this.namePrefix = 'Ambient',
    Guid? serviceUuid,
    Guid? writeCharUuid,
    Guid? notifyCharUuid,
  })  : serviceUuid =
            serviceUuid ?? Guid('12345678-1234-5678-1234-56789abcdef0'),
        writeCharUuid =
            writeCharUuid ?? Guid('12345678-1234-5678-1234-56789abcdef1'),
        notifyCharUuid =
            notifyCharUuid ?? Guid('12345678-1234-5678-1234-56789abcdef2');

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<bool> initAndConnect(
      {Duration scanTimeout = const Duration(seconds: 5)}) async {
    try {
      print('[BLE] 초기화 시작');
      onConnectionStateChanged?.call(false);

      if (!await _ensurePermissions()) {
        print('[BLE] 권한 거부');
        return false;
      }

      final isOn =
          await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
      if (!isOn) {
        print('[BLE] 블루투스 꺼짐');
        return false;
      }

      print('[BLE] 스캔 시작');
      await FlutterBluePlus.startScan(timeout: scanTimeout);

      await for (final r in FlutterBluePlus.scanResults) {
        for (final result in r) {
          final name = result.device.advName.isNotEmpty
              ? result.device.advName
              : result.device.platformName;

          if (name.toLowerCase().contains(namePrefix.toLowerCase())) {
            print('[BLE] 기기 발견: $name');
            _device = result.device;
            onDeviceNameChanged?.call(name);
            await FlutterBluePlus.stopScan();
            return await _connectSimple();
          }
        }
      }

      await FlutterBluePlus.stopScan();
      print('[BLE] 기기 없음');
      return false;
    } catch (error) {
      print('[BLE] 오류: $error');
      return false;
    }
  }

  Future<bool> _connectSimple({int retries = 3}) async {
    if (_device == null) {
      print('[BLE] 연결 실패: _device == null');
      return false;
    }

    for (int i = 0; i < retries; i++) {
      try {
        print('[BLE] 연결 시도 ${i + 1}/$retries');

        // 기존 연결이 있다면 먼저 해제
        try {
          if (await _device!.connectionState.first ==
              BluetoothConnectionState.connected) {
            print('[BLE] 기존 연결 해제 중...');
            await _device!.disconnect();
            await Future.delayed(const Duration(milliseconds: 500));
          }
        } catch (_) {
          // 연결 상태 확인 실패는 무시
        }

        // 본딩 우회를 위한 연결 옵션 설정
        // autoConnect: false로 설정하여 자동 재연결 방지
        await _device!.connect(
          timeout: const Duration(seconds: 15),
          autoConnect: false,
        );

        // 연결 후 짧은 대기 시간 (본딩 프로세스 완료 대기)
        await Future.delayed(const Duration(milliseconds: 500));

        // 연결 상태 확인
        final connectionState = await _device!.connectionState.first;
        if (connectionState != BluetoothConnectionState.connected) {
          throw Exception('연결 상태 확인 실패: $connectionState');
        }

        print('[BLE] GATT 연결 성공, 서비스 발견 시작...');
        await _discoverServices();
        _startConnectionMonitoring();

        final name = _device?.advName.isNotEmpty == true
            ? _device!.advName
            : (_device?.platformName ?? 'Ambient');
        print('[BLE] 연결 성공: $name');
        onDeviceNameChanged?.call(name);
        onConnectionStateChanged?.call(true);
        return true;
      } catch (e) {
        print('[BLE] 연결 실패 ${i + 1}: $e');
        print('[BLE] 에러 타입: ${e.runtimeType}');

        // 연결 해제 시도
        try {
          await _device?.disconnect();
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (disconnectError) {
          print('[BLE] 연결 해제 중 오류: $disconnectError');
        }

        // 마지막 시도가 아니면 재시도 전 대기
        if (i < retries - 1) {
          final waitTime = (i + 1) * 1000; // 점진적 대기 시간
          print('[BLE] ${waitTime}ms 후 재시도...');
          await Future.delayed(Duration(milliseconds: waitTime));
        } else {
          onConnectionStateChanged?.call(false);
          return false;
        }
      }
    }
    return false;
  }

  Future<void> _discoverServices() async {
    if (_device == null) {
      throw Exception('기기가 null입니다');
    }

    try {
      print('[BLE] 서비스 발견 시작...');
      final services = await _device!.discoverServices();
      print('[BLE] 서비스 수: ${services.length}');

      bool serviceFound = false;
      for (var s in services) {
        print('[BLE] 서비스 발견: ${s.uuid}');
        if (s.uuid != serviceUuid) continue;

        serviceFound = true;
        print('[BLE] 대상 서비스 발견: ${s.uuid}');
        print('[BLE] Characteristic 수: ${s.characteristics.length}');

        for (var c in s.characteristics) {
          print('[BLE] Characteristic: ${c.uuid}, 속성: ${c.properties}');
          if (c.uuid == writeCharUuid) {
            _txChar = c;
            print('[BLE] Write 특성 설정됨. 속성: ${c.properties}');
          }

          if (c.uuid == notifyCharUuid) {
            _rxChar = c;
            print('[BLE] Notify 특성 설정됨');
          }
        }
      }

      if (!serviceFound) {
        throw Exception('대상 서비스($serviceUuid)를 찾을 수 없습니다');
      }

      if (_txChar == null) {
        throw Exception('Write 특성($writeCharUuid)을 찾을 수 없습니다');
      }

      if (_rxChar == null) {
        throw Exception('Notify 특성($notifyCharUuid)을 찾을 수 없습니다');
      }

      // Notify 활성화
      print('[BLE] Notify 활성화 중...');
      await _rxChar!.setNotifyValue(true);
      print('[BLE] Notify 활성화 완료');

      _rxChar!.lastValueStream.listen((v) {
        try {
          final response = String.fromCharCodes(v);
          print('[BLE] Notification: $response');
          onPairingResponse?.call(response);
        } catch (e) {
          print('[BLE] Notification 오류: $e');
        }
      });

      print('[BLE] 서비스 발견 완료');
    } catch (e) {
      print('[BLE] 서비스 발견 실패: $e');
      _txChar = null;
      _rxChar = null;
      rethrow;
    }
  }

  Future<bool> connect(
      {Duration scanTimeout = const Duration(seconds: 8)}) async {
    return await initAndConnect(scanTimeout: scanTimeout);
  }

  // ✅✅✅ [수정된 부분 1] ✅✅✅
  Future<void> sendJson(Map<String, dynamic> msg) async {
    if (_txChar == null) {
      print('[BLE] 전송 실패: 연결 안됨');
      throw Exception("Not connected");
    }

    try {
      final jsonStr = json.encode(msg);
      final data = utf8.encode(jsonStr);

      if (data.length > maxChunkSize) {
        print('[BLE] 데이터가 너무 큼 (${data.length} 바이트), 청크 전송 사용');
        await sendJsonInChunks(msg);
        return;
      }

      // 특성이 지원하는 쓰기 방식을 동적으로 결정
      final useWithoutResponse = _txChar!.properties.writeWithoutResponse;

      print(
          '[BLE] 전송: ${jsonStr.substring(0, jsonStr.length > 100 ? 100 : jsonStr.length)}... (mode: ${useWithoutResponse ? 'withoutResponse' : 'withResponse'})');
      await _txChar!.write(data, withoutResponse: useWithoutResponse);
      print('[BLE] 전송 성공');
    } catch (e) {
      print('[BLE] 전송 오류: $e');
      throw e;
    }
  }

  // ✅✅✅ [수정된 부분 2] ✅✅✅
  Future<void> sendJsonInChunks(Map<String, dynamic> msg) async {
    if (_txChar == null) {
      throw Exception("Not connected");
    }

    try {
      final jsonStr = json.encode(msg);
      final totalChunks = (jsonStr.length / maxChunkSize).ceil();

      // 특성이 지원하는 쓰기 방식을 동적으로 결정
      final useWithoutResponse = _txChar!.properties.writeWithoutResponse;

      print(
          '[BLE] 청크 전송 시작: 총 ${totalChunks}개 청크 (${jsonStr.length} 바이트), mode: ${useWithoutResponse ? 'withoutResponse' : 'withResponse'}');

      for (int i = 0; i < totalChunks; i++) {
        final start = i * maxChunkSize;
        final end = (start + maxChunkSize > jsonStr.length)
            ? jsonStr.length
            : start + maxChunkSize;
        final chunkData = jsonStr.substring(start, end);

        final header = '<CHUNK:$i/$totalChunks>';
        final chunkWithHeader = header + chunkData;
        final chunkBytes = utf8.encode(chunkWithHeader);

        await _txChar!.write(chunkBytes, withoutResponse: useWithoutResponse);
        print('[BLE] 청크 ${i + 1}/$totalChunks 전송 (${chunkBytes.length} 바이트)');

        await Future.delayed(const Duration(milliseconds: 50));
      }

      final endSignal = utf8.encode('<CHUNK:END>');
      await _txChar!.write(endSignal, withoutResponse: useWithoutResponse);
      print('[BLE] 청크 전송 완료');
    } catch (e) {
      print('[BLE] 청크 전송 오류: $e');
      throw e;
    }
  }

  void _startConnectionMonitoring() {
    _connectionSubscription?.cancel();
    if (_device != null) {
      _connectionSubscription = _device!.connectionState.listen((state) {
        print('[BLE] 연결 상태 변경: $state');
        if (state == BluetoothConnectionState.connected) {
          final name = _device?.advName.isNotEmpty == true
              ? _device!.advName
              : (_device?.platformName ?? 'Ambient');
          print('[BLE] 기기 연결됨: $name');
          onDeviceNameChanged?.call(name);
          onConnectionStateChanged?.call(true);
        } else if (state == BluetoothConnectionState.disconnected) {
          print('[BLE] 기기 연결 해제됨');
          onConnectionStateChanged?.call(false);
          _txChar = null;
          _rxChar = null;
        } else if (state == BluetoothConnectionState.connecting) {
          print('[BLE] 연결 중...');
        } else if (state == BluetoothConnectionState.disconnecting) {
          print('[BLE] 연결 해제 중...');
        }
      }, onError: (error) {
        print('[BLE] 연결 모니터링 에러: $error');
        onConnectionStateChanged?.call(false);
        _txChar = null;
        _rxChar = null;
      });
    }
  }

  Stream<List<BluetoothDevice>> startScan(
      {Duration timeout = const Duration(seconds: 30)}) async* {
    _scannedDevices.clear();
    if (!await _ensurePermissions()) {
      yield [];
      return;
    }

    await FlutterBluePlus.startScan(timeout: timeout);
    await for (List<ScanResult> results in FlutterBluePlus.scanResults) {
      _scannedDevices.clear();
      for (ScanResult r in results) {
        if (r.device.platformName
            .toLowerCase()
            .startsWith(namePrefix.toLowerCase())) {
          if (!_scannedDevices.any((d) => d.remoteId == r.device.remoteId)) {
            _scannedDevices.add(r.device);
          }
        }
      }
      yield List.from(_scannedDevices);
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      _device = device;
      return await _connectSimple();
    } catch (error) {
      debugPrint('connectToDevice error: $error');
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      print('[BLE] 연결 해제 시작...');
      _connectionSubscription?.cancel();
      _connectionSubscription = null;

      if (_device != null) {
        try {
          final currentState = await _device!.connectionState.first;
          if (currentState == BluetoothConnectionState.connected) {
            await _device!.disconnect();
            print('[BLE] 연결 해제 완료');
          }
        } catch (e) {
          print('[BLE] 연결 해제 중 오류 (무시): $e');
        }
      }

      _device = null;
      _txChar = null;
      _rxChar = null;
      onConnectionStateChanged?.call(false);
      print('[BLE] 상태 초기화 완료');
    } catch (e) {
      print('[BLE] disconnect 오류: $e');
      // 에러가 발생해도 상태는 초기화
      _device = null;
      _txChar = null;
      _rxChar = null;
      onConnectionStateChanged?.call(false);
    }
  }

  Future<void> dispose() async {
    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();
    await disconnect();
  }
}
