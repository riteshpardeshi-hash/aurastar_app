import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/api_client.dart';
import '../../dashboard/dashboard.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  static const _purple = Color(0xFF7B2CBF);
  static const _bg     = Color(0xFF080810);

  // All start OFF
  bool _cameraOn       = false;
  bool _micOn          = false;
  bool _notifOn        = false;
  bool _galleryOn      = false;
  bool _saving         = false;

  bool get _requiredGranted => _cameraOn && _micOn;

  Future<void> _finish() async {
    if (!_requiredGranted) return;
    setState(() => _saving = true);
    try {
      final uid = await ApiClient().userId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_referral_code');
      // Mark setup complete for this specific user so splash never re-runs onboarding.
      if (uid != null && uid.isNotEmpty) {
        await prefs.setBool('setup_complete_$uid', true);
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Dashboard()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              // ── Scrollable body ──────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 36),

                      // ── Title ─────────────────────────────────────────────
                      const Text(
                        'Permissions',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Purple underline
                      Center(
                        child: Container(
                          width: 120,
                          height: 2,
                          decoration: BoxDecoration(
                            color: _purple,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // ── Subtitles ──────────────────────────────────────────
                      const Text(
                        'Required for Scoring',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF9B59B6),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'We need this to record challenges and award Aura',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Permission cards ───────────────────────────────────
                      _PermCard(
                        iconAsset: 'assets/images/permissions/Asset 102.png',
                        title: 'Camera',
                        description: 'Required to record challenge videos',
                        required: true,
                        value: _cameraOn,
                        onChanged: (v) => setState(() => _cameraOn = v),
                      ),
                      const SizedBox(height: 12),
                      _PermCard(
                        iconAsset: 'assets/images/permissions/Asset 103.png',
                        title: 'Microphone',
                        description: 'Captures audio for AI scoring accuracy',
                        required: true,
                        value: _micOn,
                        onChanged: (v) => setState(() => _micOn = v),
                      ),
                      const SizedBox(height: 12),
                      _PermCard(
                        iconAsset: 'assets/images/permissions/Asset 104.png',
                        title: 'Notifications',
                        description:
                            'Stay updated on results, rewards, and challenges',
                        required: false,
                        value: _notifOn,
                        onChanged: (v) => setState(() => _notifOn = v),
                      ),
                      const SizedBox(height: 12),
                      _PermCard(
                        iconAsset: 'assets/images/permissions/Asset 105.png',
                        title: 'Gallery Access',
                        description:
                            'Save flex cards to your phone gallery',
                        subDescription:
                            'Flex cards only — your other videos stay private',
                        required: false,
                        value: _galleryOn,
                        onChanged: (v) => setState(() => _galleryOn = v),
                      ),

                      const SizedBox(height: 16),

                      // ── Info note ──────────────────────────────────────────
                      Image.asset(
                        'assets/images/permissions/Asset 110.png',
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                      ),

                      const SizedBox(height: 32),

                      // ── Continue button ────────────────────────────────────
                      AnimatedOpacity(
                        opacity: _requiredGranted ? 1.0 : 0.4,
                        duration: const Duration(milliseconds: 250),
                        child: GestureDetector(
                        onTap: (_requiredGranted && !_saving) ? _finish : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: _requiredGranted && !_saving
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF9B4DCA),
                                      Color(0xFF5A189A),
                                    ],
                                  )
                                : null,
                            color: _requiredGranted && !_saving
                                ? null
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _requiredGranted && !_saving
                                ? [
                                    BoxShadow(
                                      color: _purple.withValues(alpha: 0.45),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'Continue',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      ),  // AnimatedOpacity
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Permission card ────────────────────────────────────────────────────────────

class _PermCard extends StatelessWidget {
  final String iconAsset;
  final String title;
  final String description;
  final String? subDescription;
  final bool required;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermCard({
    required this.iconAsset,
    required this.title,
    required this.description,
    this.subDescription,
    required this.required,
    required this.value,
    required this.onChanged,
  });

  static const _purple  = Color(0xFF7B2CBF);
  static const _cardBg  = Color(0xFF0D0A1E);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _purple.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon
          Image.asset(iconAsset, width: 44, height: 44),
          const SizedBox(width: 12),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (subDescription != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subDescription!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.30),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Badge + toggle column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: required
                      ? const Color(0xFF8B0000).withValues(alpha: 0.80)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  required ? 'REQUIRED' : 'OPTIONAL',
                  style: TextStyle(
                    color: required
                        ? const Color(0xFFFF6B6B)
                        : Colors.white.withValues(alpha: 0.45),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Toggle
              Transform.scale(
                scale: 0.85,
                alignment: Alignment.centerRight,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeColor: Colors.white,
                  activeTrackColor: _purple,
                  inactiveThumbColor: Colors.white.withValues(alpha: 0.50),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                  trackOutlineColor:
                      WidgetStateProperty.all(Colors.transparent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
