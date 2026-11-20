import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/creator_page_service.dart';
import '../../../shared/theme/app_colors.dart';
import 'creator_dashboard_screen.dart';

class CreateCreatorProfileScreen extends StatefulWidget {
  const CreateCreatorProfileScreen({super.key});

  @override
  State<CreateCreatorProfileScreen> createState() =>
      _CreateCreatorProfileScreenState();
}

/// Any player can apply to become a creator — there is no Aura threshold (backend ADR 140).
/// The form is an application an admin reviews: they approve it, ask for changes (we show
/// their note and let the player edit and resubmit), or reject it (with an optional reason;
/// the player may apply again).
enum _Step { loading, notEligible, form, pending, rejected, submitted }

class _CreateCreatorProfileScreenState
    extends State<CreateCreatorProfileScreen> {
  static const _bg = Color(0xFF080810);
  static const _card = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  final _service = CreatorPageService();

  final _displayNameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _twitterCtrl = TextEditingController();

  _Step _step = _Step.loading;
  bool _saving = false;
  File? _pickedImage;
  List<String> _categories = [];
  String? _selectedCategory;

  // Review state from GET /creator/setup-status.
  String? _changesNote; // admin's note when they asked for changes
  String? _rejectedReason; // optional reason when rejected
  DateTime? _appliedAt;
  bool _isResubmission = false;

  // Username availability
  _NameStatus _nameStatus = _NameStatus.idle;
  List<String> _suggestions = [];
  String _nameChecked = '';
  Timer? _nameDebounce;

  static const _benefits = [
    (
      Icons.rocket_launch_rounded,
      Color(0xFF7B2CBF),
      'Launch Challenges',
      'Create and publish your own branded challenges',
    ),
    (
      Icons.people_rounded,
      Color(0xFF4B6EF6),
      'Build a Following',
      'Grow an audience that competes on your content',
    ),
    (
      Icons.diamond_rounded,
      Color(0xFFFF6B9D),
      'Earn Rewards',
      'Receive Aura bonuses when players participate',
    ),
    (
      Icons.bar_chart_rounded,
      Color(0xFF06B6D4),
      'Track Analytics',
      'See reach, participation rates, and top scores',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _usernameCtrl.addListener(_onUsernameChanged);
    _load();
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _usernameCtrl.removeListener(_onUsernameChanged);
    _displayNameCtrl.dispose();
    _usernameCtrl.dispose();
    _bioCtrl.dispose();
    _instagramCtrl.dispose();
    _youtubeCtrl.dispose();
    _twitterCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted && _step != _Step.loading)
      setState(() => _step = _Step.loading);
    Map<String, dynamic> status;
    try {
      status = await _service.fetchSetupStatus();
    } catch (_) {
      status = {};
    }
    final currentStep = status['currentStep'] as String? ?? 'ELIGIBLE';
    _changesNote = status['changesRequestedNote'] as String?;
    _rejectedReason = status['rejectedReason'] as String?;
    _appliedAt =
        DateTime.tryParse(status['appliedAt']?.toString() ?? '')?.toLocal();

    switch (currentStep) {
      case 'ACTIVE':
      case 'SETUP':
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CreatorDashboardScreen()),
        );
        return;
      case 'NOT_ELIGIBLE':
        if (mounted) setState(() => _step = _Step.notEligible);
        return;
      case 'PENDING_REVIEW':
        if (mounted) setState(() => _step = _Step.pending);
        return;
      case 'REJECTED':
        if (mounted) setState(() => _step = _Step.rejected);
        return;
      case 'CHANGES_REQUESTED':
        await _openForm(prefill: true);
        return;
      default: // ELIGIBLE
        await _openForm(prefill: false);
    }
  }

  /// Show the form; on a resubmission, fill it with what was sent last time.
  Future<void> _openForm({required bool prefill}) async {
    final results = await Future.wait<Object?>([
      _service.fetchCategories(),
      prefill ? _service.fetchOwnPage() : Future.value(null),
    ]);
    if (!mounted) return;
    final categories = results[0] as List<String>;
    final page = results[1] as Map<String, dynamic>?;
    if (page != null) {
      _isResubmission = true;
      _displayNameCtrl.text = page['displayName'] as String? ?? '';
      _usernameCtrl.text = page['username'] as String? ?? '';
      _bioCtrl.text = page['bio'] as String? ?? '';
      final links =
          (page['socialLinks'] as Map?)?.cast<String, dynamic>() ?? {};
      _instagramCtrl.text = links['instagram'] as String? ?? '';
      _youtubeCtrl.text = links['youtube'] as String? ?? '';
      _twitterCtrl.text = links['twitter'] as String? ?? '';
      final cat = page['category'] as String?;
      _selectedCategory = categories.contains(cat) ? cat : null;
    }
    setState(() {
      _categories = categories;
      _step = _Step.form;
    });
  }

  // ── Username availability check ───────────────────────────────────────────

  void _onUsernameChanged() {
    final name = _usernameCtrl.text.trim();
    if (name == _nameChecked) return;
    if (name.length < 2) {
      _nameDebounce?.cancel();
      setState(() {
        _nameStatus = _NameStatus.idle;
        _nameChecked = name;
        _suggestions = [];
      });
      return;
    }
    setState(() => _nameStatus = _NameStatus.checking);
    _nameDebounce?.cancel();
    _nameDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _checkName(name),
    );
  }

  Future<void> _checkName(String name) async {
    try {
      final res = await _service.checkUsername(name);
      if (!mounted) return;
      final available = res['available'] as bool? ?? false;
      setState(() {
        _nameChecked = name;
        _suggestions = (res['suggestions'] as List?)?.cast<String>() ?? [];
        _nameStatus = available ? _NameStatus.available : _NameStatus.taken;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _nameStatus = _NameStatus.idle;
        _nameChecked = name;
      });
    }
  }

  void _applySuggestion(String s) {
    _usernameCtrl.text = s;
    _usernameCtrl.selection = TextSelection.collapsed(
      offset: _usernameCtrl.text.length,
    );
  }

  // ── Photo picker ──────────────────────────────────────────────────────────

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (_) => Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0E0E1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Profile Photo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                _photoOption(
                  Icons.camera_alt_rounded,
                  'Camera',
                  ImageSource.camera,
                ),
                const SizedBox(height: 12),
                _photoOption(
                  Icons.photo_library_rounded,
                  'Gallery',
                  ImageSource.gallery,
                ),
              ],
            ),
          ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 512,
    );
    if (picked != null && mounted) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  Widget _photoOption(IconData icon, String label, ImageSource source) {
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
            Icon(icon, color: _accent, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final displayName = _displayNameCtrl.text.trim();
    final username = _usernameCtrl.text.trim();

    if (displayName.isEmpty) {
      _snack('Please enter a display name');
      return;
    }
    if (username.isEmpty) {
      _snack('Please choose a username');
      return;
    }
    if (_nameStatus == _NameStatus.checking) {
      _snack('Checking username availability — please wait a moment');
      return;
    }
    if (_nameStatus != _NameStatus.available) {
      _snack('Please choose an available username');
      return;
    }

    setState(() => _saving = true);
    try {
      String? profileImageKey;
      if (_pickedImage != null) {
        final uploadData = await _service.getProfileImageUploadUrl();
        final uploadUrl = uploadData['uploadUrl'] as String;
        profileImageKey = uploadData['key'] as String;
        await ApiClient().uploadToS3(
          uploadUrl,
          _pickedImage!,
          contentType: 'image/jpeg',
        );
      }

      await _service.reserveUsername(username);
      await _service.createPage(
        displayName: displayName,
        username: username,
        bio: _bioCtrl.text.trim(),
        profileImage: profileImageKey,
        category: _selectedCategory,
        socialLinks: {
          if (_instagramCtrl.text.trim().isNotEmpty)
            'instagram': _instagramCtrl.text.trim(),
          if (_youtubeCtrl.text.trim().isNotEmpty)
            'youtube': _youtubeCtrl.text.trim(),
          if (_twitterCtrl.text.trim().isNotEmpty)
            'twitter': _twitterCtrl.text.trim(),
        },
      );

      if (!mounted) return;
      setState(() {
        _saving = false;
        _appliedAt = DateTime.now();
        _step = _Step.submitted;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(e.toString());
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF1A0A2E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Become a Creator'),
      ),
      body: switch (_step) {
        _Step.loading => const Center(
          child: CircularProgressIndicator(color: _accent),
        ),
        _Step.notEligible => _buildStatus(
          icon: Icons.block_rounded,
          color: const Color(0xFFF87171),
          title: 'Your account isn\'t active',
          body:
              'Only active accounts can apply to become a creator. Contact support if you think this is a mistake.',
        ),
        _Step.form => _buildForm(),
        _Step.pending => _buildStatus(
          icon: Icons.hourglass_top_rounded,
          color: const Color(0xFFFACC15),
          title: 'Application under review',
          body:
              'Our team is reviewing your creator application${_appliedDate()}. '
              'We\'ll notify you as soon as there\'s a decision.',
        ),
        _Step.submitted => _buildStatus(
          icon: Icons.mark_email_read_rounded,
          color: const Color(0xFF22C55E),
          title: 'Application sent!',
          body:
              'Thanks for applying. Our team will review it — we may approve it, ask you for '
              'a few more details, or let you know why it wasn\'t approved. We\'ll notify you.',
        ),
        _Step.rejected => _buildStatus(
          icon: Icons.cancel_rounded,
          color: const Color(0xFFF87171),
          title: 'Not approved this time',
          body:
              'Your creator application wasn\'t approved. You can update it and apply again.',
          note: _rejectedReason,
          noteLabel: 'Reason from our team',
          actionLabel: 'Update & apply again',
          onAction: () => _openForm(prefill: true),
        ),
      },
    );
  }

  String _appliedDate() {
    final d = _appliedAt;
    if (d == null) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return ' (sent ${d.day} ${months[d.month - 1]})';
  }

  // ── Status (under review / sent / not approved / inactive) ───────────────

  Widget _buildStatus({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
    String? note,
    String? noteLabel,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.40),
                  width: 1.5,
                ),
              ),
              child: Icon(icon, color: color, size: 40),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                fontFamily: 'ClashDisplay',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.6,
              ),
            ),
            if (note != null && note.trim().isNotEmpty) ...[
              const SizedBox(height: 20),
              _NoteCard(label: noteLabel ?? 'Note', text: note, color: color),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: onAction ?? () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(actionLabel ?? 'Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Application form ──────────────────────────────────────────────────────

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_changesNote != null && _changesNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            _NoteCard(
              label: 'Our team asked for a few changes',
              text: _changesNote!,
              color: const Color(0xFFFB923C),
            ),
            const SizedBox(height: 16),
          ],
          // ── Hero banner ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 24),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF2D0B5A), Color(0xFF0A1A40)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _accent.withValues(alpha: 0.30)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickPhoto,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: _accent.withValues(alpha: 0.22),
                        backgroundImage:
                            _pickedImage != null
                                ? FileImage(_pickedImage!)
                                : null,
                        child:
                            _pickedImage == null
                                ? const Icon(
                                  Icons.add_a_photo_rounded,
                                  color: Color(0xFFD4A8FF),
                                  size: 26,
                                )
                                : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Launch Your Own Challenges',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay',
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Build a brand, grow followers, and earn Aura\nwhen players compete on your content.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // ── Benefits grid ──────────────────────────────────────────────
          const Text(
            'What you get',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'ClashDisplay',
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.55,
            children:
                _benefits
                    .map(
                      (b) => _BenefitCard(
                        icon: b.$1,
                        color: b.$2,
                        title: b.$3,
                        subtitle: b.$4,
                      ),
                    )
                    .toList(),
          ),

          const SizedBox(height: 28),

          // ── Form ───────────────────────────────────────────────────────
          const Text(
            'Your application',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              fontFamily: 'ClashDisplay',
            ),
          ),
          const SizedBox(height: 14),

          _FieldLabel('Display Name'),
          const SizedBox(height: 6),
          TextField(
            controller: _displayNameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: _inputDecor('e.g. Riya Sharma'),
          ),
          const SizedBox(height: 16),

          _FieldLabel('Username'),
          const SizedBox(height: 6),
          TextField(
            controller: _usernameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: _inputDecor('e.g. riya_moves'),
          ),
          if (_nameStatus != _NameStatus.idle) ...[
            const SizedBox(height: 6),
            _NameStatusRow(status: _nameStatus),
          ],
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  _suggestions
                      .map(
                        (s) => GestureDetector(
                          onTap: () => _applySuggestion(s),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              s,
                              style: const TextStyle(
                                color: Color(0xFFD4A8FF),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ],
          const SizedBox(height: 16),

          _FieldLabel('Content Category'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: DropdownButton<String>(
              value: _selectedCategory,
              hint: const Text(
                'Select a category',
                style: TextStyle(color: AppColors.textFaint, fontSize: 14),
              ),
              dropdownColor: const Color(0xFF1A0A30),
              iconEnabledColor: Colors.white38,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items:
                  _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
            ),
          ),
          const SizedBox(height: 16),

          _FieldLabel('Bio  (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _bioCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDecor(
              'Tell us what kind of content you create and who it\'s for…',
            ),
          ),
          const SizedBox(height: 16),

          _FieldLabel('Social Links  (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _instagramCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDecor('Instagram URL'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _youtubeCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDecor('YouTube URL'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _twitterCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDecor('Twitter / X URL'),
          ),

          const SizedBox(height: 16),
          const Text(
            'Our team reviews every application. We\'ll notify you when it\'s approved, '
            'or if we need a few more details.',
            style: TextStyle(
              color: AppColors.textFaint,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),

          // ── Submit ─────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                disabledBackgroundColor: _accent.withValues(alpha: 0.50),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child:
                  _saving
                      ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                      : Text(
                        _isResubmission
                            ? 'Resubmit Application'
                            : 'Submit Application',
                      ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
    filled: true,
    fillColor: _card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _accent, width: 1.5),
    ),
  );
}

// ── Name status enum ──────────────────────────────────────────────────────────

enum _NameStatus { idle, checking, available, taken }

// ── Name status row ───────────────────────────────────────────────────────────

class _NameStatusRow extends StatelessWidget {
  final _NameStatus status;
  const _NameStatusRow({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Widget leading;
    final String label;

    switch (status) {
      case _NameStatus.checking:
        color = AppColors.textFaint;
        leading = const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white38,
          ),
        );
        label = 'Checking availability…';
      case _NameStatus.available:
        color = const Color(0xFF22C55E);
        leading = const Icon(
          Icons.check_circle_rounded,
          color: Color(0xFF22C55E),
          size: 15,
        );
        label = 'Username is available!';
      case _NameStatus.taken:
        color = Colors.redAccent;
        leading = const Icon(
          Icons.cancel_rounded,
          color: Colors.redAccent,
          size: 15,
        );
        label = 'That username isn\'t available';
      case _NameStatus.idle:
        return const SizedBox.shrink();
    }

    return Row(
      children: [
        leading,
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ── Note card (admin's note / reason) ─────────────────────────────────────────

class _NoteCard extends StatelessWidget {
  final String label;
  final String text;
  final Color color;
  const _NoteCard({
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Benefit card ──────────────────────────────────────────────────────────────

class _BenefitCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _BenefitCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF100A20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ── Field label helper ─────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.textMuted,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );
}
