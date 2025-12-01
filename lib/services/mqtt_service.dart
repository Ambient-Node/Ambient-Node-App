import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? _client;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool get isConnected => _client != null && _client!.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> initialize({String host = 'test.mosquitto.org', int port = 1883, String clientId = 'ambient_node_app'}) async {
    if (isConnected) return;

    _client = MqttServerClient(host, clientId);
    _client!.port = port;
    _client!.logging(on: false);
    _client!.keepAlivePeriod = 20;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect();
    } catch (e) {
      try {
        _client?.disconnect();
      } catch (_) {}
    }

    _client?.updates?.listen(_onMessageReceived);
  }

  void _onDisconnected() {}
  void _onConnected() {}
  void _onSubscribed(String topic) {}

  void subscribe(String topic) {
    if (!isConnected) return;
    _client?.subscribe(topic, MqttQos.atLeastOnce);
  }

  void publish(String topic, Map<String, dynamic> payload) {
    if (!isConnected) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));
    _client?.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void _onMessageReceived(List<MqttReceivedMessage<MqttMessage>>? events) {
    if (events == null) return;
    for (final event in events) {
      final topic = event.topic;
      final payload = event.payload;
      if (payload is MqttPublishMessage) {
        final pt = MqttPublishPayload.bytesToStringAsString(payload.payload.message);
        try {
          final decoded = jsonDecode(pt);
          if (decoded is Map<String, dynamic>) {
            final wrapped = <String, dynamic>{'__topic': topic, ...decoded};
            _messageController.add(wrapped);
          } else {
            _messageController.add({'__topic': topic, 'data': decoded});
          }
        } catch (e) {
          // ignore invalid JSON
        }
      }
    }
  }

  void dispose() {
    try {
      _client?.disconnect();
    } catch (_) {}
    _messageController.close();
  }
}

// Provide a simple singleton accessor
MqttService get MqttServiceInstance => MqttService();
