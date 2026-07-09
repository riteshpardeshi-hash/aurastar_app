import 'package:flutter/material.dart';
import '../../../core/services/creator_challenges_service.dart';

class CreatorChallengeParticipantDetailScreen extends StatefulWidget {
  final String challengeId;
  final String playerId;
  final String? playerName;

  const CreatorChallengeParticipantDetailScreen({
    super.key,
    required this.challengeId,
    required this.playerId,
    this.playerName,
  });

  @override
  State<CreatorChallengeParticipantDetailScreen> createState() =>
      _CreatorChallengeParticipantDetailScreenState();
}

class _CreatorChallengeParticipantDetailScreenState
    extends State<CreatorChallengeParticipantDetailScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  final _service = CreatorChallengesService();
  bool _loading = true;
  bool _loadingMore = false;
  Map<String, dynamic> _detail = {};
  List<Map<String, dynamic>> _attempts = [];
  int _page = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final detail = await _service.fetchParticipantDetail(widget.challengeId, widget.playerId);
    final attempts = await _service.fetchParticipantAttempts(widget.challengeId, widget.playerId);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _attempts = (attempts['items'] as List).cast<Map<String, dynamic>>();
      _page = attempts['page'] as int;
      _totalPages = attempts['totalPages'] as int;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    final next = await _service.fetchParticipantAttempts(
        widget.challengeId, widget.playerId, page: _page + 1);
    if (!mounted) return;
    setState(() {
      _attempts.addAll((next['items'] as List).cast<Map<String, dynamic>>());
      _page = next['page'] as int;
      _totalPages = next['totalPages'] as int;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = pickString(_detail, ['name', 'displayName', 'username'],
        fallback: widget.playerName ?? 'Participant');
    final avatar = pickString(_detail, ['avatar', 'avatarUrl', 'photoUrl', 'profileImage']);
    final attemptsCount = pickInt(_detail, ['attemptsCount', 'totalAttempts', 'attempts']);
    final bestScore = pickField(_detail, ['bestScore', 'highestScore', 'aura', 'auraEarned']);
    final verdict = pickString(_detail, ['verdict', 'status'], fallback: '');

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(name.isEmpty ? 'Participant' : name,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) _loadMore();
                return false;
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: _accent.withValues(alpha: 0.2),
                          backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                          child: avatar.isEmpty
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                              : null,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                              const SizedBox(height: 4),
                              Text('$attemptsCount attempts${verdict.isNotEmpty ? ' · $verdict' : ''}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (bestScore != null) ...[
                          const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 16),
                          const SizedBox(width: 3),
                          Text('$bestScore',
                              style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Attempts',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  if (_attempts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Center(
                          child: Text('No attempts found', style: TextStyle(color: Colors.white38, fontSize: 13))),
                    )
                  else
                    ..._attempts.map(_attemptTile),
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _attemptTile(Map<String, dynamic> a) {
    final status = pickString(a, ['verdict', 'status'], fallback: '');
    final score = pickField(a, ['score', 'aiScore']);
    final submittedAt = pickString(a, ['createdAt', 'submittedAt']);

    final statusColor = switch (status.toUpperCase()) {
      'PASS' || 'APPROVED' => const Color(0xFF22C55E),
      'FAIL' || 'REJECTED' => const Color(0xFFEF4444),
      _ => const Color(0xFFF59E0B),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.isEmpty ? 'Attempt' : status,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 13)),
                if (submittedAt.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(_formatDate(submittedAt), style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
                ],
              ],
            ),
          ),
          if (score != null)
            Text('$score', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
