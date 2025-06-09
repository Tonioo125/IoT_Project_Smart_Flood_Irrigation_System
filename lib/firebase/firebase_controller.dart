import 'package:firebase_database/firebase_database.dart';

class FirebaseController {
  final DatabaseReference _ref = FirebaseDatabase.instance.ref().child('sensorData');

  Stream<Map?> get sensorDataStream =>
      _ref.onValue.map((event) => event.snapshot.value as Map?);
}
