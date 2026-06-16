import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../video/widgets/video_player_widget.dart';

class CreatorReviewScreen extends StatefulWidget {
  final QueryDocumentSnapshot request;

  const CreatorReviewScreen({super.key, required this.request});

  @override
  State<CreatorReviewScreen> createState() => _CreatorReviewScreenState();
}

class _CreatorReviewScreenState extends State<CreatorReviewScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  // Launch controls
  final _auraCtrl      = TextEditingController();
  final _categoryCtrl  = TextEditingController();
  final _rejectCtrl    = TextEditingController();
  DateTime? _endDate;

  bool _submitting = false;

  // Difficulty → default Aura
  static const _difficultyAura = {
    'Easy':   50,
    'Medium': 100,
    'Hard':   150,
    'Expert': 200,
  };

  static const _difficultyColor = {
    'Easy':   Color(0xFF22C55E),
    'Medium': Color(0xFFF59E0B),
    'Hard':   Color(0xFFEF4444),
    'Expert': Color(0xFF9333EA),
  };

  @override
  void initState() {
    super.initState();
    final data       = widget.request.data() as Map<String, dynamic>;
    final difficulty = data['difficulty'] as String? ?? 'Medium';
    final category   = data['category'] as String? ?? '';
    _auraCtrl.text     = '${_difficultyAura[difficulty] ?? 100}';
    _categoryCtrl.text = category;
  }

  @override
  void dispose() {
    _auraCtrl.dispose();
    _categoryCtrl.dispose();
    _rejectCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<bool> _verifyAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data()?['isAdmin'] == true;
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade800 : const Color(0xFF1A0A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            onPrimary: Colors.white,
            surface: Color(0xFF1A0A2E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  // ── Approve ───────────────────────────────────────────────────────────────

  Future<void> _approve() async {
    final auraPoints = int.tryParse(_auraCtrl.text.trim());
    if (auraPoints == null || auraPoints <= 0) {
      _snack('Please enter a valid Aura points value', error: true);
      return;
    }

    if (!await _verifyAdmin()) {
      _snack('Unauthorized — admin access required', error: true);
      return;
    }

    setState(() => _submitting = true);

    final data = widget.request.data() as Map<String, dynamic>;
    final db   = FirebaseFirestore.instance;

    try {
      final batch        = db.batch();
      final challengeRef = db.collection('challenges').doc();

      // Build the challenge doc — include all fields from the request + admin
      // launch controls. scoringChecklist from the creator (if provided) is
      // stored as aiScoringChecklist so the existing scoring pipeline picks it
      // up automatically.
      final challengeData = <String, dynamic>{
        'title':        data['title'] ?? '',
        'description':  data['description'] ?? '',
        'instructions': data['instructions'] ?? '',
        'videoUrl':     data['videoUrl'] ?? '',
        'creatorId':    data['creatorId'] ?? '',
        'status':       'approved',
        'auraPoints':   auraPoints,
        'difficulty':   data['difficulty'] ?? 'Medium',
        'category':     _categoryCtrl.text.trim().isEmpty
                          ? (data['category'] ?? '')
                          : _categoryCtrl.text.trim(),
        'instructionSteps': data['instructionSteps'] ?? [],
        'starsCount':   0,
        'createdAt':    Timestamp.now(),
      };

      // Creator-defined scoring checklist → passed to AI pipeline as
      // aiScoringChecklist so generateScoringRubric is skipped in favour of
      // the human-authored checklist.
      final creatorChecklist = data['scoringChecklist'];
      if (creatorChecklist is List && (creatorChecklist).isNotEmpty) {
        challengeData['aiScoringChecklist'] = creatorChecklist;
      }

      // Optional end date
      if (_endDate != null) {
        challengeData['endDate'] = Timestamp.fromDate(_endDate!);
      }

      batch.set(challengeRef, challengeData);
      batch.update(
        db.collection('creator_requests').doc(widget.request.id),
        {'status': 'approved', 'approvedAt': Timestamp.now()},
      );

      await batch.commit();

      if (!mounted) return;
      _snack('Challenge published!');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Approval failed: $e', error: true);
    }
  }

  // ── Reject ────────────────────────────────────────────────────────────────

  Future<void> _reject() async {
    if (_rejectCtrl.text.trim().isEmpty) {
      _snack('Please enter a rejection reason', error: true);
      return;
    }
    if (!await _verifyAdmin()) {
      _snack('Unauthorized — admin access required', error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance
          .collection('creator_requests')
          .doc(widget.request.id)
          .update({
        'status':          'rejected',
        'rejectionReason': _rejectCtrl.text.trim(),
        'rejectedAt':      Timestamp.now(),
      });
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Rejection failed: $e', error: true);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final data        = widget.request.data() as Map<String, dynamic>;
    final title       = data['title'] as String? ?? '';
    final difficulty  = data['difficulty'] as String? ?? '';
    final videoUrl    = data['videoUrl'] as String? ?? '';
    final steps       = (data['instructionSteps'] as List?)?.cast<String>() ?? [];
    final checklist   = (data['scoringChecklist']  as List?)?.cast<String>() ?? [];
    final diffColor   = _difficultyColor[difficulty] ?? Colors.white38;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Review Challenge',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFamily: 'ClashDisplay'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Video preview ──────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 9 / 16,
                child: VideoPlayerWidget(videoUrl),
              ),
            ),
            const SizedBox(height: 18),

            // ── Title + difficulty ─────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ClashDisplay',
                    ),
                  ),
                ),
                if (difficulty.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: diffColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: diffColor.withValues(alpha: 0.50)),
                    ),
                    child: Text(
                      difficulty,
                      style: TextStyle(
                          color: diffColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ── Instruction steps ──────────────────────────────────────
            if (steps.isNotEmpty) ...[
              _SectionLabel('Instruction Steps'),
              const SizedBox(height: 8),
              ...steps.asMap().entries.map((e) => _ReviewRow(
                    leading: '${e.key + 1}',
                    text: e.value,
                    color: _accent,
                  )),
              const SizedBox(height: 16),
            ],

            // ── Scoring checklist ──────────────────────────────────────
            if (checklist.isNotEmpty) ...[
              Row(children: [
                const _SectionLabel('Creator Checklist'),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF06B6D4)
                            .withValues(alpha: 0.40)),
                  ),
                  child: const Text(
                    'AI will use these',
                    style: TextStyle(
                        color: Color(0xFF06B6D4),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              ...checklist.map((item) => _ReviewRow(
                    leading: '✓',
                    text: item,
                    color: const Color(0xFF06B6D4),
                  )),
              const SizedBox(height: 16),
            ],

            const Divider(color: Colors.white10, height: 32),

            // ── Launch controls ────────────────────────────────────────
            const _SectionLabel('Launch Controls'),
            const SizedBox(height: 14),

            // Aura points
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Aura Points',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _auraCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15),
                        decoration: _inputDecor('e.g. 100'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Quick presets
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quick set',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 11)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: [50, 100, 150, 200].map((v) {
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _auraCtrl.text = '$v'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _auraCtrl.text == '$v'
                                  ? _accent.withValues(alpha: 0.22)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _auraCtrl.text == '$v'
                                    ? _accent.withValues(alpha: 0.60)
                                    : Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Text(
                              '$v',
                              style: TextStyle(
                                color: _auraCtrl.text == '$v'
                                    ? const Color(0xFFD4A8FF)
                                    : Colors.white54,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Category
            const Text('Category',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _categoryCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _inputDecor('e.g. Dance, Fitness, Comedy…'),
            ),

            const SizedBox(height: 16),

            // End date
            const Text('Campaign End Date',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickEndDate,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      color: _endDate != null
                          ? const Color(0xFFD4A8FF)
                          : Colors.white24,
                      size: 16,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _endDate != null
                          ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                          : 'No end date (runs indefinitely)',
                      style: TextStyle(
                        color: _endDate != null
                            ? Colors.white
                            : Colors.white38,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (_endDate != null)
                      GestureDetector(
                        onTap: () => setState(() => _endDate = null),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 16),
                      ),
                  ],
                ),
              ),
            ),

            const Divider(color: Colors.white10, height: 32),

            // ── Rejection reason ───────────────────────────────────────
            const Text('Rejection Reason',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _rejectCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDecor(
                  'Required if rejecting — explain what needs to change…'),
            ),

            const SizedBox(height: 28),

            // ── Action buttons ─────────────────────────────────────────
            if (_submitting)
              const Center(
                  child: CircularProgressIndicator(color: _accent))
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _approve,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Approve & Publish'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _reject,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade800,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: _card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          fontFamily: 'ClashDisplay',
        ),
      );
}

// ── Review row (step or checklist item) ───────────────────────────────────────

class _ReviewRow extends StatelessWidget {
  final String leading;
  final String text;
  final Color  color;

  const _ReviewRow({
    required this.leading,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                leading,
                style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
