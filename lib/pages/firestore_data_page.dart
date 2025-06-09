import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

class FirestoreDataPage extends StatefulWidget {
  const FirestoreDataPage({super.key});

  @override
  State<FirestoreDataPage> createState() => _FirestoreDataPageState();
}

class _FirestoreDataPageState extends State<FirestoreDataPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Data History'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Sensor Data'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPumpHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildPumpHistoryTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('PumpHistory')
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Error loading pump history'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('No pump history available'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: ListTile(
                leading: _getPumpIcon(data['action']),
                title: Text(
                  _formatPumpAction(data['action']),
                  style: TextStyle(
                    color: _getActionColor(data['action']),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mode: ${data['mode'] ?? 'N/A'}'),
                    if (data['timestamp'] != null)
                      Text(
                        timeago.format(data['timestamp'].toDate()),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('A: ${data['reservoirA_height']?.toStringAsFixed(1) ?? 'N/A'} cm'),
                    Text('B: ${data['reservoirB_height']?.toStringAsFixed(1) ?? 'N/A'} cm'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Icon _getPumpIcon(String action) {
    if (action.contains('A_TO_B')) {
      return const Icon(Icons.arrow_forward, color: Colors.blue);
    } else if (action.contains('B_TO_A')) {
      return const Icon(Icons.arrow_back, color: Colors.green);
    } else if (action.contains('STOP')) {
      return const Icon(Icons.stop, color: Colors.red);
    }
    return const Icon(Icons.info, color: Colors.grey);
  }

  String _formatPumpAction(String action) {
    return action
        .replaceAll('_', ' ')
        .replaceAll('MANUAL', 'Manual')
        .replaceAll('AUTO', 'Auto');
  }

  Color _getActionColor(String action) {
    if (action.contains('A_TO_B')) return Colors.blue;
    if (action.contains('B_TO_A')) return Colors.green;
    if (action.contains('STOP')) return Colors.red;
    return Colors.grey;
  }
}