import 'package:flutter/material.dart';
import '../../../core/services/auth_api_service.dart';
import 'profile_setup_screen.dart';
import '../../dashboard/dashboard.dart';

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _countryCodeCtrl = TextEditingController(text: '+91');
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  final _authService = AuthApiService();

  bool _otpSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _countryCodeCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _phone => _phoneCtrl.text.trim();
  String get _countryCode => _countryCodeCtrl.text.trim();

  Future<void> _sendOtp() async {
    if (_phone.isEmpty || _phone.length < 7) {
      _showSnack('Enter a valid phone number');
      return;
    }
    if (!_countryCode.startsWith('+')) {
      _showSnack('Country code must start with + (e.g. +91)');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final otp = await _authService.requestOtp(phone: _phone, countryCode: _countryCode);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _isLoading = false;
        if (otp != null) _otpCtrl.text = otp;
      });
      _showSnack('OTP sent successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(e.toString());
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _showSnack('Enter the 6-digit OTP from your SMS');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _authService.verifyOtp(
        phone: _phone,
        countryCode: _countryCode,
        otp: otp,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (result.isNewUser || !(result.user['isProfileComplete'] as bool? ?? false)) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => Dashboard()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack(e.toString());
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _input(String hint) => InputDecoration(
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
                  Colors.black.withValues(alpha: 0.20),
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.65),
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
                    const Text(
                      'Continue with Phone',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Country code + phone number row
                    Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: TextField(
                            controller: _countryCodeCtrl,
                            keyboardType: TextInputType.phone,
                            textAlign: TextAlign.center,
                            decoration: _input('+91'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: _input('Phone number'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    if (_otpSent)
                      TextField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _input('Enter 6-digit OTP'),
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
                          onPressed: _isLoading ? null : (_otpSent ? _verifyOtp : _sendOtp),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.4,
                                  ),
                                )
                              : Text(
                                  _otpSent ? 'Verify OTP' : 'Send OTP',
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

                    if (_otpSent)
                      TextButton(
                        onPressed: _isLoading ? null : () => setState(() => _otpSent = false),
                        child: const Text(
                          'Change number',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),

                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Back',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
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
