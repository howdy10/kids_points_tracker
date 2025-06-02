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
                trailing: IconButton(
                  icon: Icon(Icons.share),
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => ShareChildDialog(childId: child.id),
                    );
                  },
                ),
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

class ShareChildDialog extends StatefulWidget {
  final String childId;
  const ShareChildDialog({required this.childId});
  @override
  State<ShareChildDialog> createState() => _ShareChildDialogState();
}

class _ShareChildDialogState extends State<ShareChildDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _loading = false;
  String? _error, _success;

  // HACK: We are storing users in a Firestore collection called 'users' with their email and uid.
  // This is a workaround because the Firebase Auth SDK does not provide a direct way to look up users by email.
  // WARNING: This approach is insecure as it exposes sensitive operations to the client-side,
  // making it vulnerable to malicious actors. It violates best practices for handling sensitive data.
  // RECOMMENDATION: Use Firebase Cloud Functions to securely perform server-side operations,
  // such as looking up users by email, and ensure proper authentication and authorization checks.
  Future<void> _shareChild() async {
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    final email = _emailController.text.trim();
    try {
      // Look up user by email in Firestore
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (userQuery.docs.isEmpty) {
        setState(() {
          _error = 'No user found with that email.';
          _loading = false;
        });
        return;
      }
      final shareUid = userQuery.docs.first['uid'];

      // Update child's parentUids array
      final childRef = FirebaseFirestore.instance
          .collection('children')
          .doc(widget.childId);
      await childRef.update({
        'parentUids': FieldValue.arrayUnion([shareUid]),
      });

      setState(() {
        _success = 'Child shared successfully!';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Share Child with Another Parent'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _emailController,
          decoration: InputDecoration(labelText: 'Parent\'s Email'),
          validator: (val) =>
              val == null || val.trim().isEmpty ? 'Enter an email' : null,
        ),
      ),
      actions: [
        if (_loading) CircularProgressIndicator(),
        if (_error != null) Text(_error!, style: TextStyle(color: Colors.red)),
        if (_success != null)
          Text(_success!, style: TextStyle(color: Colors.green)),
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _loading
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  await _shareChild();
                  if (_success != null) {
                    Navigator.of(context).pop(true);
                  }
                },
          child: Text('Share'),
        ),
      ],
    );
  }
}
