import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/creator_challenges_service.dart';
import '../../../core/services/creator_gates_service.dart';
import 'creator_challenge_analytics_screen.dart';
import 'creator_challenge_draft_screen.dart';
import 'creator_challenge_participants_screen.dart';
import 'creator_challenge_preview_screen.dart';
import 'creator_gate_history_screen.dart';
import 'creator_gate_rules_screen.dart';

class CreatorChallengeStatusScreen extends StatefulWidget {
  final String challengeId;

  const CreatorChallengeStatusScreen({super.key, required this.challengeId});

  @override
  State<CreatorChallengeStatusScreen> createState() => _CreatorChallengeStatusScreenState();
}

class _CreatorChallengeStatusScreenState extends State<CreatorChallengeStatusScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  final _service = CreatorChallengesService();
  final _gatesService = CreatorGatesService();
  bool _loading = true;
  bool _acting = false;
  bool _sharing = false;
  Map<String, dynamic>? _challenge;
  List<String> _feedback = [];
  Map<String, dynamic>? _gateProgress;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final raw = await _service.fetchDraft(widget.challengeId);
    final challenge = raw != null ? normaliseCreatorChallenge(raw) : null;
    List<String> feedback = [];
    final status = challenge?['submissionStatus'] as String?;
    if (status == 'CHANGES_REQUESTED' || status == 'REJECTED') {
      final fb = await _service.fetchFeedback(widget.challengeId);
      feedback = (fb?['feedback'] as List?)?.cast<String>() ?? [];
    }
    Map<String, dynamic>? gateProgress;
    Map<String, dynamic> stats = {};
    if (status == 'LIVE' || status == 'PAUSED') {
      gateProgress = await _gatesService.fetchGateProgress(widget.challengeId);
      stats = await _service.fetchStats(widget.challengeId);
    }
    if (!mounted) return;
    setState(() {
      _challenge = challenge;
      _feedback = feedback;
      _gateProgress = gateProgress;
      _stats = stats;
      _loading = false;
    });
  }

  Future<void> _shareChallenge() async {
    setState(() => _sharing = true);
    try {
      final link = await _gatesService.fetchShareLink(widget.challengeId);
      final url = link?['shareUrl'] as String?;
      if (url == null) {
        _snack('Share link unavailable');
        return;
      }
      final title = (_challenge?['title'] as String?) ?? 'this challenge';
      await Share.share('Join "$title" on Aura Arena! $url');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _openPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatorChallengePreviewScreen(challengeId: widget.challengeId),
      ),
    );
  }

  Future<void> _editDraft() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CreatorChallengeDraftScreen(existingDraft: _challenge)),
    );
    if (updated == true) _load();
  }

  Future<void> _submitForReview() async {
    final rules = await _service.fetchSubmissionRules();
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (_) => _RulesDialog(rules: rules),
    );
    if (accepted != true) return;

    setState(() => _acting = true);
    try {
      await _service.submit(widget.challengeId);
      if (!mounted) return;
      _snack('Submitted for review');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _resubmit() async {
    setState(() => _acting = true);
    try {
      await _service.resubmit(widget.challengeId);
      if (!mounted) return;
      _snack('Resubmitted for review');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _publish() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Publish Challenge', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
            'This makes your challenge visible to all players and awards you the approved Aura Points. Continue?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Publish', style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _acting = true);
    try {
      final result = await _service.publish(widget.challengeId, notifyFollowers: true);
      if (!mounted) return;
      final aura = result['auraScore'] as int?;
      _snack(aura != null ? 'Challenge is live! +$aura Aura' : 'Challenge is live!');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _transitionStatus(String newStatus, {String? confirmTitle, String? confirmBody}) async {
    if (confirmTitle != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF12102A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(confirmTitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(confirmBody ?? '', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm', style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _acting = true);
    try {
      await _service.updateStatus(widget.challengeId, newStatus);
      if (!mounted) return;
      _snack('Updated');
      await _load();
    } catch (e) {
      if (!mounted) return;
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A0A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Challenge Status',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _challenge == null
              ? const Center(
                  child: Text('Challenge not found', style: TextStyle(color: Colors.white54)))
              : _buildBody(_challenge!),
    );
  }

  Widget _buildBody(Map<String, dynamic> c) {
    final title = c['title'] as String;
    final description = c['description'] as String;
    final categoryName = c['categoryName'] as String;
    final difficulty = c['difficulty'] as String;
    final status = c['submissionStatus'] as String;
    final auraScore = c['auraScore'] as int?;
    final adminFeedback = c['adminFeedback'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusBanner(status, auraScore),
          if (status == 'LIVE' || status == 'PAUSED') ...[
            const SizedBox(height: 16),
            _gateProgressCard(),
            const SizedBox(height: 12),
            _statsCard(),
          ],
          const SizedBox(height: 20),
          Text(title.isEmpty ? 'Untitled Challenge' : title,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(
            children: [
              if (categoryName.isNotEmpty) _pill(categoryName),
              if (difficulty.isNotEmpty) ...[const SizedBox(width: 8), _pill(difficulty)],
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(description, style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5)),
          ],

          if ((status == 'CHANGES_REQUESTED' || status == 'REJECTED') &&
              (_feedback.isNotEmpty || (adminFeedback ?? '').isNotEmpty)) ...[
            const SizedBox(height: 24),
            const Text('Admin Feedback',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if ((adminFeedback ?? '').isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Text(adminFeedback!, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
              ),
            ..._feedback.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle, color: Color(0xFFF59E0B), size: 6),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4))),
                    ],
                  ),
                )),
          ],

          const SizedBox(height: 32),
          ..._buildActions(status),
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      );

  Widget _statusBanner(String status, int? auraScore) {
    final meta = switch (status) {
      'DRAFT' => (Color(0xFF6B7280), 'Draft', 'Not visible to players yet. Finish setup and submit for review when ready.'),
      'PENDING_REVIEW' => (Color(0xFFF59E0B), 'In Review', 'An admin is reviewing your submission. You\'ll be notified once it\'s decided.'),
      'APPROVED' => (Color(0xFF22C55E), 'Approved', auraScore != null
          ? 'Approved for $auraScore Aura Points. Publish to make it live for players.'
          : 'Approved. Publish to make it live for players.'),
      'REJECTED' => (Color(0xFFEF4444), 'Rejected', 'This submission didn\'t meet the requirements. See feedback below.'),
      'CHANGES_REQUESTED' => (Color(0xFFF59E0B), 'Changes Requested', 'Address the feedback below, then resubmit.'),
      'ARCHIVED' => (Color(0xFF6B7280), 'Archived', 'This challenge has been archived.'),
      'LIVE' => (Color(0xFF7B2CBF), 'Live', 'Your challenge is live and visible to all players.'),
      'PAUSED' => (Color(0xFF64748B), 'Paused', 'Hidden from player feeds until resumed. Existing progress is preserved.'),
      _ => (Colors.white38, status, ''),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: meta.$1.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: meta.$1.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(meta.$2, style: TextStyle(color: meta.$1, fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(meta.$3, style: const TextStyle(color: Colors.white60, fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }

  Widget _gateProgressCard() {
    final g = _gateProgress;
    if (g == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Text('Gate progress unavailable', style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    final currentGate = g['currentGate'] as Map<String, dynamic>?;
    final participantCount = g['participantCount'] as int? ?? 0;
    final nextTarget = g['nextTarget'] as int?;
    final progressPct = ((g['progressPercentage'] as int?) ?? 0).clamp(0, 100);
    final completedGates = g['completedGates'] as int? ?? 0;
    final totalGates = g['totalGates'] as int? ?? 0;
    final totalRewardEarned = g['totalRewardEarned'] as int? ?? 0;
    final isAllGatesCompleted = g['isAllGatesCompleted'] as bool? ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isAllGatesCompleted
                      ? 'All gates unlocked!'
                      : (currentGate?['name'] as String? ?? 'Gate progress'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 14),
                  const SizedBox(width: 3),
                  Text('$totalRewardEarned',
                      style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progressPct / 100,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(_accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isAllGatesCompleted
                ? '$participantCount participants · $completedGates/$totalGates gates unlocked'
                : '$participantCount / ${nextTarget ?? '?'} participants · $completedGates/$totalGates gates unlocked',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _statsCard() {
    if (_stats.isEmpty) return const SizedBox.shrink();
    final participants = pickInt(_stats, ['totalParticipants', 'participantCount', 'participants']);
    final attempts = pickInt(_stats, ['totalAttempts', 'attemptsCount', 'attempts']);
    final passCount = pickInt(_stats, ['passCount', 'passed']);
    final failCount = pickInt(_stats, ['failCount', 'failed']);
    final auraDistributed = pickInt(_stats, ['auraDistributed', 'totalAuraDistributed', 'auraAwarded']);
    final views = pickInt(_stats, ['viewCount', 'views', 'totalViews']);

    Widget stat(String label, int value) => Expanded(
          child: Column(
            children: [
              Text('$value', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10.5), textAlign: TextAlign.center),
            ],
          ),
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          stat('Participants', participants),
          stat('Attempts', attempts),
          stat('Passed', passCount),
          stat('Failed', failCount),
          stat('Aura Given', auraDistributed),
          stat('Views', views),
        ],
      ),
    );
  }

  List<Widget> _buildActions(String status) {
    Widget button(String label, VoidCallback? onTap, {bool outline = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: outline
              ? OutlinedButton(
                  onPressed: (_acting || _sharing) ? null : onTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                )
              : ElevatedButton(
                  onPressed: (_acting || _sharing) ? null : onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: _accent.withValues(alpha: 0.5),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: (_acting || _sharing)
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
        ),
      );
    }

    switch (status) {
      case 'DRAFT':
        return [
          button('Submit for Review', _submitForReview),
          button('Preview', _openPreview, outline: true),
          button('Edit Draft', _editDraft, outline: true),
        ];
      case 'PENDING_REVIEW':
        return [
          button('Cancel Submission', () => _transitionStatus('DRAFT',
              confirmTitle: 'Cancel Submission',
              confirmBody: 'This returns the challenge to Draft so you can keep editing it. You\'ll need to resubmit when ready.'),
              outline: true),
        ];
      case 'CHANGES_REQUESTED':
        return [
          button('Resubmit for Review', _resubmit),
          button('Preview', _openPreview, outline: true),
          button('Edit Draft', _editDraft, outline: true),
        ];
      case 'APPROVED':
        return [button('Publish Challenge', _publish)];
      case 'LIVE':
      case 'PAUSED':
        return [
          if (status == 'PAUSED')
            button('Resume Challenge', () => _transitionStatus('LIVE')),
          button('View Participants', () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CreatorChallengeParticipantsScreen(challengeId: widget.challengeId))),
              outline: status == 'PAUSED'),
          button('Analytics', () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CreatorChallengeAnalyticsScreen(challengeId: widget.challengeId))),
              outline: true),
          button(_sharing ? 'Sharing…' : 'Share Challenge', _shareChallenge, outline: true),
          button('Reward History', () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CreatorGateHistoryScreen(challengeId: widget.challengeId))),
              outline: true),
          button('Gate Rules', () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreatorGateRulesScreen())),
              outline: true),
          if (status == 'LIVE')
            button('Pause Challenge', () => _transitionStatus('PAUSED',
                confirmTitle: 'Pause Challenge',
                confirmBody: 'This hides the challenge from player feeds until you resume it. Existing progress is preserved.'),
                outline: true),
        ];
      default:
        return [];
    }
  }
}

class _RulesDialog extends StatefulWidget {
  final List<Map<String, dynamic>> rules;
  const _RulesDialog({required this.rules});

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  static const _accent = Color(0xFF7B2CBF);
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF12102A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Submission Rules', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...widget.rules.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, color: _accent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['title'] as String? ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            if ((r['description'] as String?)?.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(r['description'] as String,
                                    style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.3)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: _accent,
              title: const Text('I acknowledge these rules',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: _accepted ? () => Navigator.pop(context, true) : null,
          child: Text('Submit', style: TextStyle(color: _accepted ? _accent : Colors.white24, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
