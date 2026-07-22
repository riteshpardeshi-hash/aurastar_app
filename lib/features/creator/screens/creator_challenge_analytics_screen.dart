import 'package:flutter/material.dart';
import '../../../core/services/creator_challenges_service.dart';
import '../widgets/creator_insights_chart.dart';

/// Tabs over the "Creator Challenges" analytics sub-suite (9 endpoints) plus
/// the base per-challenge analytics endpoint — all fully schema-documented
/// in Swagger, unlike most other Creator tags, so nothing here is a
/// best-guess field read.
class CreatorChallengeAnalyticsScreen extends StatefulWidget {
  final String challengeId;
  const CreatorChallengeAnalyticsScreen({super.key, required this.challengeId});

  @override
  State<CreatorChallengeAnalyticsScreen> createState() => _CreatorChallengeAnalyticsScreenState();
}

class _CreatorChallengeAnalyticsScreenState extends State<CreatorChallengeAnalyticsScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Analytics',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Participants'),
            Tab(text: 'Attempts'),
            Tab(text: 'Scores'),
            Tab(text: 'Engagement'),
            Tab(text: 'Shares & Followers'),
            Tab(text: 'Gates & Trends'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OverviewTab(challengeId: widget.challengeId),
          _ParticipantsTab(challengeId: widget.challengeId),
          _AttemptsTab(challengeId: widget.challengeId),
          _ScoresTab(challengeId: widget.challengeId),
          _EngagementTab(challengeId: widget.challengeId),
          _SharesFollowersTab(challengeId: widget.challengeId),
          _GatesTrendsTab(challengeId: widget.challengeId),
        ],
      ),
    );
  }
}

// ── Shared bits ──────────────────────────────────────────────────────────

const _card = Color(0xFF100A20);
const _accent = Color(0xFF7B2CBF);
const _dateRanges = ['today', '7d', '30d', '90d', 'year'];
const _dateRangeLabels = {'today': 'Today', '7d': '7D', '30d': '30D', '90d': '90D', 'year': 'Year'};

String _fmt(dynamic v) {
  if (v == null) return '—';
  if (v is num) return v == v.roundToDouble() ? '${v.toInt()}' : v.toStringAsFixed(1);
  return '$v';
}

String _pct(dynamic v) => v == null ? '—' : '${(v as num).toStringAsFixed(1)}%';

Widget _dateRangeChips(String current, ValueChanged<String> onChange) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: _dateRanges
          .map((r) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => onChange(r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: current == r ? _accent : _card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: current == r ? _accent : Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text(_dateRangeLabels[r]!,
                        style: TextStyle(
                            color: current == r ? Colors.white : Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ))
          .toList(),
    ),
  );
}

class _StatGrid extends StatelessWidget {
  final List<(String, String)> stats;
  const _StatGrid(this.stats);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: stats.map((s) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 32 - 10) / 2,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.$2,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(s.$1, style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(color: _accent));
}

// ── Overview ─────────────────────────────────────────────────────────────

class _OverviewTab extends StatefulWidget {
  final String challengeId;
  const _OverviewTab({required this.challengeId});

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  final _service = CreatorChallengesService();
  bool _loading = true;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _service.fetchAnalytics(widget.challengeId);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _Loading();
    final gateProgress = _data['gateProgress'] as Map<String, dynamic>?;
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _StatGrid([
            ('Views', _fmt(_data['views'])),
            ('Participants', _fmt(_data['participants'])),
            ('Total Attempts', _fmt(_data['totalAttempts'])),
            ('Likes', _fmt(_data['likes'])),
            ('Shares', _fmt(_data['shares'])),
            ('Saves', _fmt(_data['saves'])),
            ('Completion Rate', _pct(_data['completionRate'])),
            ('Average Score', _fmt(_data['averageScore'])),
            ('Aura Generated', _fmt(_data['auraPointsGenerated'])),
          ]),
          if (gateProgress != null) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Gate Progress'),
            _StatGrid([
              ('Current Participants', _fmt(gateProgress['currentParticipants'])),
              ('Gates Completed', _fmt(gateProgress['completedGates'])),
              ('Reward Earned', _fmt(gateProgress['totalRewardEarned'])),
              ('All Gates Done', (gateProgress['isAllGatesCompleted'] as bool? ?? false) ? 'Yes' : 'No'),
            ]),
          ],
        ],
      ),
    );
  }
}

// ── Participants ─────────────────────────────────────────────────────────

class _ParticipantsTab extends StatefulWidget {
  final String challengeId;
  const _ParticipantsTab({required this.challengeId});

  @override
  State<_ParticipantsTab> createState() => _ParticipantsTabState();
}

class _ParticipantsTabState extends State<_ParticipantsTab> {
  final _service = CreatorChallengesService();
  bool _loading = true;
  String _dateRange = '30d';
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _service.fetchParticipantAnalytics(widget.challengeId, dateRange: _dateRange);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _dateRangeChips(_dateRange, (r) {
          setState(() => _dateRange = r);
          _load();
        }),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.only(top: 60), child: _Loading())
        else
          _StatGrid([
            ('Total Participants', _fmt(_data['totalParticipants'])),
            ('New', _fmt(_data['newParticipants'])),
            ('Returning', _fmt(_data['returningParticipants'])),
            ('Active', _fmt(_data['activeParticipants'])),
            ('Daily', _fmt(_data['dailyParticipants'])),
            ('Weekly', _fmt(_data['weeklyParticipants'])),
            ('Monthly', _fmt(_data['monthlyParticipants'])),
            ('Eligible Target', _fmt(_data['totalEligibleParticipants'])),
          ]),
      ],
    );
  }
}

// ── Attempts ─────────────────────────────────────────────────────────────

class _AttemptsTab extends StatefulWidget {
  final String challengeId;
  const _AttemptsTab({required this.challengeId});

  @override
  State<_AttemptsTab> createState() => _AttemptsTabState();
}

class _AttemptsTabState extends State<_AttemptsTab> {
  final _service = CreatorChallengesService();
  bool _loading = true;
  String _dateRange = '30d';
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data =
        await _service.fetchAttemptAnalytics(widget.challengeId, dateRange: _dateRange, granularity: 'day');
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeSeries = (_data['timeSeries'] as List?)
        ?.map((e) => MapEntry(e['period'] as String, (e['attempts'] as num?) ?? 0))
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _dateRangeChips(_dateRange, (r) {
          setState(() => _dateRange = r);
          _load();
        }),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.only(top: 60), child: _Loading())
        else ...[
          _StatGrid([
            ('Total Attempts', _fmt(_data['totalAttempts'])),
            ('Unique Attempts', _fmt(_data['uniqueAttempts'])),
            ('Repeat Attempts', _fmt(_data['repeatAttempts'])),
            ('Avg / User', _fmt(_data['averageAttemptsPerUser'])),
            ('Successful', _fmt(_data['successfulAttempts'])),
            ('Failed', _fmt(_data['failedAttempts'])),
            ('Completion Rate', _pct(_data['completionRate'])),
            ('Drop-off Rate', _pct(_data['dropOffRate'])),
          ]),
          if (timeSeries != null && timeSeries.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Attempts Over Time'),
            CreatorInsightsChart(points: timeSeries),
          ],
        ],
      ],
    );
  }
}

// ── Scores ───────────────────────────────────────────────────────────────

class _ScoresTab extends StatefulWidget {
  final String challengeId;
  const _ScoresTab({required this.challengeId});

  @override
  State<_ScoresTab> createState() => _ScoresTabState();
}

class _ScoresTabState extends State<_ScoresTab> {
  final _service = CreatorChallengesService();
  bool _loading = true;
  String _dateRange = '30d';
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data =
        await _service.fetchScoreAnalytics(widget.challengeId, dateRange: _dateRange, granularity: 'day');
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final trend = (_data['trend'] as List?)
        ?.map((e) => MapEntry(e['period'] as String, (e['averageScore'] as num?) ?? 0))
        .toList();
    final distribution = (_data['distribution'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final top10 = (_data['top10'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _dateRangeChips(_dateRange, (r) {
          setState(() => _dateRange = r);
          _load();
        }),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.only(top: 60), child: _Loading())
        else ...[
          _StatGrid([
            ('Highest', _fmt(_data['highestScore'])),
            ('Lowest', _fmt(_data['lowestScore'])),
            ('Average', _fmt(_data['averageScore'])),
            ('Median', _fmt(_data['medianScore'])),
            ('AI Average', _fmt(_data['aiAverageScore'])),
            ('Final Challenge Score', _fmt(_data['finalChallengeScore'])),
          ]),
          if (trend != null && trend.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Average Score Trend'),
            CreatorInsightsChart(points: trend),
          ],
          if (distribution.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Score Distribution'),
            ...distribution.map((d) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      SizedBox(width: 70, child: Text(d['range'] as String? ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ((d['count'] as num?) ?? 0) /
                                (distribution.map((e) => (e['count'] as num?) ?? 0).reduce((a, b) => a > b ? a : b)).clamp(1, double.infinity),
                            minHeight: 14,
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            valueColor: const AlwaysStoppedAnimation(_accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${d['count']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                )),
          ],
          if (top10.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Top 10 Submissions'),
            ...top10.asMap().entries.map((entry) {
              final i = entry.key;
              final t = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w700))),
                    Expanded(
                      child: Text(t['userId'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ),
                    Text('${t['aiScore']}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    );
  }
}

// ── Engagement ───────────────────────────────────────────────────────────

class _EngagementTab extends StatefulWidget {
  final String challengeId;
  const _EngagementTab({required this.challengeId});

  @override
  State<_EngagementTab> createState() => _EngagementTabState();
}

class _EngagementTabState extends State<_EngagementTab> {
  final _service = CreatorChallengesService();
  bool _loading = true;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _service.fetchEngagementAnalytics(widget.challengeId);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _Loading();
    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _StatGrid([
            ('Total Views', _fmt(_data['totalViews'])),
            ('Unique Views', _fmt(_data['uniqueViews'])),
            ('Total Likes', _fmt(_data['totalLikes'])),
            ('Shares', _fmt(_data['shares'])),
            ('Saves', _fmt(_data['saves'])),
            ('Comments', _fmt(_data['comments'])),
            ('Avg Watch Time', _fmt(_data['averageWatchTime'])),
            ('Completion %', _pct(_data['completionPercentage'])),
          ]),
          const SizedBox(height: 12),
          const Text('Fields showing "—" aren\'t tracked by the backend yet (no per-viewer dedup, comment model, or watch-time logging).',
              style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.4)),
        ],
      ),
    );
  }
}

// ── Shares & Followers ──────────────────────────────────────────────────

class _SharesFollowersTab extends StatefulWidget {
  final String challengeId;
  const _SharesFollowersTab({required this.challengeId});

  @override
  State<_SharesFollowersTab> createState() => _SharesFollowersTabState();
}

class _SharesFollowersTabState extends State<_SharesFollowersTab> {
  final _service = CreatorChallengesService();
  bool _loading = true;
  String _dateRange = '30d';
  Map<String, dynamic> _shares = {};
  Map<String, dynamic> _followers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.fetchShareAnalytics(widget.challengeId),
      _service.fetchFollowerAnalytics(widget.challengeId, dateRange: _dateRange),
    ]);
    if (!mounted) return;
    setState(() {
      _shares = results[0];
      _followers = results[1];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final platforms = (_shares['platformDistribution'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        const _SectionTitle('Shares'),
        if (_loading)
          const Padding(padding: EdgeInsets.only(bottom: 20), child: _Loading())
        else ...[
          _StatGrid([
            ('Share Clicks', _fmt(_shares['totalShareClicks'])),
            ('QR Scans', _fmt(_shares['qrCodeScans'])),
          ]),
          if (platforms.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('No per-platform share tracking yet.',
                  style: TextStyle(color: Colors.white24, fontSize: 11.5)),
            )
          else
            ...platforms.map((p) => Text('${p['label']}: ${p['count']}',
                style: const TextStyle(color: Colors.white70, fontSize: 12))),
        ],
        const SizedBox(height: 24),
        const _SectionTitle('Followers'),
        _dateRangeChips(_dateRange, (r) {
          setState(() => _dateRange = r);
          _load();
        }),
        const SizedBox(height: 16),
        if (!_loading) ...[
          _StatGrid([
            ('New Followers', _fmt(_followers['newFollowers'])),
            ('Conversion Rate', _pct(_followers['followConversionRate'])),
            ('Profile Visits', _fmt(_followers['profileVisits'])),
            ('Challenge→Follow', _pct(_followers['challengeToFollowConversion'])),
            ('Returning', _fmt(_followers['returningFollowers'])),
            ('Unfollows', _fmt(_followers['unfollowCount'])),
          ]),
          const SizedBox(height: 10),
          const Text('New-follower count is creator-wide, not proven caused by this specific challenge — follows aren\'t attributed per-challenge in this schema.',
              style: TextStyle(color: Colors.white24, fontSize: 11, height: 1.4)),
        ],
      ],
    );
  }
}

// ── Gates & Trends ──────────────────────────────────────────────────────

class _GatesTrendsTab extends StatefulWidget {
  final String challengeId;
  const _GatesTrendsTab({required this.challengeId});

  @override
  State<_GatesTrendsTab> createState() => _GatesTrendsTabState();
}

class _GatesTrendsTabState extends State<_GatesTrendsTab> {
  final _service = CreatorChallengesService();
  bool _loading = true;
  String _dateRange = '30d';
  Map<String, dynamic> _gates = {};
  Map<String, dynamic> _trends = {};
  Map<String, dynamic> _comparison = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _service.fetchGateProgressAnalytics(widget.challengeId),
      _service.fetchTrendsAnalytics(widget.challengeId, dateRange: _dateRange, granularity: 'day'),
      _service.fetchComparisonAnalytics(widget.challengeId, dateRange: _dateRange),
    ]);
    if (!mounted) return;
    setState(() {
      _gates = results[0];
      _trends = results[1];
      _comparison = results[2];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final attemptsTrend = (_trends['attemptsTrend'] as List?)
        ?.map((e) => MapEntry(e['period'] as String, (e['value'] as num?) ?? 0))
        .toList();
    final participantsTrend = (_trends['participantsTrend'] as List?)
        ?.map((e) => MapEntry(e['period'] as String, (e['value'] as num?) ?? 0))
        .toList();
    final changePercent = _comparison['changePercent'] as Map<String, dynamic>? ?? {};

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        const _SectionTitle('Gate Progress'),
        if (_loading)
          const Padding(padding: EdgeInsets.only(bottom: 20), child: _Loading())
        else
          _StatGrid([
            ('Current Gate', _fmt(_gates['currentGate'])),
            ('Total Gates', _fmt(_gates['totalGates'])),
            ('Current Participants', _fmt(_gates['currentParticipants'])),
            ('Target Participants', _fmt(_gates['targetParticipants'])),
            ('Remaining', _fmt(_gates['remainingParticipants'])),
            ('Progress', _pct(_gates['progressPercentage'])),
            ('Reward Points', _fmt(_gates['rewardPoints'])),
            ('Next Gate Reward', _fmt(_gates['nextGateReward'])),
          ]),
        const SizedBox(height: 24),
        const _SectionTitle('Trends'),
        _dateRangeChips(_dateRange, (r) {
          setState(() => _dateRange = r);
          _load();
        }),
        const SizedBox(height: 16),
        if (!_loading) ...[
          if (attemptsTrend != null && attemptsTrend.isNotEmpty) ...[
            const Text('Attempts', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            CreatorInsightsChart(points: attemptsTrend),
            const SizedBox(height: 16),
          ],
          if (participantsTrend != null && participantsTrend.isNotEmpty) ...[
            const Text('Participants', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            CreatorInsightsChart(points: participantsTrend, color: const Color(0xFF22C55E)),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 8),
          const _SectionTitle('vs. Previous Period'),
          _StatGrid([
            ('Participants', _pctChange(changePercent['participants'])),
            ('Attempts', _pctChange(changePercent['attempts'])),
            ('Avg Score', _pctChange(changePercent['averageScore'])),
            ('New Followers', _pctChange(changePercent['newFollowers'])),
          ]),
        ],
      ],
    );
  }

  String _pctChange(dynamic v) {
    if (v == null) return '—';
    final n = (v as num).toDouble();
    return '${n >= 0 ? '+' : ''}${n.toStringAsFixed(1)}%';
  }
}
