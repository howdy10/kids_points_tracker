import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'points_history_paginated.dart';

Future<Map<String, String>> fetchFirstNames(Set<String> uids) async {
  if (uids.isEmpty) return {};
  final List<String> uidList = uids.toList();
  List<DocumentSnapshot> userDocs = [];
  // Firestore whereIn only allows 10 items at a time
  for (var i = 0; i < uidList.length; i += 10) {
    final chunk = uidList.sublist(
      i,
      i + 10 > uidList.length ? uidList.length : i + 10,
    );
    final usersQuery = await FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: chunk)
        .get();
    userDocs.addAll(usersQuery.docs);
  }
  return {for (var doc in userDocs) doc.id: doc['firstName'] ?? 'Unknown'};
}

class ChildDetailScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const ChildDetailScreen({
    Key? key,
    required this.childId,
    required this.childName,
  }) : super(key: key);

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen>
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
    final logsRef = FirebaseFirestore.instance
        .collection('children')
        .doc(widget.childId)
        .collection('pointsLogs');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.childName),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "Today"),
            Tab(text: "History"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Today tab as before (existing code)
          TodayPointsView(childId: widget.childId),
          // New History tab:
          PointsHistoryPaginatedView(childId: widget.childId),
        ],
      ),
    );
  }
}

class AddRemovePointsDialog extends StatefulWidget {
  final String childId;

  const AddRemovePointsDialog({Key? key, required this.childId})
    : super(key: key);

  @override
  State<AddRemovePointsDialog> createState() => _AddRemovePointsDialogState();
}

class _AddRemovePointsDialogState extends State<AddRemovePointsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pointsController = TextEditingController();
  final _reasonController = TextEditingController();
  String _action = 'add';
  bool _loading = false;
  String? _error;
  final List<bool> _selected = [true, false];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add/Remove Points'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoSegmentedControl<String>(
              children: const <String, Widget>{
                'add': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18.0),
                  child: Text('Add +'),
                ),
                'remove': Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18.0),
                  child: Text('Remove -'),
                ),
              },
              groupValue: _action,
              onValueChanged: (String value) {
                setState(() {
                  _action = value;
                });
              },
            ),
            SizedBox(height: 18),
            TextFormField(
              controller: _pointsController,
              decoration: InputDecoration(labelText: 'Points'),
              keyboardType: TextInputType.number,
              validator: (val) {
                if (val == null || val.isEmpty) return 'Enter points';
                final n = int.tryParse(val);
                if (n == null || n <= 0) return 'Enter a positive number';
                return null;
              },
            ),
            TextFormField(
              controller: _reasonController,
              decoration: InputDecoration(labelText: 'Reason'),
              validator: (val) =>
                  val == null || val.isEmpty ? 'Enter a reason' : null,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(_error!, style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
      actions: [
        if (_loading) CircularProgressIndicator(),
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  try {
                    final points = int.parse(_pointsController.text);
                    final reason = _reasonController.text.trim();
                    final user = FirebaseAuth.instance.currentUser!;
                    await FirebaseFirestore.instance
                        .collection('children')
                        .doc(widget.childId)
                        .collection('pointsLogs')
                        .add({
                          'action': _action,
                          'points': points,
                          'reason': reason,
                          'timestamp': FieldValue.serverTimestamp(),
                          'byUid': user.uid,
                        });
                    Navigator.of(context).pop();
                  } catch (e) {
                    setState(() {
                      _error = 'Failed: $e';
                      _loading = false;
                    });
                  }
                },
          child: Text('Submit'),
        ),
      ],
    );
  }
}

class TodayPointsView extends StatelessWidget {
  final String childId;
  const TodayPointsView({required this.childId, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final logsRef = FirebaseFirestore.instance
        .collection('children')
        .doc(childId)
        .collection('pointsLogs');

    // Today’s date range
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(Duration(days: 1));

    final todayLogsQuery = logsRef
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
        )
        .where('timestamp', isLessThan: Timestamp.fromDate(todayEnd))
        .orderBy('timestamp', descending: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Today’s points
        StreamBuilder<QuerySnapshot>(
          stream: todayLogsQuery.snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return LinearProgressIndicator();
            final logs = snapshot.data!.docs;
            int totalPoints = 0;
            for (final doc in logs) {
              final action = doc['action'];
              final points = doc['points'] as int;
              if (action == 'add') {
                totalPoints += points;
              } else if (action == 'remove') {
                totalPoints -= points;
              }
            }
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    "Today's Points",
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '$totalPoints',
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: Icon(Icons.add),
                    label: Text('Add/Remove Points'),
                    onPressed: () => showDialog(
                      context: context,
                      builder: (context) =>
                          AddRemovePointsDialog(childId: childId),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Divider(),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text('Recent Activity'),
        ),
        // Activity Log (recent actions)
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: logsRef
                .orderBy('timestamp', descending: true)
                .limit(20)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }
              final logs = snapshot.data!.docs;
              if (logs.isEmpty) return Center(child: Text('No activity yet.'));

              // Collect UIDs from logs
              final byUids = logs.map((log) => log['byUid'] as String).toSet();

              // Fetch names
              return FutureBuilder<Map<String, String>>(
                future: fetchFirstNames(byUids),
                builder: (context, namesSnap) {
                  if (!namesSnap.hasData) {
                    return Center(child: CircularProgressIndicator());
                  }

                  final uidToName = namesSnap.data!;

                  return ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final action = log['action'] as String;
                      final points = log['points'] as int;
                      final reason = log['reason'] as String;
                      final timestamp = (log['timestamp'] as Timestamp)
                          .toDate();
                      final givenByUid = log['byUid'];
                      final firstName = uidToName[givenByUid] ?? 'Unknown';

                      return ListTile(
                        leading: Icon(
                          action == 'add' ? Icons.add : Icons.remove,
                          color: action == 'add' ? Colors.green : Colors.red,
                        ),
                        title: Text('${action == 'add' ? '+' : '-'}$points'),
                        subtitle: Text('$reason • by $firstName'),
                        trailing: Text(
                          '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class PointsHistoryView extends StatelessWidget {
  final String childId;
  const PointsHistoryView({required this.childId, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final logsRef = FirebaseFirestore.instance
        .collection('children')
        .doc(childId)
        .collection('pointsLogs')
        .orderBy('timestamp', descending: true);

    return StreamBuilder<QuerySnapshot>(
      stream: logsRef.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;

        // Group by date
        final Map<String, List<QueryDocumentSnapshot>> grouped = {};
        for (final doc in docs) {
          final timestamp = (doc['timestamp'] as Timestamp?)?.toDate();
          if (timestamp == null) continue;
          final dayStr = DateFormat('yyyy-MM-dd').format(timestamp);
          grouped.putIfAbsent(dayStr, () => []).add(doc);
        }

        final sortedDates = grouped.keys.toList()
          ..sort((a, b) => b.compareTo(a));
        if (sortedDates.isEmpty) return Center(child: Text("No history yet."));

        return ListView.builder(
          itemCount: sortedDates.length,
          itemBuilder: (context, index) {
            final day = sortedDates[index];
            final logs = grouped[day]!;
            int total = 0;
            for (final log in logs) {
              if (log['action'] == 'add') {
                total += log['points'] as int;
              } else if (log['action'] == 'remove') {
                total -= log['points'] as int;
              }
            }
            // Optionally, show expandable detail:
            return ExpansionTile(
              title: Text(
                DateFormat('MMM d, yyyy').format(DateTime.parse(day)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text("Net points: $total"),
              children: logs.map((log) {
                final action = log['action'] as String;
                final points = log['points'] as int;
                final reason = log['reason'] as String;
                final timestamp = (log['timestamp'] as Timestamp).toDate();
                final timeStr = DateFormat('h:mm a').format(timestamp);
                return ListTile(
                  leading: Icon(
                    action == 'add' ? Icons.add : Icons.remove,
                    color: action == 'add' ? Colors.green : Colors.red,
                  ),
                  title: Text('${action == 'add' ? '+' : '-'}$points'),
                  subtitle: Text('$reason ($timeStr)'),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}
