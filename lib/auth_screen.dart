import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/signup_screen.dart';
import 'widgets/prompt_first_name.dart';

// HACK: We are storing users in a Firestore collection called 'users' with their email and uid.
// This is a workaround because the Firebase Auth SDK does not provide a direct way to look up users by email.
// WARNING: This approach is insecure as it exposes sensitive operations to the client-side,
// making it vulnerable to malicious actors. It violates best practices for handling sensitive data.
// RECOMMENDATION: Use Firebase Cloud Functions to securely perform server-side operations,
// such as looking up users by email, and ensure proper authentication and authorization checks.
Future<void> saveUserToFirestore(User user, String firstName) async {
  if (user.email == null)
    return; // Defensive: email-less users shouldn't exist here
  await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
    'email': user.email,
    'uid': user.uid,
    'firstName': firstName,
    // Add more profile fields as needed
  }, SetOptions(merge: true));
}

class AuthScreen extends StatefulWidget {
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _error;

  Future<void> _signInWithEmail() async {
    setState(() => _error = null);
    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _error = null);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return;

      // Try to get first name
      String? firstName;
      final displayName = user.displayName ?? googleUser.displayName;
      if (displayName != null && displayName.isNotEmpty) {
        firstName = displayName.split(' ').first;
      }

      // Check if Firestore user doc exists/has firstName
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists &&
          (userDoc.data()?['firstName'] as String?)?.isNotEmpty == true) {
        // Already have a name, nothing else to do
        return;
      }

      firstName = firstName ?? await promptForFirstName(context);
      if (firstName == null || firstName.isEmpty) {
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'firstName': firstName,
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _error = null);
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final user = userCredential.user;
      if (user == null) return;

      // Apple provides name only on first sign-in
      String? firstName = appleCredential.givenName;
      if (firstName == null || firstName.isEmpty) {
        // Try to get from Firestore, else prompt
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        firstName =
            userDoc.data()?['firstName'] ?? await promptForFirstName(context);
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'firstName': firstName,
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign In')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            ElevatedButton(
              onPressed: _signInWithEmail,
              child: Text('Sign in with Email'),
            ),
            ElevatedButton(
              onPressed: _signInWithGoogle,
              child: Text('Sign in with Google'),
            ),
            if (Theme.of(context).platform == TargetPlatform.iOS)
              ElevatedButton(
                onPressed: _signInWithApple,
                child: Text('Sign in with Apple'),
              ),
            TextButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (context) => SignUpScreen()));
              },
              child: Text('Don\'t have an account? Sign Up'),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
