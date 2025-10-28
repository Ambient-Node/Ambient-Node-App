import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// 개선된 BLE 서비스: 간소화된 연결 로직과 재시도 메커니즘 포함
class TestBleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _rxChar;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  // 필터: 기기 이름 또는 서비스 UUID로 찾기
  final String namePrefix;
  final Guid? serviceUuid;
  final Guid? writeCharUuid;
  final Guid? notifyCharUuid;

  // 콜백
  Function(bool)? onConnectionStateChanged;
  Function(String)? onPairingResponse; // 주변기기에서 오는 Notify 메시지
  Function(BluetoothBondState)? onBondStateChanged; // 본딩 상태 콜백(선택)
  Function(String)? onDeviceNameChanged; // 연결된 기기 이름 보고

  // 스캔된 기기 목록
  final List<BluetoothDevice> _scannedDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  TestBleService({
    this.namePrefix = 'Ambient',
    this.serviceUuid,
    this.writeCharUuid,
    this.notifyCharUuid,
  });

  Future<bool> _ensurePermissions() async {
    // 개선된 권한 요청: 더 포괄적인 권한 포함
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    final ok = statuses.values.every((s) => s.isGranted);
    return ok;
  }

  // 간소화된 초기화 및 연결 메서드
  Future<bool> initAndConnect(
      {Duration scanTimeout = const Duration(seconds: 5)}) async {
    try {
      onConnectionStateChanged?.call(false);

      // 권한 확인
      final granted = await _ensurePermissions();
      if (!granted) {
        onConnectionStateChanged?.call(false);
        return false;
      }

      // 블루투스 어댑터 상태 확인
      final isOn =
          await FlutterBluePlus.adapterState.first == BluetoothAdapterState.on;
      if (!isOn) {
        debugPrint("Bluetooth is off");
        onConnectionStateChanged?.call(false);
        return false;
      }

      // 스캔 및 기기 찾기
      await FlutterBluePlus.startScan(timeout: scanTimeout);
      await for (final r in FlutterBluePlus.scanResults) {
        for (final result in r) {
          final name = result.device.advName.isNotEmpty
              ? result.device.advName
              : result.device.platformName;

          if (name.toLowerCase().contains(namePrefix.toLowerCase()) ||
              name.toLowerCase().contains("fan")) {
            _device = result.device;
            // 발견 즉시 이름 콜백 (옵션)
            onDeviceNameChanged?.call(name);
            await FlutterBluePlus.stopScan();
            return await _connectWithRetry();
          }
        }
      }

      await FlutterBluePlus.stopScan();
      debugPrint("No matching device found");
      onConnectionStateChanged?.call(false);
      return false;
    } catch (error) {
      debugPrint('BLE initAndConnect error: $error');
      onConnectionStateChanged?.call(false);
      return false;
    }
  }

  // 재시도 메커니즘을 포함한 연결
  Future<bool> _connectWithRetry({int retries = 3}) async {
    for (int i = 0; i < retries; i++) {
      try {
        await _device?.connect(timeout: const Duration(seconds: 10));

        // 본딩 (라즈베리파이와의 보안 연결을 위해)
        final bonded = await _ensureBonded(_device!);
        if (!bonded) {
          await _device?.disconnect();
          if (i == retries - 1) return false;
          continue;
        }

        // 서비스 발견
        await _discoverServices();

        // 연결 상태 모니터링 시작
        _startConnectionMonitoring();

        // 연결 성공: 이름 보고
        final connectedName = _device?.advName.isNotEmpty == true
            ? _device!.advName
            : (_device?.platformName ?? 'Ambient');
        onDeviceNameChanged?.call(connectedName);
        onConnectionStateChanged?.call(true);
        return true;
      } catch (e) {
        debugPrint('Connection attempt ${i + 1} failed: $e');
        await _device?.disconnect();
        if (i == retries - 1) {
          onConnectionStateChanged?.call(false);
          return false;
        }
      }
    }
    return false;
  }

  // 개선된 서비스 발견 로직
  Future<void> _discoverServices() async {
    final services = await _device?.discoverServices();
    for (var s in services ?? []) {
      for (var c in s.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          _txChar = c;
        }
        if (c.properties.notify) {
          _rxChar = c;
        }
      }
    }

    // Notification 특성 구독
    if (_rxChar != null) {
      await _rxChar!.setNotifyValue(true);
      _rxChar!.lastValueStream.listen((v) {
        try {
          final response = String.fromCharCodes(v);
          debugPrint("BLE Notification received: $response");
          onPairingResponse?.call(response);
        } catch (e) {
          debugPrint('BLE Notification parse error: $e');
        }
      });
    }
  }

  // 기존 connect 메서드 (하위 호환성을 위해 유지)
  Future<bool> connect(
      {Duration scanTimeout = const Duration(seconds: 8)}) async {
    return await initAndConnect(scanTimeout: scanTimeout);
  }

  // 개선된 데이터 전송 메서드
  Future<void> send(String data) async {
    if (_txChar == null) throw Exception("Not connected");
    try {
      await _txChar!.write(data.codeUnits, withoutResponse: true);
      debugPrint('BLE data sent successfully: $data');
    } catch (e) {
      debugPrint('BLE send error: $e');
      throw e;
    }
  }

  // JSON 데이터 전송을 위한 편의 메서드
  Future<void> sendJson(Map<String, dynamic> msg) async {
    if (_txChar == null) throw Exception("Not connected");
    try {
      final data = utf8.encode(json.encode(msg));
      await _txChar!.write(data, withoutResponse: true);
      debugPrint('BLE JSON data sent successfully: ${json.encode(msg)}');
    } catch (e) {
      debugPrint('BLE JSON send error: $e');
      throw e;
    }
  }

  void _startConnectionMonitoring() {
    _connectionSubscription?.cancel();
    if (_device != null) {
      _connectionSubscription = _device!.connectionState.listen((state) {
        debugPrint('BLE connection state: $state');
        if (state == BluetoothConnectionState.connected) {
          final connectedName = _device?.advName.isNotEmpty == true
              ? _device!.advName
              : (_device?.platformName ?? 'Ambient');
          onDeviceNameChanged?.call(connectedName);
          onConnectionStateChanged?.call(true);
        } else if (state == BluetoothConnectionState.disconnected) {
          onConnectionStateChanged?.call(false);
          _txChar = null;
        }
      });
    }
  }

  // 기기 스캔 시작 (1초마다 업데이트)
  Stream<List<BluetoothDevice>> startScan(
      {Duration timeout = const Duration(seconds: 30)}) async* {
    _scannedDevices.clear();
    _scanSubscription?.cancel();

    if (!await _ensurePermissions()) {
      yield [];
      return;
    }

    if (await FlutterBluePlus.adapterState.firstWhere((s) => true) !=
        BluetoothAdapterState.on) {
      yield [];
      return;
    }

    await FlutterBluePlus.startScan(timeout: timeout);

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      _scannedDevices.clear();
      for (ScanResult r in results) {
        if (r.device.platformName.isNotEmpty &&
            r.device.platformName
                .toLowerCase()
                .startsWith(namePrefix.toLowerCase())) {
          if (!_scannedDevices.any((d) => d.remoteId == r.device.remoteId)) {
            _scannedDevices.add(r.device);
          }
        }
      }
    });

    await for (List<ScanResult> results in FlutterBluePlus.scanResults) {
      _scannedDevices.clear();
      for (ScanResult r in results) {
        if (r.device.platformName.isNotEmpty &&
            r.device.platformName
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

  // 특정 기기에 연결 (간소화된 버전)
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      onConnectionStateChanged?.call(false);
      _device = device;
      return await _connectWithRetry();
    } catch (error) {
      debugPrint('BLE connectToDevice error: $error');
      onConnectionStateChanged?.call(false);
      return false;
    }
  }

  // 본딩 보장 유틸리티: 안드로이드에서 OS PIN 입력 UI를 띄우고 완료 대기
  Future<bool> _ensureBonded(BluetoothDevice device,
      {Duration timeout = const Duration(seconds: 60)}) async {
    try {
      // 이미 본딩되어 있으면 통과
      final initial = await device.bondState.firstWhere((_) => true);
      if (initial == BluetoothBondState.bonded) {
        onBondStateChanged?.call(BluetoothBondState.bonded);
        return true;
      }

      // 본딩 시작 (안드로이드에서만 의미 있음)
      await device.createBond();

      final completer = Completer<bool>();
      late final StreamSubscription sub;

      sub = device.bondState.listen((state) {
        onBondStateChanged?.call(state);
        if (state == BluetoothBondState.bonded) {
          completer.complete(true);
          sub.cancel();
        } else if (state == BluetoothBondState.none) {
          completer.complete(false);
          sub.cancel();
        }
      });

      final ok = await completer.future.timeout(timeout, onTimeout: () {
        sub.cancel();
        return false;
      });
      return ok;
    } catch (e) {
      debugPrint('Bonding error: $e');
      return false;
    }
  }

  Future<void> dispose() async {
    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();
    await _device?.disconnect();
    _device = null;
    _txChar = null;
    _rxChar = null;
  }
}
