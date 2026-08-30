import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    if (_isLoading) return;
    _otpSent ? _verifyOtp() : _sendOtp();
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
    final busy = _isLoading;

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
