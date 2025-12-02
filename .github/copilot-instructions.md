<!-- Copilot instructions for Ambient-Node-App -->
# Ambient-Node App — Copilot Instructions

This file gives AI coding agents the concise, codebase-specific knowledge needed to be productive immediately.


- **Project type:** Flutter app (root `pubspec.yaml`). Use `flutter` tooling for builds/tests.
- **Entry point:** `lib/main.dart` — app shell, navigation, and the primary place where services are instantiated. `MainShell` wires services and lifts app state.

Key Concepts
- **BLE layer:** `lib/services/ble_service.dart` is a singleton (`BleService`) that exposes streams and helpers:
  - `connectionStateStream` (type `BleConnectionState`) — connection lifecycle events.
  - `dataStream` — parsed JSON payloads emitted from the device.
  - `logStream` — textual logs for debugging.
  - `BleConstants` contains UUIDs, `DEVICE_NAME_PREFIX`, and `MAX_CHUNK_SIZE` (chunking protocol).
  - Chunking protocol: large JSON messages are split into chunks prefixed with `<CHUNK:i/total>` and terminated with `<CHUNK:END>`; reassembly happens in `_handleChunk`.

Service patterns
- Services are singletons and favor streams/controllers instead of global state management. Typical usage:
  - Instantiate: `final ble = BleService();`
  - Initialize: `ble.initialize()` (called in `MainShell` during startup).
  - Subscribe: `ble.connectionStateStream.listen(...)`, `ble.dataStream.listen(...)`, `ble.logStream.listen(...)`.

UI structure & state
- Screens live in `lib/screens/` and are assembled in `MainShell` (`lib/main.dart`). State is lifted to `MainShell`, passed to children via constructors and callbacks (no Provider/Bloc used).

Developer Workflows (commands)
- Install deps: `flutter pub get`
- Run on device/emulator: `flutter run -d <device-id>` (from repo root).
- Run Android build: `flutter build apk` or, from `android\\`, `.
  \\gradlew assembleDebug` (PowerShell).
- Run tests: `flutter test`.
- Format code: `dart format .` or `flutter format .`

Platform / Permissions
- BLE uses `flutter_blue_plus` and requests runtime permissions on Android. See `BleService._requestPermissions()` which asks for:
  - `Permission.bluetoothScan`, `Permission.bluetoothConnect`, `Permission.locationWhenInUse`.
- If device name or UUIDs change, update `BleConstants` in `ble_service.dart`.

Files to inspect first (quick tour)
- `lib/main.dart` — app shell, lifecycle, `BleService` usage, and UI wiring.
- `lib/services/ble_service.dart` — BLE protocol, chunking, permissions, streams.
- `lib/services/analytics_service.dart` — analytics hooks used across UI (static helpers).
- `lib/screens/*` — screen implementations that receive callbacks and streams from `MainShell`.
- `pubspec.yaml` — dependencies (notable: `flutter_blue_plus`, `mqtt_client`, `permission_handler`).

When modifying BLE or protocol code
- Keep `BleConstants` in sync with device firmware.
- Preserve chunk start/header and termination markers (`<CHUNK:...>` and `<CHUNK:END>`) unless coordinating firmware change.
- Add unit tests for JSON parsing logic (in `ble_service.dart`) by isolating `_handleChunk`/`_onDataReceived` behavior if possible.

Developer hints for PRs
- Demonstrate manual testing steps in PR description: device used, Android/iOS, sample JSON payloads, and how to reproduce connection flows.
- For UI changes, include screenshots and a short note whether BLE behavior had to be mocked; the app already has `_isTestMode` in `MainShell` for quick toggling — reference when adding tests.

If anything in this file is unclear or you'd like additional examples (e.g., typical JSON messages, wiring a new service, or a guided PR checklist), tell me which area and I'll expand it.

JSON message formats (observed and recommended)
These are the JSON shapes used between the App and the BLE device. `MainShell._sendData()` appends `user_id` when available and always encodes to JSON before sending via `BleService.sendJson()`.

App → Device (observed formats)
- Mode change (motor or wind):

  {
    "action": "mode_change",
    "type": "motor",            // 'motor' or 'wind'
    "mode": "manual_control",   // motor: 'manual_control'|'rotation'|'ai_tracking' OR wind: 'normal_wind'|'natural_wind'
    "timestamp": "2025-11-29T12:34:56.789Z",
    "user_id": "<optional-user-id>"
  }

- Speed change:

  {
    "action": "speed_change",
    "speed": 3,                  // integer 0..5
    "timestamp": "...",
    "user_id": "..."
  }

- Timer control:

  {
    "action": "timer",
    "duration_sec": 1800,        // 0 to cancel
    "timestamp": "...",
    "user_id": "..."
  }

- Manual directional control:

  {
    "action": "direction_change",
    "direction": "l",          // first letter used in app ('l','r','u','d' etc.)
    "toggleOn": 1,               // 1 = start, 0 = stop
    "timestamp": "...",
    "user_id": "..."
  }

App → Device (recommended `animation` action)
- There is no existing animation protocol in the codebase, but if you need to add UI/device animation/control commands, use a clear, versioned action shape. Example:

  {
    "action": "animation",
    "animation": "wave",        // animation name
    "params": { "speed": 1.2 }, // animation parameters
    "duration_ms": 3000,
    "loop": false,
    "timestamp": "...",
    "user_id": "..."
  }

  - Recommendation: Keep `animation` messages small (< `MAX_CHUNK_SIZE`) or reuse chunking logic for large payloads.

Device → App (observed formats)
- Device may send status or event messages; parsing happens in `BleService._onDataReceived`. Observed / handled cases in code:
  - Shutdown notification: `{ "type": "SHUTDOWN" }` — `MainShell` listens for this and disconnects.
  - Generic JSON sensor/status updates: `{ "type": "STATUS", "payload": { ... } }` or any arbitrary JSON map — app adds to `dataStream`.

- Example sensor update:

  {
    "type": "SENSOR_UPDATE",
    "temperature_c": 23.4,
    "humidity_pct": 48.1,
    "timestamp": "..."
  }

Notes on chunking and robustness
- `BleService` handles chunked messages that begin with `<CHUNK:` and end with `<CHUNK:END>`; chunks are appended to `_chunkBuffer` and decoded when `END` is received.
- Keep message sizes under `BleConstants.MAX_CHUNK_SIZE` when possible. If you change `MAX_CHUNK_SIZE`, update both firmware and app.
- `_onDataReceived` decodes bytes with UTF-8 and runs `json.decode`. If parsing fails, `_log('데이터 파싱 오류')` is emitted — add guarded parsing/tests when changing parsers.

Programming patterns to follow
- Use the singleton service factories (e.g., `BleService()`) rather than creating multiple instances.
- Subscribe to streams in `initState` and cancel in `dispose` (see `MainShell` for reference).
- Use `_isTestMode` in `MainShell` to mock sending/receiving when adding UI changes/tests.

Developer hints for PRs
- Show manual test steps in PR: device model/firmware, Android/iOS, example JSON payloads used for testing.
- If you add new device message types, include sample messages and update `ble_service.dart` tests to validate chunk reassembly and JSON parsing.

If you'd like, I can also:
- Add unit tests skeletons for `_handleChunk` and `_onDataReceived`.
- Generate example payloads for the device firmware team.

If anything here is unclear or you want the animation action shape adjusted, tell me which fields to change and I will update the file.
