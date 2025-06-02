import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_config.dart'; // Assuming you have an AppConfig class for constants

class PointsHistoryPaginatedView extends StatefulWidget {
  final String childId;
  const PointsHistoryPaginatedView({required this.childId, Key? key})
    : super(key: key);

  @override
  State<PointsHistoryPaginatedView> createState() =>
      _PointsHistoryPaginatedViewState();
}

class _PointsHistoryPaginatedViewState
    extends State<PointsHistoryPaginatedView> {
  static const int pageSize =
      AppConfig.pointsHistoryPageSize; // You can adjust this
  final List<QueryDocumentSnapshot> _allLogs = [];
  DocumentSnapshot? _lastDoc;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchNextPage();
  }

  Future<void> _fetchNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = FirebaseFirestore.instance
          .collection('children')
          .doc(widget.childId)
          .collection('pointsLogs')
          .orderBy('timestamp', descending: true)
          .limit(pageSize);

      final snap = _lastDoc == null
          ? await query.get()
          : await query.startAfterDocument(_lastDoc!).get();

      if (snap.docs.length < pageSize) _hasMore = false;
      if (snap.docs.isNotEmpty) {
        _lastDoc = snap.docs.last;
        _allLogs.addAll(snap.docs);
      }
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group logs by date (yyyy-MM-dd)
    final Map<String, List<QueryDocumentSnapshot>> grouped = {};
    for (final doc in _allLogs) {
      final timestamp = (doc['timestamp'] as Timestamp?)?.toDate();
      if (timestamp == null) continue;
      final dayStr = DateFormat('yyyy-MM-dd').format(timestamp);
      grouped.putIfAbsent(dayStr, () => []).add(doc);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text('Error: $_error', style: TextStyle(color: Colors.red)),
          ),
        if (sortedDates.isEmpty && !_loading)
          Expanded(child: Center(child: Text("No history yet."))),
        if (sortedDates.isNotEmpty)
          Expanded(
            child: ListView.builder(
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
            ),
          ),
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: CircularProgressIndicator(),
          ),
        if (_hasMore && !_loading)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: ElevatedButton(
              onPressed: _fetchNextPage,
              child: Text("Load More"),
            ),
          ),
      ],
    );
  }
}
