import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/api_client.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import 'profile_setup_screen.dart';
import '../../dashboard/dashboard.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _otpCtrl   = TextEditingController();
  final _authService = AuthApiService();

  bool _otpSent      = false;
  bool _isLoading    = false;
  String? _socialLoading;

  static const _accent = Color(0xFF9B30FF);

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── Phone auth ───────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 10) {
      _snack('Enter a valid 10-digit phone number');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final otp = await _authService.requestOtp(phone: phone, countryCode: '+91');
      if (!mounted) return;
      setState(() {
        _otpSent   = true;
        _isLoading = false;
        if (otp != null) _otpCtrl.text = otp;
      });
      _snack('OTP sent successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack(humanizeError(e));
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _snack('Enter the 6-digit OTP from your SMS');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await _authService.verifyOtp(
        phone: _phoneCtrl.text.trim(),
        countryCode: '+91',
        otp: otp,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (!result.isNewUser) {
        // Returning user — mark complete locally and go straight to Dashboard.
        final uid = await ApiClient().userId;
        if (uid != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('setup_complete_$uid', true);
        }
        _navigateTo(const Dashboard());
      } else {
        // Brand-new user — send through onboarding.
        final isComplete =
            result.user['isProfileComplete'] as bool? ?? false;
        _navigateTo(
            isComplete ? const Dashboard() : const ProfileSetupScreen());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack(humanizeError(e));
    }
  }

  void _onMainButton() {
    if (_isLoading || _socialLoading != null) return;
    _otpSent ? _verifyOtp() : _sendOtp();
  }

  // ── Google auth ──────────────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    if (_socialLoading != null || _isLoading) return;
    setState(() => _socialLoading = 'google');
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) { setState(() => _socialLoading = null); return; }
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) throw Exception('No ID token');
      final result = await _authService.signInWithGoogle(idToken);
      if (!mounted) return;
      _navigateAfterSocial(result.isNewUser, result.user);
    } catch (_) {
      if (mounted) {
        setState(() => _socialLoading = null);
        _snack('Google sign-in failed. Please try again.');
      }
    }
  }

  void _navigateAfterSocial(bool isNewUser, Map<String, dynamic> user) {
    final isComplete = user['isProfileComplete'] as bool? ?? !isNewUser;
    _navigateTo(isComplete ? const Dashboard() : const ProfileSetupScreen());
  }

  void _navigateTo(Widget screen) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final busy = _isLoading || _socialLoading != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Image.asset(
            'assets/images/sign in/bg.png',
            fit: BoxFit.cover,
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: size.height - MediaQuery.of(context).padding.top,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: size.height * 0.07),

                    // ── Title ──────────────────────────────────────────────────
                    // Left-aligned to match the rest of the onboarding flow
                    // (Rules/Trust Setup/Permissions) instead of this
                    // screen's old one-off centered block.
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SIGN IN', style: AppTextStyles.compactTitle),
                        const SizedBox(height: 8),
                        Container(
                          width: 40,
                          height: 2,
                          decoration: BoxDecoration(
                            color: _accent,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: size.height * 0.06),

                    // ── Phone field ────────────────────────────────────────────
                    const Text(
                      'Phone no.',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SignInField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── OTP field ──────────────────────────────────────────────
                    const Text(
                      'OTP',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SignInField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      focused: _otpSent,
                    ),

                    const SizedBox(height: 32),

                    // ── Main button ────────────────────────────────────────────
                    GestureDetector(
                      onTap: busy ? null : _onMainButton,
                      child: Container(
                        width: double.infinity,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1D0A4E),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _accent.withValues(alpha: 0.55),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : Text(
                                  _otpSent ? 'Get Started' : 'Get OTP',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    SizedBox(height: size.height * 0.055),

                    // ── Sign in with divider ───────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: _accent.withValues(alpha: 0.55),
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Text(
                            'Sign in with',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: _accent.withValues(alpha: 0.55),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    // ── Social buttons ─────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _SocialImageButton(
                          asset: 'assets/images/sign in/Asset 69.png',
                          onTap: busy
                              ? null
                              : () => _snack('Facebook sign-in coming soon'),
                        ),
                        const SizedBox(width: 20),
                        _SocialImageButton(
                          asset: 'assets/images/sign in/Asset 70.png',
                          onTap: busy
                              ? null
                              : () => _snack('Twitter sign-in coming soon'),
                        ),
                        const SizedBox(width: 20),
                        _SocialImageButton(
                          asset: 'assets/images/sign in/Asset 71.png',
                          loading: _socialLoading == 'google',
                          onTap: busy ? null : _signInWithGoogle,
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),
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

// ── Input field ────────────────────────────────────────────────────────────────

class _SignInField extends StatelessWidget {
  final TextEditingController controller;
  final TextInputType keyboardType;
  final bool focused;
  final List<TextInputFormatter>? inputFormatters;

  const _SignInField({
    required this.controller,
    this.keyboardType = TextInputType.text,
    this.focused = false,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF9B30FF);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: focused
              ? accent.withValues(alpha: 0.85)
              : accent.withValues(alpha: 0.40),
          width: focused ? 1.5 : 1.0,
        ),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.18),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: accent,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

// ── Social icon button ─────────────────────────────────────────────────────────

class _SocialImageButton extends StatelessWidget {
  final String asset;
  final VoidCallback? onTap;
  final bool loading;

  const _SocialImageButton({
    required this.asset,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        height: 62,
        child: loading
            ? Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF3D0080),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.2,
                    ),
                  ),
                ),
              )
            : Image.asset(asset),
      ),
    );
  }
}
