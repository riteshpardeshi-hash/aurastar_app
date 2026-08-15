import 'package:flutter/material.dart';
import '../../../core/services/creator_account_service.dart';
import '../../../core/services/creator_challenges_service.dart' show pickField, pickInt, pickString;
import '../widgets/creator_insights_chart.dart';
import '../../../shared/theme/app_colors.dart';

class CreatorInsightsScreen extends StatefulWidget {
  const CreatorInsightsScreen({super.key});

  @override
  State<CreatorInsightsScreen> createState() => _CreatorInsightsScreenState();
}

class _CreatorInsightsScreenState extends State<CreatorInsightsScreen>
    with SingleTickerProviderStateMixin {
  static const _bg     = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
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
        title: const Text('Creator Insights'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textFaint,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Performance'),
            Tab(text: 'Top Challenges'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _OverviewTab(),
          _PerformanceTab(),
          _TopChallengesTab(),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab();

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  static const _accent = Color(0xFF7B2CBF);
  static const _card   = Color(0xFF100A20);

  bool _loading = true;
  Map<String, dynamic> _insights = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await CreatorAccountService().fetchInsights();
    if (!mounted) return;
    setState(() {
      _insights = data;
      _loading = false;
    });
  }

  int _int(Map? m, String key) => (m?[key] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    final overview = _insights['overview'] as Map<String, dynamic>?;
    final rewards = _insights['rewards'] as Map<String, dynamic>?;
    final gates = _insights['gates'] as Map<String, dynamic>?;
    final topChallenges = (_insights['topChallenges'] as List? ?? []).cast<Map<String, dynamic>>();

    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Overview',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                _stat('Total Challenges', _int(overview, 'totalChallenges'), Icons.flash_on, Colors.amber),
                _stat('Live Challenges', _int(overview, 'liveChallenges'), Icons.bolt_rounded, _accent),
                _stat('Approved', _int(overview, 'approvedChallenges'), Icons.check_circle_outline, Colors.green),
                _stat('Followers', _int(overview, 'followers'), Icons.people_rounded, Colors.blue),
                _stat('Following', _int(overview, 'following'), Icons.person_add_alt_1_rounded, Colors.teal),
                _stat('Participants', _int(overview, 'totalParticipants'), Icons.groups_rounded, Colors.purple),
                _stat('Total Stars', _int(overview, 'totalStars'), Icons.star_rounded, const Color(0xFFFFD700)),
                _stat('Avg / Challenge', _int(overview, 'avgParticipantsPerChallenge'), Icons.analytics_rounded, Colors.orange),
              ],
            ),

            const SizedBox(height: 24),
            const Text('Gate Rewards',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _stat('Total Reward Earned', _int(rewards, 'totalGateRewardEarned'), Icons.emoji_events_rounded, Colors.amber)),
                const SizedBox(width: 10),
                Expanded(child: _stat('Aura from Gates', _int(rewards, 'auraFromGates'), Icons.auto_awesome, const Color(0xFFFFD700))),
              ],
            ),
            const SizedBox(height: 10),
            _stat('Completed Gates', _int(rewards, 'totalCompletedGates'), Icons.verified_rounded, Colors.green),

            const SizedBox(height: 24),
            const Text('Gate Engagement',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            _stat('Participants Across Gates', _int(gates, 'totalParticipantsAcrossAllChallenges'), Icons.diversity_3_rounded, Colors.blue),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _stat('Challenges w/ Gates', _int(gates, 'challengesWithGateProgress'), Icons.stairs_rounded, Colors.indigo)),
                const SizedBox(width: 10),
                Expanded(child: _stat('Fully Completed', _int(gates, 'completedAllGates'), Icons.done_all_rounded, Colors.green)),
              ],
            ),

            if (topChallenges.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('Top Challenges',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ...topChallenges.map(_topChallengeTile),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topChallengeTile(Map<String, dynamic> c) {
    final title = c['title'] as String? ?? 'Challenge';
    final status = c['status'] as String? ?? '';
    final participants = (c['participants'] as num?)?.toInt() ?? 0;
    final stars = (c['stars'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                if (status.isNotEmpty)
                  Text(status, style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: Colors.white38, size: 14),
              const SizedBox(width: 3),
              Text('$participants', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(width: 10),
              const Icon(Icons.star_rounded, color: Color(0xFFFFD700), size: 14),
              const SizedBox(width: 3),
              Text('$stars', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PerformanceTab extends StatefulWidget {
  const _PerformanceTab();

  @override
  State<_PerformanceTab> createState() => _PerformanceTabState();
}

class _PerformanceTabState extends State<_PerformanceTab> {
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  static const _dateRanges = ['today', '7d', '30d', '90d', 'year'];
  static const _dateRangeLabels = {
    'today': 'Today', '7d': '7D', '30d': '30D', '90d': '90D', 'year': 'Year',
  };
  static const _metrics = [
    'views', 'participants', 'likes', 'shares', 'followers', 'auraEarned', 'rewardEarned', 'attempts',
  ];
  static const _metricLabels = {
    'views': 'Views',
    'participants': 'Participants',
    'likes': 'Likes',
    'shares': 'Shares',
    'followers': 'Followers',
    'auraEarned': 'Aura Earned',
    'rewardEarned': 'Reward Earned',
    'attempts': 'Attempts',
  };

  final _service = CreatorAccountService();
  bool _loading = true;
  String _dateRange = '30d';
  String _metric = 'views';
  List<String> _availableMetrics = _metrics;
  List<String> _availableDateRanges = _dateRanges;
  Map<String, dynamic> _overview = {};
  List<MapEntry<String, num>> _chartPoints = [];

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _load();
  }

  /// Narrows the chip lists if the backend restricts what's available for
  /// this creator; falls back to the full documented enum otherwise.
  Future<void> _loadFilters() async {
    final filters = await _service.fetchInsightsFilterOptions();
    final metrics = pickField(filters, ['metrics']);
    final dateRanges = pickField(filters, ['dateRanges', 'dateRange']);
    if (!mounted) return;
    setState(() {
      if (metrics is List && metrics.isNotEmpty) {
        _availableMetrics = metrics.map((e) => e.toString()).toList();
      }
      if (dateRanges is List && dateRanges.isNotEmpty) {
        _availableDateRanges = dateRanges.map((e) => e.toString()).toList();
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final overview = await _service.fetchPerformanceOverview(dateRange: _dateRange);
    final rawPoints = await _service.fetchInsightsChart(metric: _metric, dateRange: _dateRange);
    if (!mounted) return;
    setState(() {
      _overview = overview;
      _chartPoints = rawPoints.map((p) {
        final label = pickString(p, ['date', 'label', 'day', 'x']);
        final value = pickInt(p, ['value', 'count', 'y']);
        return MapEntry(label, value);
      }).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final views = pickInt(_overview, ['totalViews', 'views']);
    final participants = pickInt(_overview, ['totalParticipants', 'participants']);
    final aura = pickInt(_overview, ['totalAura', 'auraEarned', 'totalAuraEarned']);
    final followerGrowth = pickInt(_overview, ['followerGrowth', 'newFollowers']);
    final challengeCount = pickInt(_overview, ['challengeCount', 'totalChallenges']);

    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _chipRow(_availableDateRanges, (r) => _dateRangeLabels[r] ?? r, _dateRange, (r) {
            setState(() => _dateRange = r);
            _load();
          }),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator(color: _accent)),
            )
          else ...[
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.7,
              children: [
                _stat('Views', views, Icons.visibility_rounded, Colors.blue),
                _stat('Participants', participants, Icons.groups_rounded, Colors.purple),
                _stat('Aura Earned', aura, Icons.auto_awesome, const Color(0xFFFFD700)),
                _stat('New Followers', followerGrowth, Icons.person_add_alt_1_rounded, Colors.teal),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _stat('Active Challenges', challengeCount, Icons.flash_on, Colors.amber),
            ),
            const SizedBox(height: 24),
            Text(_metricLabels[_metric] ?? 'Metric',
                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _chipRow(_availableMetrics, (m) => _metricLabels[m] ?? m, _metric, (m) {
              setState(() => _metric = m);
              _load();
            }),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: CreatorInsightsChart(points: _chartPoints),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chipRow(List<String> values, String Function(String) labelOf, String selected,
      void Function(String) onSelect) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: values
            .map((v) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _chip(labelOf(v), selected == v, () => onSelect(v)),
                ))
            .toList(),
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
                color: selected ? Colors.white : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _stat(String label, int value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          CircleAvatar(radius: 16, backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$value', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopChallengesTab extends StatefulWidget {
  const _TopChallengesTab();

  @override
  State<_TopChallengesTab> createState() => _TopChallengesTabState();
}

class _TopChallengesTabState extends State<_TopChallengesTab> {
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  static const _sortOptions = {
    'most_viewed': 'Most Viewed',
    'most_participated': 'Most Participated',
    'most_liked': 'Most Liked',
    'most_shared': 'Most Shared',
    'highest_aura': 'Highest Aura',
    'highest_reward': 'Highest Reward',
    'newest': 'Newest',
    'oldest': 'Oldest',
  };
  static const _dateRanges = ['today', '7d', '30d', '90d', 'year'];
  static const _dateRangeLabels = {
    'today': 'Today', '7d': '7D', '30d': '30D', '90d': '90D', 'year': 'Year',
  };

  final _service = CreatorAccountService();
  bool _loading = true;
  bool _loadingMore = false;
  String _sort = 'most_viewed';
  String _dateRange = '30d';
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _service.fetchTopChallenges(sort: _sort, dateRange: _dateRange);
    if (!mounted) return;
    setState(() {
      _items = (res['items'] as List).cast<Map<String, dynamic>>();
      _page = res['page'] as int;
      _totalPages = res['totalPages'] as int;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    final res = await _service.fetchTopChallenges(sort: _sort, dateRange: _dateRange, page: _page + 1);
    if (!mounted) return;
    setState(() {
      _items.addAll((res['items'] as List).cast<Map<String, dynamic>>());
      _page = res['page'] as int;
      _totalPages = res['totalPages'] as int;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) _loadMore();
        return false;
      },
      child: RefreshIndicator(
        color: _accent,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _dateRanges
                    .map((r) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _chip(_dateRangeLabels[r]!, _dateRange == r, () {
                            setState(() => _dateRange = r);
                            _load();
                          }),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: PopupMenuButton<String>(
                color: const Color(0xFF12102A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (v) {
                  setState(() => _sort = v);
                  _load();
                },
                itemBuilder: (_) => _sortOptions.entries
                    .map((e) => PopupMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(color: Colors.white))))
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
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down_rounded, color: Colors.white54, size: 18),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(color: _accent)),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: Text('No challenges found', style: TextStyle(color: AppColors.textFaint, fontSize: 13))),
              )
            else
              ..._items.map(_tile),
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
                color: selected ? Colors.white : AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final title = pickString(c, ['title', 'name'], fallback: 'Challenge');
    final status = pickString(c, ['status', 'submissionStatus']);
    final views = pickInt(c, ['views', 'viewCount']);
    final participants = pickInt(c, ['participants', 'participantCount']);
    final aura = pickField(c, ['aura', 'auraEarned', 'reward', 'rewardEarned']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                if (status.isNotEmpty)
                  Text(status, style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility_rounded, color: Colors.white38, size: 13),
                  const SizedBox(width: 3),
                  Text('$views', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  const SizedBox(width: 8),
                  const Icon(Icons.groups_rounded, color: Colors.white38, size: 13),
                  const SizedBox(width: 3),
                  Text('$participants', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
              if (aura != null) ...[
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 12),
                    const SizedBox(width: 3),
                    Text('$aura', style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
