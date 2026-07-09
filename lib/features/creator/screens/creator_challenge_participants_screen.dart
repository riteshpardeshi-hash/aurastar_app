import 'package:flutter/material.dart';
import '../../../core/services/creator_challenges_service.dart';
import 'creator_challenge_participant_detail_screen.dart';

class CreatorChallengeParticipantsScreen extends StatefulWidget {
  final String challengeId;
  const CreatorChallengeParticipantsScreen({super.key, required this.challengeId});

  @override
  State<CreatorChallengeParticipantsScreen> createState() =>
      _CreatorChallengeParticipantsScreenState();
}

class _CreatorChallengeParticipantsScreenState extends State<CreatorChallengeParticipantsScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  static const _statusOptions = ['ALL', 'PASS', 'FAIL', 'PENDING'];
  static const _sortOptions = {
    'latest_attempt': 'Latest attempt',
    'oldest_attempt': 'Oldest attempt',
    'most_attempts': 'Most attempts',
    'least_attempts': 'Least attempts',
    'highest_aura': 'Highest aura',
    'alphabetical': 'A–Z',
  };

  final _service = CreatorChallengesService();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _loadingMore = false;
  Map<String, dynamic> _summary = {};
  List<Map<String, dynamic>> _participants = [];
  int _page = 1;
  int _totalPages = 1;
  String _status = 'ALL';
  String _sort = 'latest_attempt';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summary = await _service.fetchParticipantsSummary(widget.challengeId);
    final list = await _service.fetchParticipants(
      widget.challengeId,
      status: _status == 'ALL' ? null : _status,
      sort: _sort,
      search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _summary = summary;
      _participants = (list['items'] as List).cast<Map<String, dynamic>>();
      _page = list['page'] as int;
      _totalPages = list['totalPages'] as int;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    final next = await _service.fetchParticipants(
      widget.challengeId,
      page: _page + 1,
      status: _status == 'ALL' ? null : _status,
      sort: _sort,
      search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
    );
    if (!mounted) return;
    setState(() {
      _participants.addAll((next['items'] as List).cast<Map<String, dynamic>>());
      _page = next['page'] as int;
      _totalPages = next['totalPages'] as int;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = pickInt(_summary, ['totalCount', 'totalParticipants', 'total']);
    final pass = pickInt(_summary, ['passCount', 'passed']);
    final fail = pickInt(_summary, ['failCount', 'failed']);
    final pending = pickInt(_summary, ['pendingCount', 'pending']);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Participants',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) _loadMore();
                return false;
              },
              child: RefreshIndicator(
                color: _accent,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _summaryTile('Total', '$total')),
                        const SizedBox(width: 8),
                        Expanded(child: _summaryTile('Passed', '$pass', color: const Color(0xFF22C55E))),
                        const SizedBox(width: 8),
                        Expanded(child: _summaryTile('Failed', '$fail', color: const Color(0xFFEF4444))),
                        const SizedBox(width: 8),
                        Expanded(child: _summaryTile('Pending', '$pending', color: const Color(0xFFF59E0B))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white),
                      onSubmitted: (_) => _load(),
                      decoration: InputDecoration(
                        hintText: 'Search participants',
                        hintStyle: const TextStyle(color: Colors.white38),
                        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                        filled: true,
                        fillColor: _card,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ..._statusOptions.map((s) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _chip(s, _status == s, () {
                                  setState(() => _status = s);
                                  _load();
                                }),
                              )),
                          const SizedBox(width: 8),
                          PopupMenuButton<String>(
                            color: const Color(0xFF12102A),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            onSelected: (v) {
                              setState(() => _sort = v);
                              _load();
                            },
                            itemBuilder: (_) => _sortOptions.entries
                                .map((e) => PopupMenuItem(
                                    value: e.key,
                                    child: Text(e.value, style: const TextStyle(color: Colors.white))))
                                .toList(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: _card,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_sortOptions[_sort] ?? 'Sort',
                                      style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.arrow_drop_down_rounded, color: Colors.white54, size: 18),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_participants.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(
                            child: Text('No participants found', style: TextStyle(color: Colors.white38, fontSize: 13))),
                      )
                    else
                      ..._participants.map(_participantTile),
                    if (_loadingMore)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Center(child: CircularProgressIndicator(color: _accent, strokeWidth: 2)),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _summaryTile(String label, String value, {Color color = Colors.white}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _accent : _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _accent : Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _participantTile(Map<String, dynamic> p) {
    final id = pickString(p, ['playerId', 'userId', '_id', 'id']);
    final name = pickString(p, ['name', 'displayName', 'username'], fallback: 'Participant');
    final avatar = pickString(p, ['avatar', 'avatarUrl', 'photoUrl', 'profileImage']);
    final attemptsCount = pickInt(p, ['attemptsCount', 'attempts', 'totalAttempts']);
    final verdict = pickString(p, ['verdict', 'status'], fallback: '');
    final aura = pickField(p, ['aura', 'auraEarned', 'bestScore']);

    final statusColor = switch (verdict.toUpperCase()) {
      'PASS' => const Color(0xFF22C55E),
      'FAIL' => const Color(0xFFEF4444),
      _ => const Color(0xFFF59E0B),
    };

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreatorChallengeParticipantDetailScreen(
            challengeId: widget.challengeId,
            playerId: id,
            playerName: name,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _accent.withValues(alpha: 0.2),
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (verdict.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(verdict,
                              style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      if (verdict.isNotEmpty) const SizedBox(width: 6),
                      Text('$attemptsCount attempts', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            if (aura != null) ...[
              const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 14),
              const SizedBox(width: 3),
              Text('$aura', style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ],
        ),
      ),
    );
  }
}
