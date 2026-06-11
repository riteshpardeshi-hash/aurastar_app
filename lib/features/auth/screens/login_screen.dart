import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_setup_screen.dart';
import '../../dashboard/dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLogin = true;
  bool isLoading = false;

  Future<void> handleAuth() async {
    try {
      setState(() => isLoading = true);

      UserCredential userCred;

      if (isLogin) {
        userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } else {
        userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      }

      final user = userCred.user;
      if (user == null) {
        if (mounted) setState(() => isLoading = false);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      setState(() => isLoading = false);

      if (!doc.exists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => Dashboard()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      String message = 'Something went wrong. Please try again.';
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
          case 'wrong-password':
          case 'invalid-credential':
          case 'invalid-email':
            message = 'Invalid email or password.';
          case 'email-already-in-use':
            message = 'Sign up failed. Please try again.';
          case 'too-many-requests':
            message = 'Too many attempts. Please try again later.';
          case 'network-request-failed':
            message = 'Network error. Please check your connection.';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  InputDecoration input(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black54, fontSize: 16),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.white, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/power-music-concept-portrait (2).jpg',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextField(
                      controller: emailController,
                      decoration: input("Email/Username"),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: input("Password"),
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B2CBF),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7B2CBF).withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: isLoading ? null : handleAuth,
                          child: isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Text(
                                  isLogin ? "Login" : "Sign Up",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () => setState(() => isLogin = !isLogin),
                      child: Text(
                        isLogin
                            ? "Don't have an account? Sign Up"
                            : "Already have an account? Login",
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Image.asset(
                      'assets/images/Aura arena.png',
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
