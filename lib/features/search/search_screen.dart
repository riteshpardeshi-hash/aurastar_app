import 'dart:async';
import 'package:flutter/material.dart';
import '../challenges/screens/challenge_detail.dart';
import '../challenges/screens/category_challenges_screen.dart';
import '../../../core/services/search_service.dart';

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
  final _service = SearchService();

  String _query = '';
  String _filter = 'All';
  List<_SearchItem> _recent = [];
  List<_SearchItem> _results = [];
  bool _searching = false;
  Timer? _debounce;

  static const _filters = ['All', 'Challenges', 'Brands', 'Creators'];

  static const _filterTypeMap = {
    'All': 'all',
    'Challenges': 'challenges',
    'Brands': 'brands',
    'Creators': 'creators',
  };

  @override
  void initState() {
    super.initState();
    _loadRecent();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    final items = await _service.fetchRecent();
    if (!mounted) return;
    setState(() => _recent = items.map(_SearchItem.fromApiItem).toList());
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _results = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    try {
      final type = _filterTypeMap[_filter] ?? 'all';
      final data = await _service.search(q, type: type);
      if (!mounted) return;
      setState(() {
        _results = _parseResults(data, type);
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() { _results = []; _searching = false; });
    }
  }

  List<_SearchItem> _parseResults(Map<String, dynamic> data, String type) {
    final items = <_SearchItem>[];
    if (type == 'all') {
      for (final c in (data['challenges'] as List? ?? [])) {
        final m = c as Map<String, dynamic>;
        items.add(_SearchItem(
          id: m['_id'] as String? ?? '',
          type: 'Challenge',
          title: m['title'] as String? ?? '',
          subtitle: '${m['starsCount'] ?? 0} Aura',
          imageUrl: '',
          entityType: 'challenge',
        ));
      }
      for (final b in (data['brands'] as List? ?? [])) {
        final m = b as Map<String, dynamic>;
        items.add(_SearchItem(
          id: m['_id'] as String? ?? '',
          type: 'Brand',
          title: m['displayName'] as String? ?? '',
          subtitle: '@${m['username'] ?? ''}',
          imageUrl: m['avatar'] as String? ?? '',
          entityType: 'brand',
        ));
      }
      for (final c in (data['creators'] as List? ?? [])) {
        final m = c as Map<String, dynamic>;
        items.add(_SearchItem(
          id: m['_id'] as String? ?? '',
          type: 'Creator',
          title: m['displayName'] as String? ?? '',
          subtitle: '@${m['username'] ?? ''}',
          imageUrl: m['avatar'] as String? ?? '',
          entityType: 'creator',
        ));
      }
      for (final c in (data['categories'] as List? ?? [])) {
        final m = c as Map<String, dynamic>;
        items.add(_SearchItem(
          id: m['_id'] as String? ?? '',
          type: 'Category',
          title: m['name'] as String? ?? '',
          subtitle: '',
          imageUrl: '',
          entityType: 'category',
        ));
      }
    } else {
      for (final d in (data['docs'] as List? ?? [])) {
        final m = d as Map<String, dynamic>;
        if (type == 'challenges') {
          items.add(_SearchItem(
            id: m['_id'] as String? ?? '',
            type: 'Challenge',
            title: m['title'] as String? ?? '',
            subtitle: '${m['starsCount'] ?? 0} Aura',
            imageUrl: '',
            entityType: 'challenge',
          ));
        } else {
          items.add(_SearchItem(
            id: m['_id'] as String? ?? '',
            type: type == 'brands' ? 'Brand' : 'Creator',
            title: m['displayName'] as String? ?? '',
            subtitle: '@${m['username'] ?? ''}',
            imageUrl: m['avatar'] as String? ?? '',
            entityType: type == 'brands' ? 'brand' : 'creator',
          ));
        }
      }
    }
    return items;
  }

  void _onItemTap(_SearchItem item) {
    _service.saveHistory(item.entityType, item.id);
    if (item.type == 'Challenge') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            title: item.title,
            instructions: '',
            videoUrl: '',
            challengeId: item.id,
          ),
        ),
      );
    } else if (item.type == 'Category') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryChallengesScreen(category: item.title),
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
            child: Icon(Icons.search_rounded, color: Colors.white54, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontFamily: 'SpaceGrotesk'),
              decoration: InputDecoration(
                hintText: 'Search challenges, brands, creators...',
                hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 15,
                    fontFamily: 'SpaceGrotesk'),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              onChanged: (v) {
                setState(() => _query = v);
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 400),
                  () => _search(v),
                );
              },
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                setState(() { _query = ''; _results = []; });
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.50), size: 18),
              ),
            ),
        ],
      ),
    );
  }

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
                    fontWeight:
                        active ? FontWeight.w700 : FontWeight.w500,
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
        const Text('Recent',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'ClashDisplay')),
        const SizedBox(height: 12),
        ..._recent.map((item) => _SearchRow(
              item: item,
              onTap: () => _onItemTap(item),
            )),
      ],
    );
  }

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
        final item = _results[i];
        return _SearchRow(item: item, onTap: () => _onItemTap(item));
      },
    );
  }
}

// ── Data model ─────────────────────────────────────────────────────────────────

class _SearchItem {
  final String id, type, title, subtitle, imageUrl, entityType;

  const _SearchItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.entityType,
  });

  static _SearchItem fromApiItem(Map<String, dynamic> item) {
    final type = item['type'] as String? ?? '';
    final entity = item['entity'] as Map<String, dynamic>? ?? {};
    switch (type) {
      case 'challenge':
        return _SearchItem(
          id: entity['_id'] as String? ?? '',
          type: 'Challenge',
          title: entity['title'] as String? ?? '',
          subtitle: '${entity['starsCount'] ?? 0} Aura',
          imageUrl: '',
          entityType: 'challenge',
        );
      case 'brand':
      case 'creator':
        return _SearchItem(
          id: entity['_id'] as String? ?? '',
          type: type == 'brand' ? 'Brand' : 'Creator',
          title: entity['displayName'] as String? ?? '',
          subtitle: '@${entity['username'] ?? ''}',
          imageUrl: entity['avatar'] as String? ?? '',
          entityType: type,
        );
      case 'category':
        return _SearchItem(
          id: entity['_id'] as String? ?? '',
          type: 'Category',
          title: entity['name'] as String? ?? '',
          subtitle: '',
          imageUrl: '',
          entityType: 'category',
        );
      default:
        return _SearchItem(
            id: '', type: type, title: '', subtitle: '', imageUrl: '', entityType: type);
    }
  }
}

// ── Row widget ─────────────────────────────────────────────────────────────────

class _SearchRow extends StatelessWidget {
  final _SearchItem item;
  final VoidCallback onTap;

  const _SearchRow({required this.item, required this.onTap});

  Color get _badgeColor {
    switch (item.type) {
      case 'Brand':   return const Color(0xFF1B7A4A);
      case 'Creator': return const Color(0xFFB03080);
      case 'Category':return const Color(0xFFB03080);
      default:        return const Color(0xFF7B2CBF);
    }
  }

  Color get _badgeTextColor =>
      item.type == 'Brand' ? const Color(0xFF44E896) : Colors.white;

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
                  if (item.subtitle.isNotEmpty) ...[
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
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _badgeColor.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _badgeColor.withValues(alpha: 0.55)),
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
