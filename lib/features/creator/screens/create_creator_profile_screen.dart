import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreateCreatorProfileScreen extends StatefulWidget {
  const CreateCreatorProfileScreen({super.key});

  @override
  State<CreateCreatorProfileScreen> createState() =>
      _CreateCreatorProfileScreenState();
}

class _CreateCreatorProfileScreenState
    extends State<CreateCreatorProfileScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  final _pageNameCtrl = TextEditingController();
  final _bioCtrl      = TextEditingController();

  String?     _selectedCategory;
  bool        _loading    = true;
  bool        _saving     = false;
  String?     _pendingStatus; // null = no application, 'pending'/'rejected'

  // Name availability check
  _NameStatus _nameStatus  = _NameStatus.idle;
  String      _nameChecked = '';
  Timer?      _nameDebounce;

  static const _categories = [
    'Dance', 'Fitness', 'Fashion', 'Comedy',
    'Cooking', 'Gaming', 'Music', 'Travel', 'Other',
  ];

  static const _benefits = [
    (Icons.rocket_launch_rounded,  Color(0xFF7B2CBF), 'Launch Challenges',
        'Create and publish your own branded challenges'),
    (Icons.people_rounded,         Color(0xFF4B6EF6), 'Build a Following',
        'Grow an audience that competes on your content'),
    (Icons.diamond_rounded,        Color(0xFFFF6B9D), 'Earn Rewards',
        'Receive Aura bonuses when players participate'),
    (Icons.bar_chart_rounded,      Color(0xFF06B6D4), 'Track Analytics',
        'See reach, participation rates, and top scores'),
  ];

  @override
  void initState() {
    super.initState();
    _loadApplicationStatus();
    _pageNameCtrl.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameDebounce?.cancel();
    _pageNameCtrl.removeListener(_onNameChanged);
    _pageNameCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  // ── Name similarity check ─────────────────────────────────────────────────

  void _onNameChanged() {
    final name = _pageNameCtrl.text.trim();
    if (name == _nameChecked) return;
    if (_normalize(name).length < 2) {
      _nameDebounce?.cancel();
      setState(() { _nameStatus = _NameStatus.idle; _nameChecked = name; });
      return;
    }
    setState(() => _nameStatus = _NameStatus.checking);
    _nameDebounce?.cancel();
    _nameDebounce =
        Timer(const Duration(milliseconds: 650), () => _checkName(name));
  }

  Future<void> _checkName(String name) async {
    final normInput = _normalize(name);
    if (normInput.length < 2) {
      if (mounted) setState(() { _nameStatus = _NameStatus.idle; _nameChecked = name; });
      return;
    }

    try {
      // Check against existing approved creators
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('isCreator', isEqualTo: true)
          .get();

      bool conflict = false;
      for (final doc in snap.docs) {
        final existing = _normalize(
            (doc.data()['pageName'] as String? ?? ''));
        if (_isTooSimilar(normInput, existing)) {
          conflict = true;
          break;
        }
      }

      // Also check pending applications to prevent race conditions
      if (!conflict) {
        final pendingSnap = await FirebaseFirestore.instance
            .collection('creator_applications')
            .where('status', isEqualTo: 'pending')
            .get();
        for (final doc in pendingSnap.docs) {
          if (doc.id == FirebaseAuth.instance.currentUser?.uid) continue;
          final existing = _normalize(
              (doc.data()['pageName'] as String? ?? ''));
          if (_isTooSimilar(normInput, existing)) {
            conflict = true;
            break;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _nameChecked = name;
        _nameStatus =
            conflict ? _NameStatus.taken : _NameStatus.available;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _nameStatus = _NameStatus.idle; _nameChecked = name; });
    }
  }

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool _isTooSimilar(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    // Block if one is a substring of the other with ≥80% length overlap
    if (a.contains(b) || b.contains(a)) {
      final shorter = a.length < b.length ? a.length : b.length;
      final longer  = a.length > b.length ? a.length : b.length;
      if (shorter / longer >= 0.80) return true;
    }
    return false;
  }

  Future<void> _loadApplicationStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) { setState(() => _loading = false); return; }

    final doc = await FirebaseFirestore.instance
        .collection('creator_applications')
        .doc(uid)
        .get();

    if (!mounted) return;
    setState(() {
      _loading = false;
      if (doc.exists) {
        _pendingStatus = (doc.data()?['status'] as String?) ?? 'pending';
      }
    });
  }

  Future<void> _submit() async {
    final pageName = _pageNameCtrl.text.trim();
    if (pageName.isEmpty) {
      _snack('Please enter a page name');
      return;
    }
    if (_nameStatus == _NameStatus.checking) {
      _snack('Checking name availability — please wait a moment');
      return;
    }
    if (_nameStatus == _NameStatus.taken) {
      _snack('This name is too similar to an existing creator. Please choose a different one.');
      return;
    }
    if (_selectedCategory == null) {
      _snack('Please select a content category');
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _saving = true);

    try {
      // Enforce 500-Aura gate
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final totalRewards =
          (userDoc.data()?['totalRewards'] as num?)?.toInt() ?? 0;
      if (totalRewards < 500) {
        if (!mounted) return;
        setState(() => _saving = false);
        _snack(
            'You need 500 Aura to apply — you have $totalRewards. Keep completing challenges!');
        return;
      }

      // Persist display fields to user doc
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'pageName': pageName,
        'bio':      _bioCtrl.text.trim(),
        'category': _selectedCategory,
      });

      // Submit creator application
      await FirebaseFirestore.instance
          .collection('creator_applications')
          .doc(uid)
          .set({
        'uid':       uid,
        'pageName':  pageName,
        'bio':       _bioCtrl.text.trim(),
        'category':  _selectedCategory,
        'status':    'pending',
        'submittedAt': Timestamp.now(),
      });

      if (!mounted) return;
      setState(() {
        _saving        = false;
        _pendingStatus = 'pending';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Something went wrong. Please try again.');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A0A2E),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
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
        title: const Text(
          'Become a Creator',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFamily: 'ClashDisplay'),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _pendingStatus != null
              ? _buildPendingState()
              : _buildForm(),
    );
  }

  // ── Pending / success state ───────────────────────────────────────────────

  Widget _buildPendingState() {
    final approved = _pendingStatus == 'approved';
    final rejected = _pendingStatus == 'rejected';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: (approved
                        ? const Color(0xFF22C55E)
                        : rejected
                            ? Colors.red
                            : _accent)
                    .withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: (approved
                          ? const Color(0xFF22C55E)
                          : rejected
                              ? Colors.red
                              : _accent)
                      .withValues(alpha: 0.40),
                  width: 1.5,
                ),
              ),
              child: Icon(
                approved
                    ? Icons.check_circle_rounded
                    : rejected
                        ? Icons.cancel_rounded
                        : Icons.hourglass_top_rounded,
                color: approved
                    ? const Color(0xFF22C55E)
                    : rejected
                        ? Colors.redAccent
                        : const Color(0xFFD4A8FF),
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              approved
                  ? 'You\'re a Creator!'
                  : rejected
                      ? 'Application Not Approved'
                      : 'Application Submitted',
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
              approved
                  ? 'Your creator profile is live. Head to Creator Dashboard to launch your first challenge!'
                  : rejected
                      ? 'Your application didn\'t meet the requirements. Keep earning Aura and try again.'
                      : 'We\'re reviewing your application. You\'ll be notified once a decision is made — usually within 24–48 hours.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 14, height: 1.6),
            ),
            if (rejected) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () => setState(() => _pendingStatus = null),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Try Again'),
                ),
              ),
            ],
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
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star_rounded,
                      color: Color(0xFFD4A8FF), size: 30),
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
                      color: Colors.white54, fontSize: 13, height: 1.5),
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
            children: _benefits
                .map((b) => _BenefitCard(
                      icon: b.$1,
                      color: b.$2,
                      title: b.$3,
                      subtitle: b.$4,
                    ))
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

          _FieldLabel('Creator / Page Name'),
          const SizedBox(height: 6),
          TextField(
            controller: _pageNameCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: _inputDecor('e.g. Studio Moves, Chef Priya…'),
          ),
          if (_nameStatus != _NameStatus.idle) ...[
            const SizedBox(height: 6),
            _NameStatusRow(status: _nameStatus),
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
              hint: const Text('Select a category',
                  style: TextStyle(color: Colors.white38, fontSize: 14)),
              dropdownColor: const Color(0xFF1A0A30),
              iconEnabledColor: Colors.white38,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: _categories
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
                'Tell us what kind of content you create and who it\'s for…'),
          ),

          const SizedBox(height: 28),

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
                    borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Text('Submit Application'),
            ),
          ),

          const SizedBox(height: 12),
          const Text(
            'Applications are reviewed within 24–48 hours.\nYou\'ll receive a notification once a decision is made.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.white24, fontSize: 14),
        filled: true,
        fillColor: _card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: _accent, width: 1.5)),
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
        color   = Colors.white38;
        leading = const SizedBox(
          width: 13,
          height: 13,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        );
        label = 'Checking availability…';
      case _NameStatus.available:
        color   = const Color(0xFF22C55E);
        leading = const Icon(Icons.check_circle_rounded,
            color: Color(0xFF22C55E), size: 15);
        label = 'Name is available!';
      case _NameStatus.taken:
        color   = Colors.redAccent;
        leading = const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 15);
        label = 'Too similar to an existing creator';
      case _NameStatus.idle:
        return const SizedBox.shrink();
    }

    return Row(
      children: [
        leading,
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
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
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600),
      );
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
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }
}
