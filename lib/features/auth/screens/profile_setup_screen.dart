import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/auth_api_service.dart';
import '../../../core/utils/error_message.dart';
import '../../../shared/theme/app_colors.dart';
import '../../../shared/theme/app_text_styles.dart';
import 'city_interests_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  DateTime? _dob;
  String? _gender;
  bool _saving = false;

  File? _pickedImage;

  static const _purple = Color(0xFF7B2CBF);
  static const _genders = ['Male', 'Female', 'Non-binary', 'Prefer not to say'];
  static final _nameRegExp = RegExp(r'^[a-zA-Z ]+$');
  static final _nameCharRegExp = RegExp(r'[a-zA-Z ]');

  // The docs say the backend only accepts male/female/other, but the live
  // validation error actually lists 4 distinct values — collapsing
  // Non-binary/Prefer not to say into 'other' made both selections fail.
  String _genderApiValue(String? uiGender) {
    switch (uiGender) {
      case 'Male':
        return 'male';
      case 'Female':
        return 'female';
      case 'Non-binary':
        return 'non-binary';
      case 'Prefer not to say':
        return 'prefer not to say';
      default:
        return 'prefer not to say';
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _pickDob() async {
    // Backend requires the user to be at least 13 years old.
    final maxDob = DateTime.now().subtract(const Duration(days: 365 * 13));
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: maxDob,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _purple,
            onPrimary: Colors.white,
            surface: Color(0xFF1A1A2E),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0E0E1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Add Profile Photo',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _sheetOption(Icons.camera_alt_rounded, 'Camera', ImageSource.camera),
            const SizedBox(height: 12),
            _sheetOption(Icons.photo_library_rounded, 'Gallery', ImageSource.gallery),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80, maxWidth: 512);
    if (picked != null && mounted) setState(() => _pickedImage = File(picked.path));
  }

  Widget _sheetOption(IconData icon, String label, ImageSource source) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _purple, size: 22),
            const SizedBox(width: 14),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_pickedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a profile photo.')),
      );
      return;
    }
    if (_nameCtrl.text.trim().isEmpty || _usernameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in your name and username.')),
      );
      return;
    }
    if (!_nameRegExp.hasMatch(_nameCtrl.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name can only contain letters.')),
      );
      return;
    }
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth.')),
      );
      return;
    }
    if (_gender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your gender.')),
      );
      return;
    }
    setState(() => _saving = true);

    try {
      final service = AuthApiService();

      if (_pickedImage != null) {
        final uploadData = await service.getAvatarUploadUrl('image/jpeg');
        final uploadUrl = uploadData['uploadUrl'] as String;
        final publicUrl = uploadData['publicUrl'] as String;
        await ApiClient().uploadToS3(
          uploadUrl,
          _pickedImage!,
          contentType: 'image/jpeg',
        );
        await service.updateAvatar(publicUrl);
      }

      // The REST backend is the source of truth for the profile — if this
      // fails, stay on this screen and let the user retry rather than
      // silently advancing with a profile the backend never received.
      await service.updateProfile(
        displayName: _nameCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        gender: _genderApiValue(_gender),
        dateOfBirth: _dob,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const CityInterestsScreen()));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(humanizeError(e))),
      );
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final top = MediaQuery.of(context).padding.top;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // Purple radial glow at top
            Positioned(
              top: -80,
              left: size.width * 0.5 - 180,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _purple.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, top > 0 ? 8 : 20, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ──────────────────────────────────────────────
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/Splash screen/Star icon.png',
                          width: 28,
                          height: 28,
                        ),
                        const SizedBox(width: 10),
                        Image.asset(
                          'assets/images/Splash screen/Aura arena.png',
                          width: size.width * 0.38,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),

                    SizedBox(height: size.height * 0.042),

                    // ── Avatar ──────────────────────────────────────────────
                    Center(
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: Stack(
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Color(0xFF9B4DCA), Color(0xFF5A189A)],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _purple.withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: _pickedImage != null
                                    ? Image.file(_pickedImage!, fit: BoxFit.cover)
                                    : const Icon(Icons.person_rounded,
                                        color: Colors.white, size: 44),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: const BoxDecoration(
                                  color: _purple,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _pickedImage != null
                                      ? Icons.check_rounded
                                      : Icons.camera_alt_rounded,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: size.height * 0.032),

                    // ── Title ────────────────────────────────────────────────
                    const Text('Create your\nprofile',
                        style: AppTextStyles.compactTitle),
                    const SizedBox(height: 6),
                    Text(
                      'Tell us a little about yourself',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 14,
                      ),
                    ),

                    SizedBox(height: size.height * 0.036),

                    // ── Full Name ────────────────────────────────────────────
                    _label('Full Name'),
                    const SizedBox(height: 8),
                    _inputField(
                      controller: _nameCtrl,
                      hint: 'Enter your full name',
                      icon: Icons.badge_outlined,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(_nameCharRegExp),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // ── Username ─────────────────────────────────────────────
                    _label('Username'),
                    const SizedBox(height: 8),
                    _inputField(
                      controller: _usernameCtrl,
                      hint: 'Choose a username',
                      icon: Icons.alternate_email_rounded,
                      prefix: '@',
                    ),

                    const SizedBox(height: 20),

                    // ── Date of Birth ────────────────────────────────────────
                    _label('Date of Birth'),
                    const SizedBox(height: 8),
                    _tapField(
                      onTap: _pickDob,
                      icon: Icons.cake_outlined,
                      value: _dob == null
                          ? null
                          : '${_dob!.day.toString().padLeft(2, '0')} / '
                              '${_dob!.month.toString().padLeft(2, '0')} / '
                              '${_dob!.year}',
                      hint: 'DD / MM / YYYY',
                    ),

                    const SizedBox(height: 20),

                    // ── Gender ───────────────────────────────────────────────
                    _label('Gender'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _genders.map((g) {
                        final selected = _gender == g;
                        return GestureDetector(
                          onTap: () => setState(() => _gender = g),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _purple
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                color: selected
                                    ? _purple
                                    : Colors.white.withValues(alpha: 0.18),
                                width: 1.2,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: _purple.withValues(alpha: 0.40),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      )
                                    ]
                                  : null,
                            ),
                            child: Text(
                              g,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.55),
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    SizedBox(height: size.height * 0.05),

                    // ── Continue button ───────────────────────────────────────
                    GestureDetector(
                      onTap: _saving ? null : _save,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _saving
                                ? [Colors.grey.shade800, Colors.grey.shade700]
                                : const [Color(0xFF9B4DCA), Color(0xFF5A189A)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _saving
                              ? null
                              : [
                                  BoxShadow(
                                    color: _purple.withValues(alpha: 0.50),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  )
                                ],
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared UI helpers ──────────────────────────────────────────────────────

  Widget _label(String text) => Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      );

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? prefix,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: TextField(
        controller: controller,
        textCapitalization: textCapitalization,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: const Color(0xFF7B2CBF),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: AppColors.textFaint, fontSize: 15),
          prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.35), size: 20),
          prefixText: prefix,
          prefixStyle: TextStyle(
              color: Colors.white.withValues(alpha: 0.40), fontSize: 15),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _tapField({
    required VoidCallback onTap,
    required IconData icon,
    required String hint,
    String? value,
    IconData? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value != null
                ? const Color(0xFF7B2CBF).withValues(alpha: 0.60)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: Colors.white.withValues(alpha: 0.35), size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                  color: value != null
                      ? Colors.white
                      : AppColors.textFaint,
                  fontSize: 15,
                ),
              ),
            ),
            if (trailing != null)
              Icon(trailing,
                  color: Colors.white.withValues(alpha: 0.35), size: 22),
          ],
        ),
      ),
    );
  }
}
