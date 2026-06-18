import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../challenges/screens/challenge_detail.dart';
import '../challenges/screens/category_challenges_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);
  static const _surface = Color(0xFF12122A);

  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';
  String _filter = 'All';
  List<_RecentItem> _recent = [];
  List<QueryDocumentSnapshot> _results = [];
  bool _searching = false;

  static const _filters = ['All', 'Challenges', 'Brands', 'Creators'];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('recent_search_items') ?? [];
    setState(() {
      _recent = raw
          .map((s) {
            try {
              return _RecentItem.fromJson(
                  jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<_RecentItem>()
          .toList();
    });
  }

  Future<void> _saveRecent(_RecentItem item) async {
    final updated = [item, ..._recent.where((r) => r.id != item.id)]
        .take(20)
        .toList();
    setState(() => _recent = updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_search_items',
        updated.map((r) => jsonEncode(r.toJson())).toList());
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_search_items');
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final qLower = q.toLowerCase();
    final db = FirebaseFirestore.instance;
    final List<QueryDocumentSnapshot> docs = [];

    if (_filter == 'All' || _filter == 'Challenges') {
      final snap = await db.collection('challenges').limit(20).get();
      docs.addAll(snap.docs.where((d) {
        final t = (d['title'] as String? ?? '').toLowerCase();
        return t.contains(qLower);
      }));
    }
    if (_filter == 'All' || _filter == 'Brands') {
      final snap = await db
          .collection('users')
          .where('isCreator', isEqualTo: true)
          .limit(20)
          .get();
      docs.addAll(snap.docs.where((d) {
        final n = (d['name'] as String? ?? '').toLowerCase();
        final u = (d['username'] as String? ?? '').toLowerCase();
        return n.contains(qLower) || u.contains(qLower);
      }));
    }
    if (_filter == 'All' || _filter == 'Creators') {
      final snap = await db.collection('users').limit(20).get();
      docs.addAll(snap.docs.where((d) {
        final n = (d['name'] as String? ?? '').toLowerCase();
        final u = (d['username'] as String? ?? '').toLowerCase();
        return n.contains(qLower) || u.contains(qLower);
      }));
    }

    setState(() {
      _results = docs;
      _searching = false;
    });
  }

  void _onResultTap(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final isChallenge =
        data.containsKey('videoUrl') && data.containsKey('title');
    final isUser =
        data.containsKey('name') && data.containsKey('username');
    final isBrand = isUser && (data['isCreator'] == true);

    final item = _RecentItem(
      id: doc.id,
      type: isChallenge ? 'Challenge' : isBrand ? 'Brand' : 'Creator',
      title: isChallenge
          ? data['title'] as String? ?? ''
          : data['name'] as String? ?? '',
      subtitle: isChallenge
          ? '${data['auraPoints'] ?? 0} Aura'
          : '@${data['username'] ?? ''}',
      imageUrl: isChallenge
          ? data['thumbnailUrl'] as String? ?? ''
          : data['profileImageUrl'] as String? ?? '',
    );
    _saveRecent(item);

    if (isChallenge) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            title: data['title'] as String? ?? '',
            instructions: data['instructions'] as String? ?? '',
            videoUrl: data['videoUrl'] as String? ?? '',
            challengeId: doc.id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 18, 18, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const Text(
                    'Search',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'ClashDisplay',
                    ),
                  ),
                ],
              ),
            ),
            _buildSearchBar(),
            _buildFilterPills(),
            Expanded(
              child: _query.isEmpty ? _buildRecent() : _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search bar ─────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 14),
            child: Icon(Icons.search_rounded,
                color: Colors.white54, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontFamily: 'SpaceGrotesk'),
              decoration: InputDecoration(
                hintText: 'Search challenges, brands, creators...',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 15,
                    fontFamily: 'SpaceGrotesk'),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
              ),
              onChanged: (v) {
                setState(() => _query = v);
                _search(v);
              },
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                setState(() {
                  _query = '';
                  _results = [];
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.50),
                    size: 18),
              ),
            ),
        ],
      ),
    );
  }

  // ── Filter pills ───────────────────────────────────────────────────────────
  Widget _buildFilterPills() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(
        children: _filters.map((f) {
          final active = f == _filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _filter = f);
                if (_query.isNotEmpty) _search(_query);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active
                        ? _accent
                        : Colors.white.withValues(alpha: 0.20),
                  ),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white60,
                    fontSize: 13,
                    fontWeight: active
                        ? FontWeight.w700
                        : FontWeight.w500,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Recent section ─────────────────────────────────────────────────────────
  Widget _buildRecent() {
    if (_recent.isEmpty) {
      return Center(
        child: Text(
          'Start typing to search',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.30),
              fontSize: 15,
              fontFamily: 'SpaceGrotesk'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Recent',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'ClashDisplay')),
            GestureDetector(
              onTap: _clearRecent,
              child: const Text('Clear all',
                  style: TextStyle(
                      color: Color(0xFF9B4DCA),
                      fontSize: 13,
                      fontFamily: 'SpaceGrotesk')),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._recent.map((item) => _RecentRow(
              item: item,
              onTap: () => _openRecentItem(item),
            )),
      ],
    );
  }

  void _openRecentItem(_RecentItem item) {
    if (item.type == 'Challenge') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            title: item.title,
            instructions: item.subtitle,
            videoUrl: item.imageUrl,
            challengeId: item.id,
          ),
        ),
      );
    } else if (item.type == 'Category') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CategoryChallengesScreen(category: item.title),
        ),
      );
    }
  }

  // ── Results section ────────────────────────────────────────────────────────
  Widget _buildResults() {
    if (_searching) {
      return const Center(
          child: CircularProgressIndicator(color: _accent));
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No results for "$_query"',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.40),
              fontFamily: 'SpaceGrotesk'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final doc = _results[i];
        final data = doc.data() as Map<String, dynamic>;
        final isChallenge =
            data.containsKey('videoUrl') && data.containsKey('title');
        final isUser =
            data.containsKey('name') && data.containsKey('username');
        final isBrand = isUser && (data['isCreator'] == true);

        final type = isChallenge
            ? 'Challenge'
            : isBrand
                ? 'Brand'
                : 'Creator';
        final title = isChallenge
            ? data['title'] as String? ?? ''
            : data['name'] as String? ?? '';
        final subtitle = isChallenge
            ? '${data['auraPoints'] ?? 0} Aura'
            : '@${data['username'] ?? ''}';
        final imageUrl = isChallenge
            ? data['thumbnailUrl'] as String? ?? ''
            : data['profileImageUrl'] as String? ?? '';

        final item = _RecentItem(
            id: doc.id,
            type: type,
            title: title,
            subtitle: subtitle,
            imageUrl: imageUrl);

        return _RecentRow(
          item: item,
          onTap: () => _onResultTap(doc),
        );
      },
    );
  }
}

// ── Recent item model ──────────────────────────────────────────────────────────
class _RecentItem {
  final String id, type, title, subtitle, imageUrl;
  const _RecentItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
  });

  factory _RecentItem.fromJson(Map<String, dynamic> j) => _RecentItem(
        id: j['id'] as String? ?? '',
        type: j['type'] as String? ?? '',
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        imageUrl: j['imageUrl'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'subtitle': subtitle,
        'imageUrl': imageUrl,
      };
}

// ── Recent row widget ─────────────────────────────────────────────────────────
class _RecentRow extends StatelessWidget {
  final _RecentItem item;
  final VoidCallback onTap;

  const _RecentRow({required this.item, required this.onTap});

  Color get _badgeColor {
    switch (item.type) {
      case 'Challenge':
        return const Color(0xFF7B2CBF);
      case 'Brand':
        return const Color(0xFF1B7A4A);
      case 'Creator':
        return const Color(0xFFB03080);
      case 'Category':
        return const Color(0xFFB03080);
      default:
        return const Color(0xFF7B2CBF);
    }
  }

  Color get _badgeTextColor {
    if (item.type == 'Brand') return const Color(0xFF44E896);
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 54,
                height: 54,
                child: item.imageUrl.isNotEmpty
                    ? Image.network(
                        item.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const _SearchPlaceholder(),
                      )
                    : const _SearchPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.type} · ${item.subtitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _badgeColor.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _badgeColor.withValues(alpha: 0.55)),
              ),
              child: Text(
                item.type,
                style: TextStyle(
                  color: _badgeTextColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Icon placeholder ──────────────────────────────────────────────────────────
class _SearchPlaceholder extends StatelessWidget {
  const _SearchPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF1A1A2E),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined,
              color: Colors.white12, size: 22),
        ),
      );
}
