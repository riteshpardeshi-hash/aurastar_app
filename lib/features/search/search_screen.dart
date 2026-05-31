import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../challenges/screens/challenge_detail.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<QueryDocumentSnapshot> _results = [];
  bool _loading = false;
  bool _searched = false;

  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);
  static const _card = Color(0xFF0E0E1A);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() { _results = []; _searched = false; });
      return;
    }
    setState(() => _loading = true);

    // Prefix search on title field
    final snap = await FirebaseFirestore.instance
        .collection('challenges')
        .where('title', isGreaterThanOrEqualTo: q)
        .where('title', isLessThanOrEqualTo: '$q')
        .limit(20)
        .get();

    setState(() {
      _results = snap.docs;
      _loading = false;
      _searched = true;
    });
  }

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
              if (v.isEmpty) setState(() { _results = []; _searched = false; });
            },
            decoration: InputDecoration(
              hintText: 'Search challenges…',
              hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.30), fontSize: 15),
              prefixIcon: Icon(Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.40), size: 20),
              suffixIcon: _ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear,
                          color: Colors.white.withValues(alpha: 0.40),
                          size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() { _results = []; _searched = false; });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : !_searched
              ? _buildSuggestions()
              : _results.isEmpty
                  ? _buildEmpty()
                  : _buildResults(),
    );
  }

  Widget _buildSuggestions() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Try searching for',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.40),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ['Dance', 'Yoga', 'Flip', 'Fashion', 'Hiss', 'Walk']
                .map((tag) => GestureDetector(
                      onTap: () {
                        _ctrl.text = tag;
                        _search(tag);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: _accent.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          tag,
                          style: const TextStyle(
                              color: Color(0xFFD4A8FF),
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.white24, size: 52),
          const SizedBox(height: 14),
          const Text('No challenges found',
              style: TextStyle(color: Colors.white38, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            'Try a different search term',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final doc = _results[i];
        final data = doc.data() as Map<String, dynamic>;
        final title = data['title'] as String? ?? 'Challenge';
        final instructions = data['instructions'] as String? ?? '';
        final videoUrl = data['videoUrl'] as String? ?? '';
        final creatorId = data['creatorId'] as String? ?? '';
        final isSystem = creatorId == 'system';

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChallengeDetail(
                title: title,
                instructions: instructions,
                videoUrl: videoUrl,
                challengeId: doc.id,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isSystem
                        ? Icons.auto_awesome_rounded
                        : Icons.store_outlined,
                    color: _accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      if (instructions.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          instructions,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSystem
                              ? _accent.withValues(alpha: 0.15)
                              : Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isSystem ? 'Aura Arena' : 'Brand',
                          style: TextStyle(
                            color: isSystem ? _accent : Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Colors.white24, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
