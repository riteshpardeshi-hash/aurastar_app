import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../challenges/screens/challenge_detail.dart';
import '../explore/screens/creator_profile_screen.dart';
import '../explore/screens/participant_profile_screen.dart';

// ── Result model ──────────────────────────────────────────────────────────────

enum _Type { challenge, brand, user, category }

class _Result {
  final _Type type;
  final String id;
  final Map<String, dynamic> data;
  _Result(this.type, this.id, this.data);
}

// ── Categories ────────────────────────────────────────────────────────────────

const _kCategories = ['Dance', 'Fitness', 'Fashion', 'Sports', 'Comedy', 'Skill'];

// ── Screen ────────────────────────────────────────────────────────────────────

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  static const _bg    = Color(0xFF000000);
  static const _card  = Color(0xFF0E0E1A);
  static const _accent = Color(0xFF7B2CBF);
  static const _prefsKey = 'search_recent';

  final _ctrl = TextEditingController();
  late final TabController _tabCtrl;

  List<String> _recent = [];
  Map<_Type, List<_Result>> _results = {};
  bool _loading = false;
  bool _searched = false;

  static const _tabs = ['All', 'Challenges', 'Brands', 'Users', 'Categories'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _loadRecent();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Recent searches ───────────────────────────────────────────────────────

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _recent = prefs.getStringList(_prefsKey) ?? []);
  }

  Future<void> _saveRecent(String term) async {
    final updated = [term, ..._recent.where((r) => r != term)].take(6).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, updated);
    if (mounted) setState(() => _recent = updated);
  }

  Future<void> _removeRecent(String term) async {
    final updated = _recent.where((r) => r != term).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, updated);
    if (mounted) setState(() => _recent = updated);
  }

  // ── Search logic ──────────────────────────────────────────────────────────

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() { _results = {}; _searched = false; });
      return;
    }

    setState(() { _loading = true; _searched = true; });
    _saveRecent(q);

    final end = '$q';

    try {
      final futures = await Future.wait([
        // Challenges
        FirebaseFirestore.instance
            .collection('challenges')
            .where('status', isEqualTo: 'approved')
            .where('title', isGreaterThanOrEqualTo: q)
            .where('title', isLessThanOrEqualTo: end)
            .limit(10)
            .get(),
        // Brands (isCreator users) — search by pageName
        FirebaseFirestore.instance
            .collection('users')
            .where('isCreator', isEqualTo: true)
            .where('pageName', isGreaterThanOrEqualTo: q)
            .where('pageName', isLessThanOrEqualTo: end)
            .limit(8)
            .get(),
        // Users — search by username
        FirebaseFirestore.instance
            .collection('users')
            .where('username', isGreaterThanOrEqualTo: q)
            .where('username', isLessThanOrEqualTo: end)
            .limit(8)
            .get(),
      ]);

      final challenges = futures[0].docs
          .map((d) => _Result(_Type.challenge, d.id, d.data()))
          .toList();

      final brands = futures[1].docs
          .map((d) => _Result(_Type.brand, d.id, d.data()))
          .toList();

      // Users: exclude creators to avoid duplicates
      final users = futures[2].docs
          .where((d) {
            final data = d.data();
            return data['isCreator'] != true && data['isAdmin'] != true;
          })
          .map((d) => _Result(_Type.user, d.id, d.data()))
          .toList();

      final matchedCategories = _kCategories
          .where((c) => c.toLowerCase().startsWith(q.toLowerCase()))
          .map((c) => _Result(_Type.category, c, {'name': c}))
          .toList();

      if (!mounted) return;
      setState(() {
        _results = {
          _Type.challenge: challenges,
          _Type.brand: brands,
          _Type.user: users,
          _Type.category: matchedCategories,
        };
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clear() {
    _ctrl.clear();
    setState(() { _results = {}; _searched = false; });
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _openResult(BuildContext context, _Result r) {
    switch (r.type) {
      case _Type.challenge:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            title: r.data['title'] as String? ?? '',
            instructions: r.data['instructions'] as String? ?? '',
            videoUrl: r.data['videoUrl'] as String? ?? '',
            challengeId: r.id,
          ),
        ));
      case _Type.brand:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => CreatorProfileScreen(creatorId: r.id),
        ));
      case _Type.user:
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => ParticipantProfileScreen(userId: r.id),
        ));
      case _Type.category:
        _ctrl.text = r.data['name'] as String;
        _search(_ctrl.text);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Container(
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            cursorColor: _accent,
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            onChanged: (v) {
              if (v.isEmpty) setState(() { _results = {}; _searched = false; });
            },
            decoration: InputDecoration(
              hintText: 'Search Aura Arena…',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.30), fontSize: 15),
              prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withValues(alpha: 0.40), size: 20),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: Colors.white.withValues(alpha: 0.40), size: 18),
                      onPressed: _clear,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: _accent,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            dividerColor: Colors.white10,
            tabs: _tabs.map((t) => Tab(text: t)).toList(),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : TabBarView(
              controller: _tabCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _searched ? _buildAllResults() : _buildSuggestions(),
                _searched ? _buildTypeList(_Type.challenge) : _buildSuggestions(),
                _searched ? _buildTypeList(_Type.brand) : _buildSuggestions(),
                _searched ? _buildTypeList(_Type.user) : _buildSuggestions(),
                _buildCategoriesTab(),
              ],
            ),
    );
  }

  // ── Suggestions (pre-search) ──────────────────────────────────────────────

  Widget _buildSuggestions() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        if (_recent.isNotEmpty) ...[
          Row(
            children: [
              const Text('Recent', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove(_prefsKey);
                  if (mounted) setState(() => _recent = []);
                },
                child: const Text('Clear all', style: TextStyle(color: Color(0xFF9B4DCA), fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...(_recent.map((term) => _recentTile(term))),
          const SizedBox(height: 20),
        ],
        const Text('Browse categories', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        const SizedBox(height: 12),
        _buildCategoryChips(),
        const SizedBox(height: 20),
        const Text('Try searching for', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Ramp Walk', 'Dance', 'Yoga', 'Fashion', 'Flip']
              .map((tag) => GestureDetector(
                    onTap: () { _ctrl.text = tag; _search(tag); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _accent.withValues(alpha: 0.30)),
                      ),
                      child: Text(tag, style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 13)),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _recentTile(String term) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.history_rounded, color: Colors.white30, size: 18),
        title: Text(term, style: const TextStyle(color: Colors.white70, fontSize: 14)),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.white24, size: 16),
          onPressed: () => _removeRecent(term),
        ),
        onTap: () { _ctrl.text = term; _search(term); },
      ),
    );
  }

  Widget _buildCategoryChips() {
    final colors = [
      const Color(0xFF4B6EF6),
      const Color(0xFFFF6B9D),
      Colors.greenAccent,
      Colors.orange,
      const Color(0xFFFFD700),
      const Color(0xFF06B6D4),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_kCategories.length, (i) {
        final c = colors[i % colors.length];
        return GestureDetector(
          onTap: () { _ctrl.text = _kCategories[i]; _search(_kCategories[i]); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.withValues(alpha: 0.35)),
            ),
            child: Text(_kCategories[i], style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        );
      }),
    );
  }

  // ── All results (grouped) ─────────────────────────────────────────────────

  Widget _buildAllResults() {
    final allEmpty = _results.values.every((l) => l.isEmpty);
    if (allEmpty) return _buildEmpty();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if ((_results[_Type.challenge] ?? []).isNotEmpty) ...[
          _sectionHeader('Challenges', _results[_Type.challenge]!.length),
          ...(_results[_Type.challenge]!.map((r) => _challengeTile(r))),
          const SizedBox(height: 16),
        ],
        if ((_results[_Type.brand] ?? []).isNotEmpty) ...[
          _sectionHeader('Brands', _results[_Type.brand]!.length),
          ...(_results[_Type.brand]!.map((r) => _brandTile(r))),
          const SizedBox(height: 16),
        ],
        if ((_results[_Type.user] ?? []).isNotEmpty) ...[
          _sectionHeader('Users', _results[_Type.user]!.length),
          ...(_results[_Type.user]!.map((r) => _userTile(r))),
          const SizedBox(height: 16),
        ],
        if ((_results[_Type.category] ?? []).isNotEmpty) ...[
          _sectionHeader('Categories', _results[_Type.category]!.length),
          ...(_results[_Type.category]!.map((r) => _categoryTile(r))),
        ],
      ],
    );
  }

  // ── Per-type list ─────────────────────────────────────────────────────────

  Widget _buildTypeList(_Type type) {
    final list = _results[type] ?? [];
    if (list.isEmpty) return _buildEmpty();
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _tileFor(list[i]),
    );
  }

  Widget _tileFor(_Result r) {
    switch (r.type) {
      case _Type.challenge: return _challengeTile(r);
      case _Type.brand:     return _brandTile(r);
      case _Type.user:      return _userTile(r);
      case _Type.category:  return _categoryTile(r);
    }
  }

  // ── Categories tab ────────────────────────────────────────────────────────

  Widget _buildCategoriesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        const Text('All Categories', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        const SizedBox(height: 14),
        ..._kCategories.map((cat) {
          final r = _Result(_Type.category, cat, {'name': cat});
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _categoryTile(r),
          );
        }),
      ],
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _sectionHeader(String label, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count', style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // ── Tile builders ─────────────────────────────────────────────────────────

  Widget _challengeTile(_Result r) {
    final aura = (r.data['auraPoints'] as num?)?.toInt() ?? 0;
    final category = r.data['category'] as String? ?? '';
    final isSystem = (r.data['creatorId'] as String? ?? '') == 'system';
    return _baseTile(
      onTap: () => _openResult(context, r),
      icon: isSystem ? Icons.auto_awesome_rounded : Icons.store_outlined,
      iconColor: _accent,
      title: r.data['title'] as String? ?? 'Challenge',
      subtitle: category.isNotEmpty ? category : (isSystem ? 'Aura Arena' : 'Brand Challenge'),
      trailing: aura > 0
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.diamond, color: Color(0xFF7B2CBF), size: 13),
              const SizedBox(width: 3),
              Text('$aura', style: const TextStyle(color: Color(0xFFD4A8FF), fontSize: 13, fontWeight: FontWeight.w700)),
            ])
          : null,
    );
  }

  Widget _brandTile(_Result r) {
    final pageName = r.data['pageName'] as String? ?? r.data['name'] as String? ?? 'Brand';
    final followers = (r.data['followerCount'] as num?)?.toInt() ?? 0;
    return _baseTile(
      onTap: () => _openResult(context, r),
      icon: Icons.store_rounded,
      iconColor: const Color(0xFF4B6EF6),
      title: pageName,
      subtitle: followers > 0 ? '${_fmt(followers)} followers' : 'Brand',
      badge: 'Brand',
      badgeColor: const Color(0xFF4B6EF6),
    );
  }

  Widget _userTile(_Result r) {
    final username = r.data['username'] as String? ?? 'user';
    final aura = (r.data['totalRewards'] as num?)?.toInt() ?? 0;
    return _baseTile(
      onTap: () => _openResult(context, r),
      icon: Icons.person_outline_rounded,
      iconColor: const Color(0xFFFF6B9D),
      title: '@$username',
      subtitle: aura > 0 ? '${_fmt(aura)} Aura' : 'Player',
    );
  }

  Widget _categoryTile(_Result r) {
    final name = r.data['name'] as String? ?? '';
    final colorMap = {
      'Dance': const Color(0xFF4B6EF6),
      'Fitness': Colors.greenAccent,
      'Fashion': const Color(0xFFFF6B9D),
      'Sports': Colors.orange,
      'Comedy': const Color(0xFFFFD700),
      'Skill': const Color(0xFF06B6D4),
    };
    final c = colorMap[name] ?? _accent;
    return _baseTile(
      onTap: () => _openResult(context, r),
      icon: Icons.category_outlined,
      iconColor: c,
      title: name,
      subtitle: 'Browse $name challenges',
      badge: 'Category',
      badgeColor: c,
    );
  }

  Widget _baseTile({
    required VoidCallback onTap,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    String? badge,
    Color? badgeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(child: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 12))),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? _accent).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(badge, style: TextStyle(color: badgeColor ?? _accent, fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.white24, size: 52),
          const SizedBox(height: 14),
          const Text('No results found', style: TextStyle(color: Colors.white38, fontSize: 15)),
          const SizedBox(height: 6),
          Text('Try a different search term', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12)),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
    return '$n';
  }
}
