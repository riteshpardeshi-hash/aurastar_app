import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/sms_otp_autofill.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/legal_consent_text.dart';
import '../../../shared/widgets/deletion_cancelled_dialog.dart';
import '../phone_auth_controller.dart';
import '../widgets/otp_code_input.dart';
import 'profile_setup_screen.dart';
import '../../shell/main_shell.dart';

/// Sign in / sign up with a mobile number, in two steps on one screen:
///
/// 1. **Mobile number** — the code can't be typed yet, only requested.
/// 2. **Verify** — six code boxes, auto-filled from the SMS on Android and by
///    the keyboard on iOS, auto-submitted when complete.
///
/// The logic (validation, cooldowns, every error case) lives in
/// [PhoneAuthController]; this widget renders it.
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key, this.smsAutofill});

  /// Injectable for tests. Production uses the real [SmsOtpAutofill].
  final SmsOtpAutofill? smsAutofill;

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> with SingleTickerProviderStateMixin {
  static const _accent = Color(0xFF9B30FF);
  static const _accent2 = Color(0xFFE040FB);
  static const _sheet = Color(0xFF0F0A1E);
  static const _error = Color(0xFFFF5C7A);

  final _authService = AuthApiService();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _phoneFocus = FocusNode();
  final _otpFocus = FocusNode();

  late final SmsOtpAutofill _smsAutofill = widget.smsAutofill ?? SmsOtpAutofill();
  late final PhoneAuthController _auth = PhoneAuthController(
    requestOtp: (phone) => _authService.requestOtp(phone: phone, countryCode: '+91'),
    verifyOtp: (phone, otp) => _authService.verifyOtp(phone: phone, countryCode: '+91', otp: otp),
  );

  // One entrance spin, then the orb rests: an endless animation would keep
  // every screen test that lands here (e.g. after logout) from settling.
  late final AnimationController _orb = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );
  late final Animation<double> _orbTurn = CurvedAnimation(parent: _orb, curve: Curves.easeOutCubic);

  PhoneAuthStep _lastStep = PhoneAuthStep.phone;
  int _lastCodeReset = 0;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "reduce motion" setting.
    if (MediaQuery.of(context).disableAnimations) {
      _orb.value = 1;
    } else if (!_orb.isAnimating && _orb.value == 0) {
      _orb.forward();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _auth.dispose();
    _smsAutofill.cancel();
    _orb.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _phoneFocus.dispose();
    _otpFocus.dispose();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (_auth.codeResetCount != _lastCodeReset) {
      _lastCodeReset = _auth.codeResetCount;
      _otpCtrl.clear();
    }
    if (_auth.step != _lastStep) {
      _lastStep = _auth.step;
      if (_auth.step == PhoneAuthStep.otp) {
        _listenForSmsCode();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _otpFocus.requestFocus();
        });
      } else {
        _smsAutofill.cancel();
      }
    }
    setState(() {});
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    await _auth.sendOtp();
  }

  Future<void> _resend() async {
    await _auth.resend();
    if (_auth.otpError == null) _listenForSmsCode();
  }

  /// Waits for the OTP SMS and, on a clean 6-digit read, fills the boxes and
  /// submits — the user never types anything.
  Future<void> _listenForSmsCode() async {
    _smsAutofill.cancel();
    final code = await _smsAutofill.waitForCode();
    if (!mounted || _auth.step != PhoneAuthStep.otp || code == null || code.length != 6) return;
    _otpCtrl.text = code;
    _verify(code);
  }

  Future<void> _verify(String code) async {
    final result = await _auth.verify(code);
    if (result == null || !mounted) return;
    _smsAutofill.cancel();
    result.isNewUser ? AnalyticsService().logSignUp('phone') : AnalyticsService().logLogin('phone');

    if (result.deletionCancelled) {
      await showDeletionCancelledDialog(context);
      if (!mounted) return;
    }

    // Trust the server's isProfileComplete for new and returning users alike:
    // a returning user who never finished onboarding must go back to it, or
    // every tab's requireProfileComplete-gated content fails to load. Landing
    // on MainShell (not a bare Dashboard) keeps the bottom-nav tabs wired to
    // MainShellController.
    final isComplete = result.user['isProfileComplete'] as bool? ?? false;
    if (isComplete) {
      final uid = await ApiClient().userId;
      if (uid != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('setup_complete_$uid', true);
      }
      _navigateTo(const MainShell());
    } else {
      _navigateTo(const ProfileSetupScreen());
    }
  }

  void _navigateTo(Widget screen) {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  void _editNumber() {
    _auth.editNumber();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _phoneFocus.requestFocus();
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final onOtp = _auth.step == PhoneAuthStep.otp;

    return PopScope(
      // System back on the code step returns to the number, not out of the app.
      canPop: !onOtp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && onOtp) _editNumber();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF07060F),
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/sign in/bg.png', fit: BoxFit.cover),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x3307060F), Color(0xCC07060F), Color(0xFF07060F)],
                  stops: [0, 0.55, 1],
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Expanded(child: _hero(compact: keyboardOpen)),
                  _sheetCard(media, onOtp),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero({required bool compact}) {
    return LayoutBuilder(builder: (context, box) {
      final orbSize = math.min(box.maxHeight * (compact ? 0.62 : 0.56), 230.0).clamp(0.0, 230.0);
      return Center(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (orbSize > 60)
                SizedBox(
                  width: orbSize,
                  height: orbSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.85, end: 1).animate(_orbTurn),
                        child: RotationTransition(
                          turns: _orbTurn,
                          child: Image.asset('assets/images/Splash screen/Orb.png', fit: BoxFit.contain),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(orbSize * 0.24),
                        child: Image.asset('assets/images/Aura arena.png', fit: BoxFit.contain),
                      ),
                    ],
                  ),
                ),
              if (!compact) ...[
                const SizedBox(height: 14),
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Colors.white, Color(0xFFD9B8FF)])
                      .createShader(r),
                  child: const Text(
                    'See it. Copy it. Slay it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'ClashDisplay',
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Take on challenges, flex your aura, top the leaderboard.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }

  Widget _sheetCard(MediaQueryData media, bool onOtp) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: _accent.withValues(alpha: 0.35))),
        boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.18), blurRadius: 40, offset: const Offset(0, -6))],
      ),
      padding: EdgeInsets.fromLTRB(24, 22, 24, 20 + media.padding.bottom),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final forward = child.key == const ValueKey('otp-step');
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(begin: Offset(forward ? 0.12 : -0.12, 0), end: Offset.zero)
                    .animate(animation),
                child: child,
              ),
            );
          },
          child: onOtp ? _otpStep() : _phoneStep(),
        ),
      ),
    );
  }

  // ─── Step 1: mobile number ───────────────────────────────────────────────

  Widget _phoneStep() {
    final error = _auth.phoneError;
    return Column(
      key: const ValueKey('phone-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _dividerTitle('Log in or sign up'),
        const SizedBox(height: 18),
        _PhoneField(
          controller: _phoneCtrl,
          focusNode: _phoneFocus,
          hasError: error != null,
          enabled: !_auth.busy,
          onChanged: _auth.setPhone,
          onSubmitted: (_) => _sendOtp(),
        ),
        if (error != null) _errorLine(error, key: const Key('phone-error')),
        if (_auth.canEnterExistingCode)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('have-code'),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4)),
              onPressed: _auth.enterExistingCode,
              child: const Text('Already got a code? Enter it',
                  style: TextStyle(color: Color(0xFFD4A8FF), fontWeight: FontWeight.w700)),
            ),
          ),
        const SizedBox(height: 16),
        LegalConsentText(
          accent: _accent,
          checked: _auth.termsAccepted,
          onChanged: _auth.setTermsAccepted,
        ),
        if (_auth.termsError) _errorLine(PhoneAuthController.termsMessage, key: const Key('terms-error')),
        const SizedBox(height: 18),
        _GradientButton(
          key: const Key('get-otp'),
          label: 'Get OTP',
          busyLabel: 'Sending code…',
          busy: _auth.sending,
          dimmed: !_auth.phoneValid || !_auth.termsAccepted,
          onTap: _sendOtp,
        ),
      ],
    );
  }

  // ─── Step 2: verify ──────────────────────────────────────────────────────

  Widget _otpStep() {
    final error = _auth.otpError;
    final info = _auth.otpInfo;
    final complete = _otpCtrl.text.length == 6;
    return Column(
      key: const ValueKey('otp-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            InkResponse(
              key: const Key('otp-back'),
              onTap: _auth.verifying ? null : _editNumber,
              radius: 22,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Verify your number',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700, fontFamily: 'ClashDisplay'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            const Text('Enter the 6-digit code sent to', style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            Text(_auth.displayPhone,
                style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700)),
            GestureDetector(
              key: const Key('edit-number'),
              onTap: _auth.verifying ? null : _editNumber,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Edit',
                    style: TextStyle(color: Color(0xFFD4A8FF), fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
        if (info != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('otp-info'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accent.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                const Icon(Icons.sms_outlined, color: Color(0xFFD4A8FF), size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(info, style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.35))),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        OtpCodeInput(
          controller: _otpCtrl,
          focusNode: _otpFocus,
          enabled: !_auth.verifying,
          hasError: error != null,
          shakeTrigger: _auth.shakeCount,
          onChanged: (_) {
            _auth.clearOtpError();
            setState(() {});
          },
          onCompleted: _verify,
        ),
        if (error != null) _errorLine(error, key: const Key('otp-error')),
        const SizedBox(height: 14),
        _resendRow(),
        const SizedBox(height: 18),
        _GradientButton(
          key: const Key('verify'),
          label: 'Verify & continue',
          busyLabel: 'Verifying…',
          busy: _auth.verifying,
          dimmed: !complete,
          onTap: () => _verify(_otpCtrl.text),
        ),
        if (Platform.isAndroid) ...[
          const SizedBox(height: 10),
          const Text(
            'We\'ll fill in the code automatically when the SMS arrives.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textFaint, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  Widget _resendRow() {
    final secs = _auth.resendIn;
    final countdown = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    // Wraps instead of overflowing on narrow phones / large system fonts.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('Didn\'t get it? ', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        if (secs > 0)
          Text('Resend code in $countdown',
              key: const Key('resend-countdown'),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w700))
        else if (_auth.sending)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4A8FF)),
          )
        else
          GestureDetector(
            key: const Key('resend'),
            onTap: _auth.canResend ? _resend : null,
            child: const Text('Resend code',
                style: TextStyle(color: Color(0xFFD4A8FF), fontSize: 13, fontWeight: FontWeight.w800)),
          ),
      ],
    );
  }

  // ─── Pieces ──────────────────────────────────────────────────────────────

  Widget _dividerTitle(String text) {
    Widget line({required bool fadeLeft}) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.white.withValues(alpha: fadeLeft ? 0.0 : 0.18),
                Colors.white.withValues(alpha: fadeLeft ? 0.18 : 0.0),
              ]),
            ),
          ),
        );
    // The title is capped at 70% of the row so a long translation or a large
    // system font ellipsizes instead of overflowing.
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          line(fadeLeft: true),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.7),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
            ),
          ),
          line(fadeLeft: false),
        ],
      ),
    );
  }

  Widget _errorLine(String text, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.error_outline_rounded, color: _error, size: 15),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: const TextStyle(color: _error, fontSize: 12.5, height: 1.35))),
          ],
        ),
      );
}

/// "+91 | mobile number" with India flag, focus glow and a clear button.
class _PhoneField extends StatefulWidget {
  const _PhoneField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.hasError,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final bool hasError;
  final bool enabled;

  @override
  State<_PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<_PhoneField> {
  static const _accent = Color(0xFF9B30FF);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_rebuild);
    widget.controller.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_rebuild);
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    final border = widget.hasError
        ? const Color(0xFFFF5C7A)
        : focused
            ? _accent
            : Colors.white.withValues(alpha: 0.14);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 58,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: focused || widget.hasError ? 1.6 : 1.1),
        boxShadow: focused ? [BoxShadow(color: _accent.withValues(alpha: 0.22), blurRadius: 16)] : null,
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Text('🇮🇳', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          const Text('+91',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: Colors.white.withValues(alpha: 0.16),
          ),
          Expanded(
            child: TextField(
              key: const Key('phone-field'),
              controller: widget.controller,
              focusNode: widget.focusNode,
              enabled: widget.enabled,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: const [IndianMobileInputFormatter()],
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
              cursorColor: _accent,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Mobile number',
                hintStyle: TextStyle(color: Colors.white30, fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0),
                counterText: '',
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty && widget.enabled)
            IconButton(
              key: const Key('phone-clear'),
              tooltip: 'Clear',
              onPressed: () {
                widget.controller.clear();
                widget.onChanged('');
              },
              icon: const Icon(Icons.cancel_rounded, color: Colors.white38, size: 20),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}

/// Keeps the phone field to the 10-digit national number however it was typed
/// or pasted ("+91 98765 43210", "098765-43210").
class IndianMobileInputFormatter extends TextInputFormatter {
  const IndianMobileInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final normalized = PhoneAuthController.normalizePhone(newValue.text);
    if (normalized == newValue.text) return newValue;
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    super.key,
    required this.label,
    required this.busyLabel,
    required this.busy,
    required this.dimmed,
    required this.onTap,
  });

  final String label;
  final String busyLabel;
  final bool busy;
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed && !busy ? 0.55 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [_PhoneAuthScreenState._accent, _PhoneAuthScreenState._accent2]),
          boxShadow: dimmed
              ? null
              : [
                  BoxShadow(
                    color: _PhoneAuthScreenState._accent.withValues(alpha: 0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            // Still tappable while dimmed, so a tap explains what's missing.
            onTap: busy ? null : onTap,
            child: SizedBox(
              height: 56,
              child: Center(
                child: busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                          ),
                          const SizedBox(width: 10),
                          Text(busyLabel,
                              style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
                        ],
                      )
                    : Text(label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        )),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
