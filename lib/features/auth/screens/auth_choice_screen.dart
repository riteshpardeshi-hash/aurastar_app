import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'login_screen.dart';
import 'phone_auth_screen.dart';
import 'profile_setup_screen.dart';
import '../../dashboard/dashboard.dart';

class AuthChoiceScreen extends StatefulWidget {
  const AuthChoiceScreen({super.key});

  @override
  State<AuthChoiceScreen> createState() => _AuthChoiceScreenState();
}

class _AuthChoiceScreenState extends State<AuthChoiceScreen> {
  String? _loading; // 'google' | 'apple' — null means idle

  static const _privacyKey = 'privacy_v1_accepted';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPrivacy());
  }

  Future<void> _checkPrivacy() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_privacyKey) == true) return;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PrivacySheet(
        onAccept: () async {
          await prefs.setBool(_privacyKey, true);
          if (mounted) Navigator.pop(context);
        },
      ),
    );
  }

  // ── Shared: post-credential navigation ──────────────────────────────────────

  Future<void> _handleCredential(UserCredential userCred) async {
    final user = userCred.user;
    if (user == null) {
      if (mounted) setState(() => _loading = null);
      return;
    }

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!mounted) return;
    setState(() => _loading = null);

    if (!doc.exists) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Dashboard()),
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Google ───────────────────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    if (_loading != null) return;
    setState(() => _loading = 'google');
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _loading = null);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await _handleCredential(userCred);
    } catch (_) {
      if (mounted) setState(() => _loading = null);
      _showError('Google sign-in failed. Please try again.');
    }
  }

  // ── Apple ────────────────────────────────────────────────────────────────────

  Future<void> _signInWithApple() async {
    if (_loading != null) return;
    setState(() => _loading = 'apple');
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oAuthProvider = OAuthProvider('apple.com');
      final credential = oAuthProvider.credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final userCred =
          await FirebaseAuth.instance.signInWithCredential(credential);
      await _handleCredential(userCred);
    } catch (_) {
      if (mounted) setState(() => _loading = null);
      _showError('Apple sign-in failed. Please try again.');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool showApple = Platform.isIOS || Platform.isMacOS;

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
                  Colors.black.withValues(alpha: 0.20),
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Image.asset(
                    'assets/images/Aura arena.png',
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    'Choose how you want to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Email ───────────────────────────────────────────────────
                  _PrimaryButton(
                    label: 'Continue with Email',
                    onTap: _loading != null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen()),
                            ),
                  ),
                  const SizedBox(height: 14),

                  // ── Phone ───────────────────────────────────────────────────
                  _OutlineButton(
                    label: 'Continue with Phone',
                    onTap: _loading != null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const PhoneAuthScreen()),
                            ),
                  ),
                  const SizedBox(height: 14),

                  // ── Divider ─────────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.25),
                              thickness: 0.8)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'or',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 13),
                        ),
                      ),
                      Expanded(
                          child: Divider(
                              color: Colors.white.withValues(alpha: 0.25),
                              thickness: 0.8)),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ── Google ──────────────────────────────────────────────────
                  _SocialButton(
                    onTap: _loading == null ? _signInWithGoogle : null,
                    loading: _loading == 'google',
                    icon: const _GoogleIcon(),
                    label: 'Continue with Google',
                    backgroundColor: Colors.white,
                    textColor: const Color(0xFF1A1A1A),
                  ),

                  // ── Apple (iOS / macOS only) ────────────────────────────────
                  if (showApple) ...[
                    const SizedBox(height: 12),
                    _SocialButton(
                      onTap: _loading == null ? _signInWithApple : null,
                      loading: _loading == 'apple',
                      icon: const Icon(Icons.apple,
                          color: Colors.white, size: 20),
                      label: 'Continue with Apple',
                      backgroundColor: Colors.black,
                      textColor: Colors.white,
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable button widgets ────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
          onPressed: onTap,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.deepPurple,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool loading;
  final Widget icon;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _SocialButton({
    required this.onTap,
    required this.loading,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        onPressed: onTap,
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: textColor,
                  strokeWidth: 2.2,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Google coloured "G" icon ──────────────────────────────────────────────────

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw the four quadrant arcs in Google's brand colors
    final segments = [
      (startAngle: -1.5708, sweepAngle: 1.5708, color: const Color(0xFF4285F4)), // blue top-right
      (startAngle: 0.0, sweepAngle: 1.5708, color: const Color(0xFF34A853)), // green bottom-right
      (startAngle: 1.5708, sweepAngle: 1.5708, color: const Color(0xFFFBBC05)), // yellow bottom-left
      (startAngle: 3.1416, sweepAngle: 1.5708, color: const Color(0xFFEA4335)), // red top-left
    ];

    for (final s in segments) {
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.22
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - size.width * 0.11),
        s.startAngle,
        s.sweepAngle,
        false,
        paint,
      );
    }

    // White notch for the crossbar cutout (top-right quadrant)
    final notchPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - size.width * 0.11),
      -0.52,
      0.52,
      false,
      notchPaint,
    );

    // Horizontal bar of the G (right side)
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.50, center.dy),
      Offset(size.width * 0.92, center.dy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Privacy notice bottom sheet ───────────────────────────────────────────────

class _PrivacySheet extends StatelessWidget {
  final VoidCallback onAccept;
  const _PrivacySheet({required this.onAccept});

  static const _bg = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  static const _points = [
    (Icons.videocam_outlined, 'Video submissions', 'Videos you record are stored to enable AI scoring and the public leaderboard.'),
    (Icons.bar_chart_rounded, 'Performance data', 'Your scores, Aura Points, and activity are used to power rankings and personalised challenges.'),
    (Icons.person_outline_rounded, 'Profile information', 'Your display name and avatar are visible to other users on the platform.'),
    (Icons.notifications_none_rounded, 'Push notifications', 'We may send score results and challenge alerts — you can opt out at any time in Settings.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Icon + heading
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: _accent.withValues(alpha: 0.35)),
            ),
            child: const Icon(Icons.shield_outlined, color: _accent, size: 28),
          ),
          const SizedBox(height: 16),
          const Text(
            'Privacy & Data Notice',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Before you join, here\'s what Aura Arena collects and why.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Data points
          ..._points.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(p.$1, color: _accent, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.$2,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(p.$3,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.50),
                                fontSize: 12,
                                height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Policy link
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.40), fontSize: 12),
              children: [
                const TextSpan(text: 'By continuing you agree to our '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: const TextStyle(
                      color: _accent,
                      decoration: TextDecoration.underline,
                      decorationColor: _accent),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      // Deep-link or in-app WebView would go here.
                      // For now, acknowledge with a snack.
                    },
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Terms of Service',
                  style: const TextStyle(
                      color: _accent,
                      decoration: TextDecoration.underline,
                      decorationColor: _accent),
                  recognizer: TapGestureRecognizer()..onTap = () {},
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Accept button
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              onPressed: onAccept,
              child: const Text(
                'Accept & Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
