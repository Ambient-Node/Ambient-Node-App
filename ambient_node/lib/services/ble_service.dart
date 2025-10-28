import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txChar;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  // 필터: 기기 이름 또는 서비스 UUID로 찾기 (필요시 수정)
  final String
      namePrefix; // 기기 이름 접두사. ex) namePrefix = 'Ambient' 면 기기 이름이 'Ambient' 로 시작하는 기기를 찾음
  final Guid? serviceUuid;
  final Guid? writeCharUuid;
  final Guid? notifyCharUuid;

  // 연결 상태 콜백
  Function(bool)? onConnectionStateChanged;
  Function(String)? onPairingResponse; // 페어링 응답 콜백

  // 스캔된 기기 목록
  final List<BluetoothDevice> _scannedDevices = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  BleService({
    this.namePrefix = 'Ambient',
    this.serviceUuid,
    this.writeCharUuid,
    this.notifyCharUuid,
  });

  Future<bool> _ensurePermissions() async {
    // Android 12+: BLUETOOTH_SCAN/CONNECT, 그 외 위치 권한 필요
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    final ok = statuses.values.every((s) => s.isGranted);
    return ok;
  }

  Future<bool> connect(
      {Duration scanTimeout = const Duration(seconds: 8)}) async {
    try {
      // 연결 시작 시 즉시 false로 설정
      onConnectionStateChanged?.call(false);

      final granted = await _ensurePermissions();
      if (!granted) {
        onConnectionStateChanged?.call(false);
        return false;
      }

      // Bluetooth 상태 확인
      if (await FlutterBluePlus.adapterState.firstWhere((s) => true) !=
          BluetoothAdapterState.on) {
        onConnectionStateChanged?.call(false);
        return false;
      }

      // 스캔 시작
      await FlutterBluePlus.startScan(timeout: scanTimeout);
      BluetoothDevice? found;

      await for (final scanRes in FlutterBluePlus.scanResults) {
        for (final r in scanRes) {
          final name = r.device.advName.isNotEmpty
              ? r.device.advName
              : r.device.platformName;
          final matchesName = name.isNotEmpty &&
              name.toLowerCase().startsWith(namePrefix.toLowerCase());
          final advUuids = r.advertisementData.serviceUuids
              .map((g) => g.str.toLowerCase())
              .toList();
          final matchesService = serviceUuid != null &&
              advUuids.contains(serviceUuid!.str.toLowerCase());
          if (matchesName || matchesService) {
            found = r.device;
            break;
          }
        }
        if (found != null) break;
      }
      await FlutterBluePlus.stopScan();

      found ??= (FlutterBluePlus.lastScanResults.isNotEmpty
          ? FlutterBluePlus.lastScanResults.first.device
          : null);
      if (found == null) {
        onConnectionStateChanged?.call(false);
        return false;
      }

      _device = found;

      // 연결 상태 모니터링 시작
      _startConnectionMonitoring();

      // 연결
      await _device!.connect(autoConnect: false);

      // 서비스/특성 탐색
      final services = await _device!.discoverServices();
      BluetoothCharacteristic? candidate;

      if (serviceUuid != null) {
        BluetoothService? svc;
        for (final s in services) {
          if (s.uuid == serviceUuid) {
            svc = s;
            break;
          }
        }
        if (svc != null && svc.characteristics.isNotEmpty) {
          candidate = _selectWritableCharacteristic(svc.characteristics);
        }
      }

      if (candidate == null) {
        for (final s in services) {
          final c = _selectWritableCharacteristic(s.characteristics);
          if (c != null) {
            candidate = c;
            break;
          }
        }
      }

      if (writeCharUuid != null) {
        for (final c in services.expand((s) => s.characteristics)) {
          if (c.uuid == writeCharUuid) {
            candidate = c;
            break;
          }
        }
      }

      _txChar = candidate;
      // 연결 상태는 _startConnectionMonitoring에서 실제 연결 확인 후 설정
      return true;
    } catch (error) {
      debugPrint('BLE connection error: $error');
      onConnectionStateChanged?.call(false);
      return false;
    }
  }

  BluetoothCharacteristic? _selectWritableCharacteristic(
      List<BluetoothCharacteristic> chars) {
    try {
      return chars.firstWhere(
          (c) => c.properties.writeWithoutResponse || c.properties.write);
    } catch (_) {
      return null;
    }
  }

  Future<void> send(Map<String, dynamic> msg) async {
    if (_txChar == null) return;
    try {
      final data = utf8.encode(json.encode(msg));
      // 항상 writeWithoutResponse 사용 (페어링 불필요)
      await _txChar!.write(data, withoutResponse: true);
      debugPrint('BLE data sent successfully: ${json.encode(msg)}');
    } catch (e) {
      debugPrint('BLE send error: $e');
    }
  }

  void _startConnectionMonitoring() {
    _connectionSubscription?.cancel();
    if (_device != null) {
      _connectionSubscription = _device!.connectionState.listen((state) {
        debugPrint('BLE connection state: $state');

        // 연결 완료 시에만 true로 설정
        if (state == BluetoothConnectionState.connected) {
          debugPrint('BLE actually connected!');
          onConnectionStateChanged?.call(true);
        } else if (state == BluetoothConnectionState.disconnected) {
          // 실제로 연결이 끊어진 경우에만 false
          debugPrint(
              'BLE disconnected! Reason: Connection terminated by remote device');
          onConnectionStateChanged?.call(false);
          _txChar = null;
        }
        // connecting, disconnecting 상태는 무시
      });
    }
  }

  // 기기 스캔 시작 (1초마다 업데이트)
  Stream<List<BluetoothDevice>> startScan(
      {Duration timeout = const Duration(seconds: 30)}) async* {
    _scannedDevices.clear();
    _scanSubscription?.cancel();

    // 권한 확인
    if (!await _ensurePermissions()) {
      yield [];
      return;
    }

    // Bluetooth 상태 확인
    if (await FlutterBluePlus.adapterState.firstWhere((s) => true) !=
        BluetoothAdapterState.on) {
      yield [];
      return;
    }

    // 스캔 시작 (더 긴 타임아웃)
    await FlutterBluePlus.startScan(timeout: timeout);

    // 스캔 결과 스트림 구독
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

    // 스캔된 기기 목록을 스트림으로 전달
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

  // 스캔 중지
  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
  }

  // 특정 기기에 연결
  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      // 연결 시작 시 즉시 false로 설정
      onConnectionStateChanged?.call(false);

      _device = device;
      await _device!.connect();

      // 서비스 발견
      List<BluetoothService> services = await _device!.discoverServices();
      BluetoothService? targetService;

      if (serviceUuid != null) {
        targetService = services.firstWhere(
          (service) => service.uuid == serviceUuid,
          orElse: () => throw Exception('Service not found'),
        );
      } else {
        targetService = services.first;
      }

      // 특성 찾기
      BluetoothCharacteristic? candidate =
          targetService.characteristics.firstWhere(
        (c) => c.properties.write || c.properties.writeWithoutResponse,
        orElse: () => throw Exception('Write characteristic not found'),
      );

      if (writeCharUuid != null) {
        try {
          candidate = targetService.characteristics.firstWhere(
            (c) => c.uuid == writeCharUuid,
          );
        } catch (e) {
          // writeCharUuid가 없으면 기존 candidate 사용
        }
      }

      _txChar = candidate;

      // Notification 특성 찾기 및 구독
      if (notifyCharUuid != null) {
        try {
          BluetoothCharacteristic? notifyChar =
              targetService.characteristics.firstWhere(
            (c) => c.uuid == notifyCharUuid && c.properties.notify,
          );

          // Notification 구독
          await notifyChar.setNotifyValue(true);
          notifyChar.lastValueStream.listen((value) {
            try {
              String response = String.fromCharCodes(value);
              debugPrint('BLE Notification received: $response');
              onPairingResponse?.call(response);
            } catch (e) {
              debugPrint('BLE Notification parse error: $e');
            }
          });

          debugPrint('Notification characteristic subscribed');
        } catch (e) {
          debugPrint(
              'Notification characteristic not found or failed to subscribe: $e');
        }
      }

      _startConnectionMonitoring();
      return true;
    } catch (error) {
      debugPrint('BLE connection error: $error');
      onConnectionStateChanged?.call(false);
      return false;
    }
  }

  void dispose() {
    _connectionSubscription?.cancel();
    _scanSubscription?.cancel();
    _device?.disconnect();
  }
}
