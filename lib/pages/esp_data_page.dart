import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../widgets/data_card.dart';
import '../mqtt/mqtt_controller.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class EspDataPage extends StatefulWidget {
  const EspDataPage({super.key});

  @override
  State<EspDataPage> createState() => _EspDataPageState();
}

class _EspDataPageState extends State<EspDataPage> {
  // Sensor data
  String heightA = '---';
  String heightB = '---';
  String waterLevelA = '---';
  String waterLevelB = '---';
  String pumpStatusA = 'IDLE';
  String pumpStatusB = 'IDLE';

  // System state
  bool isFirebaseConnected = false;
  bool isMqttConnected = false;
  String source = 'A';
  String target = 'B';
  bool isRedirecting = false;

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  double? _lastHeightA;
  double? _lastHeightB;
  DateTime _lastNotifiedA = DateTime.now().subtract(const Duration(minutes: 3));
  DateTime _lastNotifiedB = DateTime.now().subtract(const Duration(minutes: 3));

  // Subscriptions
  StreamSubscription<bool>? _mqttConnectionSubscription;
  StreamSubscription<DatabaseEvent>? _firebaseSubscriptionA;
  StreamSubscription<DatabaseEvent>? _firebaseSubscriptionB;

  @override
  void initState() {
    super.initState();
    _initConnections();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    // Request permission
    await Permission.notification.request();
  }

  Future<void> _showNotification(String message) async {
    const androidDetails = AndroidNotificationDetails(
      'flood_channel_id',
      'Flood Alerts',
      channelDescription: 'Notifications for height drops',
      importance: Importance.max,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    await _notifications.show(
      0,
      'Alert',
      message,
      notificationDetails,
    );
  }

  Future<void> _initConnections() async {
    // Initialize MQTT (only for sending commands now)
    try {
      await MqttController().connect();
      _mqttConnectionSubscription = MqttController().connectionStream.listen((connected) {
        if (mounted) {
          setState(() => isMqttConnected = connected);
        }
      });
      if (mounted) {
        setState(() => isMqttConnected = MqttController().isConnected);
      }
    } catch (e) {
      // print("MQTT Connection Error: $e");
    }

    // Firebase listeners
    _firebaseSubscriptionA = FirebaseDatabase.instance.ref('sensorData_A').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (mounted) {
        setState(() {
          // print("Firebase data received for Reservoir A: $data");

          if (data != null) {
            heightA = "${data['height'] ?? '---'}";
            double? newHeight = double.tryParse(heightA);

            // print("Parsed heightA: $newHeight, Last heightA: $_lastHeightA");

            if (newHeight != null && _lastHeightA != null) {
              double diff = _lastHeightA! - newHeight;
              print("Height difference: $diff");

              final timeSinceLastNotif = DateTime.now().difference(_lastNotifiedA);
              // print("Time since last notification: ${timeSinceLastNotif.inSeconds} seconds");

              if (diff >= 3.0 && timeSinceLastNotif > const Duration(minutes: 1)) {
                // print("Triggering notification...");
                _showNotification("Reservoir A: Water level increased ${diff.toStringAsFixed(1)} cm");
                _lastNotifiedA = DateTime.now();
              } else {
                // print("Notification NOT triggered: Condition not met.");
              }
            } else {
              // print("Notification check skipped due to null newHeight or _lastHeightA");
            }

            _lastHeightA = newHeight;

            waterLevelA = "${data['waterlevel'] ?? '---'}";
            pumpStatusA = "${data['pumpStatus'] ?? 'IDLE'}";
            isFirebaseConnected = true;
            isRedirecting = pumpStatusA == 'ON' || pumpStatusB == 'ON';

            print("Updated UI values - WaterLevelA: $waterLevelA, PumpStatusA: $pumpStatusA, IsRedirecting: $isRedirecting");
          } else {
            print("Data from Firebase is null");
          }
        });
      }
    });


    _firebaseSubscriptionB = FirebaseDatabase.instance.ref('sensorData_B').onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (mounted) {
        setState(() {
          if (data != null) {
            heightB = "${data['height'] ?? '---'}";
            double? newHeight = double.tryParse(heightB);
            if (newHeight != null && _lastHeightB != null) {
              double diff = _lastHeightB! - newHeight;
              if (diff >= 3.0 && DateTime.now().difference(_lastNotifiedB) > const Duration(minutes: 1)) {
                _showNotification("Reservoir B: Water level increased by ${diff.toStringAsFixed(1)} cm");
                _lastNotifiedB = DateTime.now();
              }
            }
            _lastHeightB = newHeight;
            waterLevelB = "${data['waterlevel'] ?? '---'}";
            pumpStatusB = "${data['pumpStatus'] ?? 'IDLE'}";
            isFirebaseConnected = true;
            isRedirecting = pumpStatusA == 'ON' || pumpStatusB == 'ON';
          }
        });
      }
    });
  }

  void toggleRedirect() {
    if (!MqttController().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("MQTT not connected yet")),
      );
      return;
    }

    // setState(() => isRedirecting = !isRedirecting);

    try {
      String direction = '';
      if (pumpStatusA == 'IDLE' && source == 'A'){
        direction = "ON_$source$target";
      } else if (pumpStatusA != 'IDLE' && source == 'A'){
        direction = "OFF_$source$target";
      } else if (pumpStatusB == 'IDLE' && source == 'B'){
        direction = "ON_$source$target";
      } else if (pumpStatusB != 'IDLE' && source == 'B'){
        direction = "OFF_$source$target";
      }
      MqttController().publishMessage("smartflood/redirect", direction);
    } catch (e) {
      setState(() => isRedirecting = !isRedirecting);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send command: $e")),
      );
    }
  }

  @override
  void dispose() {
    _mqttConnectionSubscription?.cancel();
    _firebaseSubscriptionA?.cancel();
    _firebaseSubscriptionB?.cancel();
    MqttController().disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Smart Flood Irrigator",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/firestore'),
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('View Firestore Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurpleAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),

              // Connection Status
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Row(
                  children: [
                    _buildStatusDot("Firebase", isFirebaseConnected),
                    const SizedBox(width: 16),
                    _buildStatusDot("MQTT", isMqttConnected),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Data Grid
              Row(
                children: [
                  _buildColumnCard(
                    "Source",
                    source,
                        (value) => setState(() => source = value!),
                    double.tryParse(source == 'A' ? heightA : heightB) ?? 0.0,
                    double.tryParse(source == 'A' ? waterLevelA : waterLevelB) ?? 0.0,
                    source == 'A' ? pumpStatusA : pumpStatusB,
                  ),

                  _buildColumnCard(
                    "Target",
                    target,
                        (value) => setState(() => target = value!),
                    double.tryParse(target == 'A' ? heightA : heightB) ?? 0.0,
                    double.tryParse(target == 'A' ? waterLevelA : waterLevelB) ?? 0.0,
                    target == 'A' ? pumpStatusA : pumpStatusB,
                  ),

                ],
              ),

              const SizedBox(height: 30),

              // Redirect Button
              Center(
                child: ElevatedButton.icon(
                  icon: Icon(
                    ((pumpStatusA != 'IDLE' && source == 'A') || (pumpStatusB != 'IDLE' && source == 'B')) && source != target
                        ? Icons.stop_circle
                        : Icons.sync_alt,
                  ),
                  onPressed: ((pumpStatusA != 'IDLE' && source == 'A') || (pumpStatusB != 'IDLE' && source == 'B') && source != target)
                      ? toggleRedirect
                      : (source != target ? toggleRedirect : null),
                  label: Text(
                    ((pumpStatusA != 'IDLE' && source == 'A') || (pumpStatusB != 'IDLE' && source == 'B')) && source != target
                        ? "STOP REDIRECT"
                        : (source != target ? "START REDIRECT" : "UNABLE TO REDIRECT"),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ((pumpStatusA != 'IDLE' && source == 'A') || (pumpStatusB != 'IDLE' && source == 'B'))
                        ? Colors.redAccent
                        : (source != target ? Colors.green : Colors.grey),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusDot(String label, bool isConnected) {
    return Row(
      children: [
        Icon(Icons.circle, color: isConnected ? Colors.green : Colors.red, size: 14),
        const SizedBox(width: 6),
        Text(
          '$label: ${isConnected ? 'Connected' : 'Disconnected'}',
          style: TextStyle(fontSize: 12, color: isConnected ? Colors.green : Colors.red),
        ),
      ],
    );
  }

  Widget _buildColumnCard(
      String label,
      String selectedValue,
      ValueChanged<String?> onChanged,
      double height,
      double waterLevel,
      String pumpStatus,
      ) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: selectedValue,
              decoration: InputDecoration(
                labelText: label,
                // prefixIcon: const Icon(Icons.water_drop_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.white,
              ),
              items: ['A', 'B'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text("Reservoir $value"),
                );
              }).toList(),
              onChanged: onChanged,
            ),
            const SizedBox(height: 12),
            EspCard(title: "Sensor Distance", value: "$height cm"),
            EspCard(title: "Water Level", value: "$waterLevel%"),
            EspCard(
              title: "Pump Status",
              value: pumpStatus.replaceAll('_', ' '),
              color: pumpStatus != 'IDLE' ? Colors.red[50] : Colors.grey[100],
            ),
          ],
        ),
      ),
    );
  }

}