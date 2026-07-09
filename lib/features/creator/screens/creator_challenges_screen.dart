import 'package:flutter/material.dart';
import '../../../core/services/creator_challenges_service.dart';
import 'creator_challenge_draft_screen.dart';
import 'creator_challenge_status_screen.dart';

class CreatorChallengesScreen extends StatefulWidget {
  const CreatorChallengesScreen({super.key});

  @override
  State<CreatorChallengesScreen> createState() => _CreatorChallengesScreenState();
}

class _CreatorChallengesScreenState extends State<CreatorChallengesScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  static const _allStatuses = [
    'DRAFT', 'PENDING_REVIEW', 'APPROVED', 'CHANGES_REQUESTED', 'REJECTED', 'LIVE', 'ARCHIVED',
  ];

  final _service = CreatorChallengesService();
  bool _loading = true;
  List<Map<String, dynamic>> _challenges = [];
  List<String> _statusOptions = _allStatuses;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _load();
  }

  Future<void> _loadFilters() async {
    final filters = await _service.fetchChallengeFilters();
    final statuses = pickField(filters, ['statuses', 'status', 'submissionStatuses']);
    if (!mounted || statuses is! List || statuses.isEmpty) return;
    setState(() => _statusOptions = statuses.map((e) => e.toString()).toList());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final raw = await _service.fetchMyChallenges(limit: 50, submissionStatus: _statusFilter);
    if (!mounted) return;
    setState(() {
      _challenges = raw.map(normaliseCreatorChallenge).toList();
      _loading = false;
    });
  }

  Future<void> _createNew() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreatorChallengeDraftScreen()),
    );
    if (created == true) _load();
  }

  Future<void> _openChallenge(String id) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreatorChallengeStatusScreen(challengeId: id)),
    );
    _load();
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

  Future<void> _archive(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF12102A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Archive Challenge', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
            'This hides the challenge from player feeds. Your data is preserved and this can be reviewed later.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.archive(id);
      _snack('Challenge archived');
      _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _duplicate(String id) async {
    try {
      await _service.duplicate(id);
      _snack('Duplicated as a new draft');
      _load();
    } catch (e) {
      _snack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('My Challenges',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNew,
        backgroundColor: _accent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Challenge', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _statusChip('All', _statusFilter == null, () {
                    setState(() => _statusFilter = null);
                    _load();
                  }),
                  ..._statusOptions.map((s) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _statusChip(_statusLabel(s), _statusFilter == s, () {
                          setState(() => _statusFilter = s);
                          _load();
                        }),
                      )),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _accent))
                : _challenges.isEmpty
                    ? _buildEmpty()
                    : RefreshIndicator(
                        color: _accent,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          itemCount: _challenges.length,
                          itemBuilder: (_, i) => _ChallengeCard(
                            challenge: _challenges[i],
                            onTap: () => _openChallenge(_challenges[i]['id'] as String),
                            onArchive: () => _archive(_challenges[i]['id'] as String),
                            onDuplicate: () => _duplicate(_challenges[i]['id'] as String),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String s) => switch (s) {
        'PENDING_REVIEW' => 'In Review',
        'CHANGES_REQUESTED' => 'Changes Requested',
        _ => s[0] + s.substring(1).toLowerCase(),
      };

  Widget _statusChip(String label, bool selected, VoidCallback onTap) {
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

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_outlined, color: Colors.white24, size: 52),
            const SizedBox(height: 16),
            const Text('No challenges yet',
                style: TextStyle(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Create your first challenge to start building your audience.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white30, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  final Map<String, dynamic> challenge;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onDuplicate;

  const _ChallengeCard({
    required this.challenge,
    required this.onTap,
    required this.onArchive,
    required this.onDuplicate,
  });

  static const _statusMeta = {
    'DRAFT': (Color(0xFF6B7280), Icons.edit_note_rounded, 'Draft'),
    'PENDING_REVIEW': (Color(0xFFF59E0B), Icons.hourglass_top_rounded, 'In Review'),
    'APPROVED': (Color(0xFF22C55E), Icons.check_circle_outline_rounded, 'Approved'),
    'REJECTED': (Color(0xFFEF4444), Icons.cancel_outlined, 'Rejected'),
    'CHANGES_REQUESTED': (Color(0xFFF59E0B), Icons.rate_review_outlined, 'Changes Requested'),
    'ARCHIVED': (Color(0xFF6B7280), Icons.archive_outlined, 'Archived'),
    'LIVE': (Color(0xFF7B2CBF), Icons.bolt_rounded, 'Live'),
  };

  @override
  Widget build(BuildContext context) {
    final title = challenge['title'] as String;
    final categoryName = challenge['categoryName'] as String;
    final status = challenge['submissionStatus'] as String;
    final auraScore = challenge['auraScore'] as int?;
    final meta = _statusMeta[status] ?? _statusMeta['DRAFT']!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF100A20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: meta.$1.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(meta.$2, color: meta.$1, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.isEmpty ? 'Untitled Challenge' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: meta.$1.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(meta.$3,
                            style: TextStyle(color: meta.$1, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                      if (categoryName.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(categoryName, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (auraScore != null) ...[
              const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 14),
              const SizedBox(width: 3),
              Text('$auraScore',
                  style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(width: 8),
            ],
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 20),
              color: const Color(0xFF12102A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              onSelected: (v) {
                if (v == 'archive') onArchive();
                if (v == 'duplicate') onDuplicate();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate', style: TextStyle(color: Colors.white)),
                ),
                if (status != 'ARCHIVED')
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive', style: TextStyle(color: Color(0xFFEF4444))),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
