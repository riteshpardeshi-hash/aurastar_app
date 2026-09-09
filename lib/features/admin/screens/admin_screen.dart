import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'review_screen.dart';
import 'creator_review_screen.dart';
import 'challenge_submissions_screen.dart';
import 'rubric_builder_screen.dart';
import 'admin_offers_screen.dart';

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  static const _bg     = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Admin Panel',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ClashDisplay')),
          bottom: TabBar(
            indicatorColor: _accent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(text: 'Pending'),
              Tab(text: 'Requests'),
              Tab(text: 'Live'),
              Tab(text: 'Offers'),
              Tab(text: 'All Subs'),
              Tab(text: 'Reports'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _PendingSubmissionsTab(),
            _CreatorRequestTab(),
            _LiveChallengesTab(),
            AdminOffersScreen(),
            ChallengeSubmissionsTab(),
            _ReportsTab(),
          ],
        ),
      ),
    );
  }
}

// ── Pending submissions tab ───────────────────────────────────────────────────

class _PendingSubmissionsTab extends StatelessWidget {
  const _PendingSubmissionsTab();

  static const _bg = Color(0xFF080810);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B2CBF)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _empty('No pending submissions', Icons.check_circle_outline_rounded);
        }
        return ColoredBox(
          color: _bg,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return _AdminCard(
                title: d['challengeTitle'] as String? ?? 'Submission',
                subtitle: 'User: ${d['userId']?.toString().substring(0, 8) ?? '—'}…',
                badge: 'PENDING',
                badgeColor: Colors.amber,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ReviewScreen(submission: docs[i])),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Creator brand requests tab ────────────────────────────────────────────────

class _CreatorRequestTab extends StatelessWidget {
  const _CreatorRequestTab();

  static const _bg = Color(0xFF080810);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('creator_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B2CBF)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _empty('No pending requests', Icons.inbox_outlined);
        }
        return ColoredBox(
          color: _bg,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final difficulty = d['difficulty'] as String? ?? 'Medium';
              return _AdminCard(
                title: d['title'] as String? ?? 'Challenge',
                subtitle: 'Creator: ${d['creatorId']?.toString().substring(0, 8) ?? '—'}…',
                badge: difficulty.toUpperCase(),
                badgeColor: _difficultyColor(difficulty),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CreatorReviewScreen(request: docs[i])),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Live challenges tab (Aura score assignment) ───────────────────────────────

class _LiveChallengesTab extends StatelessWidget {
  const _LiveChallengesTab();

  static const _bg = Color(0xFF080810);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challenges')
          .where('status', isEqualTo: 'approved')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B2CBF)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _empty('No live challenges', Icons.flash_off_outlined);
        }
        return ColoredBox(
          color: _bg,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d              = docs[i].data() as Map<String, dynamic>;
              final title          = d['title']         as String? ?? 'Challenge';
              final difficulty     = d['difficulty']    as String? ?? 'Medium';
              final auraPoints     = (d['auraPoints']   as num?)?.toInt() ?? 100;
              final category       = d['category']      as String? ?? '';
              final creatorId      = d['creatorId']     as String? ?? '';
              final scoringWeights = d['scoringWeights'] as Map<String, dynamic>?;
              final challengeId    = docs[i].id;

              return _LiveChallengeCard(
                challengeId:    challengeId,
                title:          title,
                difficulty:     difficulty,
                auraPoints:     auraPoints,
                category:       category,
                creatorId:      creatorId,
                scoringWeights: scoringWeights,
              );
            },
          ),
        );
      },
    );
  }
}

// ── Live challenge card with Aura score edit ──────────────────────────────────

class _LiveChallengeCard extends StatelessWidget {
  final String                  challengeId;
  final String                  title;
  final String                  difficulty;
  final int                     auraPoints;
  final String                  category;
  final String                  creatorId;
  final Map<String, dynamic>?   scoringWeights;

  const _LiveChallengeCard({
    required this.challengeId,
    required this.title,
    required this.difficulty,
    required this.auraPoints,
    required this.category,
    required this.creatorId,
    this.scoringWeights,
  });

  @override
  Widget build(BuildContext context) {
    final diffColor = _difficultyColor(difficulty);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF100A20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Expanded(
                child: Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              // Difficulty badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: diffColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border:
                      Border.all(color: diffColor.withValues(alpha: 0.45)),
                ),
                child: Text(difficulty,
                    style: TextStyle(
                        color: diffColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Stats row
          Row(
            children: [
              if (category.isNotEmpty) ...[
                Icon(Icons.category_outlined,
                    color: Colors.white38, size: 12),
                const SizedBox(width: 4),
                Text(category,
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                const SizedBox(width: 14),
              ],
              // Aura score display
              const Icon(Icons.auto_awesome,
                  color: Color(0xFFD4A8FF), size: 13),
              const SizedBox(width: 4),
              Text('$auraPoints Aura',
                  style: const TextStyle(
                      color: Color(0xFFD4A8FF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              // Rubric button
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RubricBuilderScreen(
                      challengeId:    challengeId,
                      challengeTitle: title,
                      existingWeights: scoringWeights,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: scoringWeights != null
                        ? const Color(0xFF22C55E).withValues(alpha: 0.12)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: scoringWeights != null
                            ? const Color(0xFF22C55E).withValues(alpha: 0.40)
                            : Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        scoringWeights != null
                            ? Icons.tune_rounded
                            : Icons.tune_outlined,
                        color: scoringWeights != null
                            ? const Color(0xFF22C55E)
                            : Colors.white38,
                        size: 12),
                      const SizedBox(width: 3),
                      Text('Rubric',
                          style: TextStyle(
                              color: scoringWeights != null
                                  ? const Color(0xFF22C55E)
                                  : Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Edit score button
              GestureDetector(
                onTap: () => _showEditSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B2CBF).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            const Color(0xFF7B2CBF).withValues(alpha: 0.45)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.edit_outlined,
                          color: Color(0xFFD4A8FF), size: 12),
                      SizedBox(width: 4),
                      Text('Edit Score',
                          style: TextStyle(
                              color: Color(0xFFD4A8FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => _AuraEditSheet(
        challengeId:  challengeId,
        title:        title,
        currentAura:  auraPoints,
        difficulty:   difficulty,
        creatorId:    creatorId,
      ),
    );
  }
}

// ── Aura score edit bottom sheet ──────────────────────────────────────────────

class _AuraEditSheet extends StatefulWidget {
  final String challengeId;
  final String title;
  final int    currentAura;
  final String difficulty;
  final String creatorId;

  const _AuraEditSheet({
    required this.challengeId,
    required this.title,
    required this.currentAura,
    required this.difficulty,
    required this.creatorId,
  });

  @override
  State<_AuraEditSheet> createState() => _AuraEditSheetState();
}

class _AuraEditSheetState extends State<_AuraEditSheet> {
  static const _accent = Color(0xFF7B2CBF);

  static const _difficulties = [
    ('Easy',   Color(0xFF22C55E)),
    ('Medium', Color(0xFFF59E0B)),
    ('Hard',   Color(0xFFEF4444)),
    ('Expert', Color(0xFF9333EA)),
  ];

  static const _quickAura = [50, 75, 100, 125, 150, 175, 200];

  late final TextEditingController _auraCtrl;
  late String _difficulty;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _auraCtrl   = TextEditingController(text: '${widget.currentAura}');
    _difficulty = widget.difficulty;
  }

  @override
  void dispose() {
    _auraCtrl.dispose();
    super.dispose();
  }

  bool get _changed =>
      int.tryParse(_auraCtrl.text.trim()) != widget.currentAura ||
      _difficulty != widget.difficulty;

  Future<void> _save() async {
    final newAura = int.tryParse(_auraCtrl.text.trim());
    if (newAura == null || newAura <= 0) {
      _snack('Enter a valid Aura value', error: true);
      return;
    }

    // Admin check
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('users').doc(uid).get();
    if (userDoc.data()?['isAdmin'] != true) {
      _snack('Admin access required', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final db  = FirebaseFirestore.instance;
      final batch = db.batch();

      // Update challenge
      batch.update(db.collection('challenges').doc(widget.challengeId), {
        'auraPoints': newAura,
        'difficulty': _difficulty,
        'auraUpdatedAt': Timestamp.now(),
        'auraUpdatedBy': uid,
      });

      // Notify creator
      if (widget.creatorId.isNotEmpty) {
        final notifRef = db.collection('notifications').doc();
        batch.set(notifRef, {
          'userId':    widget.creatorId,
          'type':      'aura_score_updated',
          'title':     'Challenge score updated',
          'body':      '"${widget.title}" Aura reward updated to $newAura.',
          'challengeId': widget.challengeId,
          'read':      false,
          'createdAt': Timestamp.now(),
        });
      }

      await batch.commit();
      if (!mounted) return;
      _snack('Aura score updated to $newAura');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Save failed: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? Colors.red.shade800 : const Color(0xFF1A0A2E),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 20),

            // Title
            const Text('Edit Aura Score',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay')),
            const SizedBox(height: 4),
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),

            const SizedBox(height: 22),

            // Current → New
            Row(
              children: [
                _InfoBadge(
                    label: 'Current',
                    value: '${widget.currentAura}',
                    color: Colors.white38),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white24, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _auraCtrl,
                    builder: (_, v, __) {
                      final n = int.tryParse(v.text);
                      return _InfoBadge(
                          label: 'New',
                          value: n != null ? '$n' : '—',
                          color: n != null && n != widget.currentAura
                              ? _accent
                              : Colors.white38);
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Aura points field
            const _Label('Aura Points'),
            const SizedBox(height: 8),
            TextField(
              controller: _auraCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: Colors.white, fontSize: 22,
                  fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
              decoration: _inputDecor('e.g. 100'),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 14),

            // Quick-set chips
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _quickAura.map((v) {
                final sel = _auraCtrl.text.trim() == '$v';
                return GestureDetector(
                  onTap: () {
                    _auraCtrl.text = '$v';
                    setState(() {});
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel
                          ? _accent.withValues(alpha: 0.25)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel
                            ? _accent.withValues(alpha: 0.60)
                            : Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Text('$v',
                        style: TextStyle(
                            color: sel
                                ? const Color(0xFFD4A8FF)
                                : Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 22),

            // Difficulty
            const _Label('Difficulty'),
            const SizedBox(height: 10),
            Row(
              children: _difficulties.map((pair) {
                final name  = pair.$1;
                final color = pair.$2;
                final sel   = _difficulty == name;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _difficulty = name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: sel
                            ? color.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel
                              ? color.withValues(alpha: 0.65)
                              : Colors.white.withValues(alpha: 0.08),
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Text(name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: sel ? color : Colors.white24,
                              fontSize: 11,
                              fontWeight: sel
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 30),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_saving || !_changed) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor:
                      Colors.white.withValues(alpha: 0.06),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.white24, fontSize: 20),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.12))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.12))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: _accent, width: 1.5)),
      );
}

// ── Shared helpers ────────────────────────────────────────────────────────────

class _AdminCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color  badgeColor;
  final VoidCallback onTap;

  const _AdminCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF100A20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border:
                    Border.all(color: badgeColor.withValues(alpha: 0.40)),
              ),
              child: Text(badge,
                  style: TextStyle(
                      color: badgeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700));
}

class _InfoBadge extends StatelessWidget {
  final String label;
  final String value;
  final Color  color;
  const _InfoBadge(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11)),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
        ],
      );
}

Color _difficultyColor(String d) => switch (d) {
      'Easy'   => const Color(0xFF22C55E),
      'Hard'   => const Color(0xFFEF4444),
      'Expert' => const Color(0xFF9333EA),
      _        => const Color(0xFFF59E0B),
    };

Widget _empty(String msg, IconData icon) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          Text(msg,
              style: const TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ),
    );

// ── Reports tab ──────────────────────────────────────────────────────────────

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  bool _showFraud = false;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF080810),
      child: Column(
        children: [
          // Toggle: User Reports | Fraud Alerts
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _ToggleChip(
                  label: 'User Reports',
                  active: !_showFraud,
                  onTap: () => setState(() => _showFraud = false),
                ),
                const SizedBox(width: 8),
                _ToggleChip(
                  label: 'Fraud Alerts',
                  active: _showFraud,
                  color: Colors.redAccent,
                  onTap: () => setState(() => _showFraud = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: _showFraud ? _FraudAlertsList() : _UserReportsList(),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color? color;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFF7B2CBF);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? c.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? c.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? c : Colors.white38,
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _UserReportsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reports')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF7B2CBF)));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) return _empty('No pending reports', Icons.flag_outlined);
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) => _ReportCard(doc: docs[i]),
        );
      },
    );
  }
}

class _FraudAlertsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fraudAlerts')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.redAccent));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return _empty('No fraud alerts', Icons.verified_user_outlined);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) => _FraudAlertCard(doc: docs[i]),
        );
      },
    );
  }
}

class _FraudAlertCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _FraudAlertCard({required this.doc});

  static const _card = Color(0xFF1A0A0A);

  static const _reasonLabels = {
    'account_suspended':  'Suspended account attempted submission',
    'velocity_challenge': 'Too many attempts on same challenge (>3/hr)',
    'velocity_daily':     'Daily submission volume exceeded (>15/day)',
  };

  Future<void> _dismiss() async {
    await doc.reference.update({'status': 'dismissed'});
  }

  Future<void> _suspendUser(BuildContext context) async {
    final data = doc.data() as Map<String, dynamic>;
    final userId = data['userId'] as String? ?? '';
    if (userId.isEmpty) return;
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.update(db.collection('users').doc(userId), {
      'isSuspended': true,
      'suspendedAt': FieldValue.serverTimestamp(),
    });
    batch.update(doc.reference, {'status': 'actioned'});
    await batch.commit();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User suspended.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final reason = data['reason'] as String? ?? 'unknown';
    final label = _reasonLabels[reason] ?? reason;
    final userId = (data['userId'] as String? ?? '');
    final shortUid = userId.length > 8 ? userId.substring(0, 8) : userId;
    final challengeTitle = data['challengeTitle'] as String? ?? '';
    final ts = data['createdAt'];
    final when = ts is Timestamp ? _timeAgo(ts.toDate()) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.security_outlined,
                      color: Colors.redAccent, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Fraud alert',
                          style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text('UID: $shortUid…',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Text(when,
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.30)),
                  ),
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                if (challengeTitle.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Challenge: $challengeTitle',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _dismiss,
                  child: const Text('Dismiss',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white10),
              Expanded(
                child: TextButton(
                  onPressed: () => _suspendUser(context),
                  child: const Text('Suspend User',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ReportCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  const _ReportCard({required this.doc});

  static const _card = Color(0xFF140C28);

  Future<void> _dismiss() async {
    await doc.reference.update({'status': 'dismissed'});
  }

  Future<void> _removeContent(BuildContext context) async {
    final data = doc.data() as Map<String, dynamic>;
    final challengeId = data['challengeId'] as String?;
    final submissionId = data['submissionId'] as String?;
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    if (challengeId != null && challengeId.isNotEmpty) {
      batch.update(
        db.collection('challenges').doc(challengeId),
        {'status': 'removed', 'removedAt': FieldValue.serverTimestamp()},
      );
    }
    if (submissionId != null && submissionId.isNotEmpty) {
      batch.update(
        db.collection('submissions').doc(submissionId),
        {'isDeleted': true, 'isPublic': false},
      );
    }
    batch.update(doc.reference, {'status': 'actioned'});
    await batch.commit();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Content removed and report actioned.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] as String? ?? 'challenge';
    final isSubmission = type == 'submission';
    final title = data['challengeTitle'] as String? ??
        data['submissionId'] as String? ??
        'Unknown';
    final reason = data['reason'] as String? ?? 'No reason given';
    final reporterId = (data['reportedBy'] as String? ?? '');
    final shortId = reporterId.length > 8 ? reporterId.substring(0, 8) : reporterId;
    final ts = data['createdAt'];
    final when = ts is Timestamp ? _timeAgo(ts.toDate()) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSubmission ? Icons.videocam_outlined : Icons.flag_rounded,
                    color: Colors.redAccent,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSubmission ? 'Submission report' : 'Challenge report',
                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Text(when, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.30)),
                  ),
                  child: Text(reason,
                      style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                if (shortId.isNotEmpty)
                  Text('by $shortId…',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _dismiss,
                  child: const Text('Dismiss',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white10),
              Expanded(
                child: TextButton(
                  onPressed: () => _removeContent(context),
                  child: Text(
                    isSubmission ? 'Remove Video' : 'Remove Challenge',
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
