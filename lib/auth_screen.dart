import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// HACK: We are storing users in a Firestore collection called 'users' with their email and uid.
// This is a workaround because the Firebase Auth SDK does not provide a direct way to look up users by email.
// WARNING: This approach is insecure as it exposes sensitive operations to the client-side,
// making it vulnerable to malicious actors. It violates best practices for handling sensitive data.
// RECOMMENDATION: Use Firebase Cloud Functions to securely perform server-side operations,
// such as looking up users by email, and ensure proper authentication and authorization checks.
Future<void> saveUserToFirestore(User user) async {
  if (user.email == null)
    return; // Defensive: email-less users shouldn't exist here
  await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
    'email': user.email,
    'uid': user.uid,
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
      final user = FirebaseAuth.instance.currentUser!;
      await saveUserToFirestore(user);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<void> _signUpWithEmail() async {
    setState(() => _error = null);
    try {
      await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final user = FirebaseAuth.instance.currentUser!;
      await saveUserToFirestore(user);
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
      await _auth.signInWithCredential(credential);
      await saveUserToFirestore(FirebaseAuth.instance.currentUser!);
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
      await _auth.signInWithCredential(oauthCredential);
      await saveUserToFirestore(FirebaseAuth.instance.currentUser!);
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
            ElevatedButton(
              onPressed: _signUpWithEmail,
              child: Text('Sign up with Email'),
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }
}
