import 'package:flutter/material.dart';

Future<String?> promptForFirstName(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Enter your first name'),
      content: TextField(
        controller: controller,
        decoration: InputDecoration(labelText: 'First Name'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) {
              Navigator.of(context).pop(text);
            }
          },
          child: Text('OK'),
        ),
      ],
    ),
  );
}
