import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChildrenListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final childrenStream = FirebaseFirestore.instance
        .collection('children')
        .where('parentUids', arrayContains: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text('Your Children'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: childrenStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(child: Text('No children yet. Tap + to add.'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final child = docs[index];
              return ListTile(
                title: Text(child['name']),
                // You can add more actions here, like view details or share child.
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await showDialog(
            context: context,
            builder: (_) => AddChildDialog(),
          );
          if (added == true) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Child added!')));
          }
        },
        child: Icon(Icons.add),
        tooltip: 'Add Child',
      ),
    );
  }
}

class AddChildDialog extends StatefulWidget {
  @override
  State<AddChildDialog> createState() => _AddChildDialogState();
}

class _AddChildDialogState extends State<AddChildDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Child'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          decoration: InputDecoration(labelText: 'Child Name'),
          validator: (val) =>
              val == null || val.trim().isEmpty ? 'Enter a name' : null,
        ),
      ),
      actions: [
        if (_loading)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(_error!, style: TextStyle(color: Colors.red)),
          ),
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
                    final user = FirebaseAuth.instance.currentUser!;
                    await FirebaseFirestore.instance.collection('children').add(
                      {
                        'name': _nameController.text.trim(),
                        'parentUids': [user.uid],
                        'createdAt': FieldValue.serverTimestamp(),
                      },
                    );
                    Navigator.of(context).pop(true);
                  } catch (e) {
                    setState(() {
                      _loading = false;
                      _error = 'Failed to add child: $e';
                    });
                  }
                },
          child: Text('Add'),
        ),
      ],
    );
  }
}
