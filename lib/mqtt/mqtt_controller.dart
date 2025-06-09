import 'dart:async';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttStringMessage {
  final String topic;
  final String payload;
  MqttStringMessage(this.topic, this.payload);
}

class MqttController {
  static final MqttController _instance = MqttController._internal();
  factory MqttController() => _instance;
  MqttController._internal();

  final String broker = '5f2bc0b8926d4530b7d3d10646ca602c.s1.eu.hivemq.cloud';
  final int port = 8883;
  final String username = 'antoniooo';
  final String password = 'x@_!k#GRs7NV.LP';
  final String clientIdentifier = 'aaaa';

  Timer? _handshakeTimer;
  bool _espConnected = false;
  int _reconnectAttempts = 0;

  late MqttServerClient client;
  bool _isInitialized = false;

  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  final StreamController<MqttStringMessage> _messageController = StreamController<MqttStringMessage>.broadcast();

  bool get isInitialized => _isInitialized;
  bool get isConnected => _isInitialized && client.connectionStatus?.state == MqttConnectionState.connected;
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<MqttStringMessage> get messageStream => _messageController.stream;

  Future<void> connect() async {
    if (_isInitialized && isConnected) return;

    client = MqttServerClient(broker, clientIdentifier);
    _isInitialized = true;

    client.port = port;
    client.secure = true;
    client.keepAlivePeriod = 20;
    client.logging(on: true);
    client.onConnected = onConnected;
    client.onDisconnected = onDisconnected;
    // client.onSubscribed = onSubscribed;
    // client.onUnsubscribed = onUnsubscribed;
    // client.pongCallback = pong;

    // Optional: configure security context
    // client.securityContext = SecurityContext.defaultContext;

    final connMess = MqttConnectMessage()
        .authenticateAs(username, password)
        .withClientIdentifier(clientIdentifier)
        .withWillTopic('willtopic')
        .withWillMessage('Will message')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;
    client.setProtocolV311();

    try {
      // print('Connecting to MQTT broker...');
      await client.connect();
      _reconnectAttempts = 0;

      client.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final recMess = c[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final topic = c[0].topic;

        _messageController.add(MqttStringMessage(topic, payload));

        if (topic == "smartflood/status" && (payload == "ESP32_ACK" || payload == "ESP32_PING")) {
          _espConnected = true;
          _connectionController.add(true);
        }
      });
    } catch (e) {
      _isInitialized = false;
      // print('MQTT connection exception: $e');
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (!_isInitialized) return;

    // print('Disconnecting...');
    try {
      client.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
      _isInitialized = false;
      // print('Disconnected successfully');
    } catch (e) {
      // print('Error during disconnect: $e');
      rethrow;
    }
  }

  void publishMessage(String topic, String message) {
    if (!isConnected) {
      // print('Cannot publish - not connected');
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    // print('Published to $topic: $message');
  }

  Future<void> subscribe(String topic) async {
    if (!isConnected) throw Exception('Cannot subscribe - not connected');
    // print('Subscribing to $topic');
    client.subscribe(topic, MqttQos.atLeastOnce);
  }

  Future<void> unsubscribe(String topic) async {
    if (!isConnected) throw Exception('Cannot unsubscribe - not connected');
    // print('Unsubscribing from $topic');
    client.unsubscribe(topic);
  }

  void onConnected() {
    print('Connected to MQTT broker');
    _connectionController.add(true);
    _startHandshake();
  }

  void onDisconnected() {
    print('Disconnected from MQTT broker');
    _connectionController.add(false);

    if (_reconnectAttempts < 5) {
      _reconnectAttempts++;
      Future.delayed(Duration(seconds: 3 * _reconnectAttempts), () {
        // print('Reconnecting... attempt $_reconnectAttempts');
        connect();
      });
    } else {
      // print('Max reconnection attempts reached');
    }
  }

  // void onSubscribed(String topic) => print('Subscribed to $topic');
  // void onUnsubscribed(String? topic) => print('Unsubscribed from $topic');
  // void pong() => print('Ping response received');

  Future<void> dispose() async {
    await disconnect();
    _connectionController.close();
    _messageController.close();
  }

  void _startHandshake() {
    _handshakeTimer?.cancel();
    _handshakeTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (isConnected) {
        // publishMessage("smartflood/handshake", "APP_CONNECTED");
      }
    });
  }
}
