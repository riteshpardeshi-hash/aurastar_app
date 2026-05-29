import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'challenge_detail.dart';

class AllGeneralChallengesScreen extends StatefulWidget {
  const AllGeneralChallengesScreen({super.key});

  @override
  State<AllGeneralChallengesScreen> createState() => _AllGeneralChallengesScreenState();
}

class _AllGeneralChallengesScreenState extends State<AllGeneralChallengesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedCategories = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Live Challenges', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search challenges...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1A0533),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('challenges')
                  .where('creatorId', isEqualTo: 'system')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allDocs = snapshot.data?.docs ?? [];

                // Collect unique categories from the fetched docs
                final categories = <String>{};
                for (final doc in allDocs) {
                  final cat = (doc.data() as Map<String, dynamic>)['category'] as String?;
                  if (cat != null && cat.isNotEmpty) categories.add(cat);
                }
                final sortedCategories = categories.toList()..sort();

                // Apply search + category filters
                final docs = allDocs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (_searchQuery.isNotEmpty) {
                    final title = (data['title'] ?? '').toString().toLowerCase();
                    final description = (data['description'] ?? '').toString().toLowerCase();
                    if (!title.contains(_searchQuery) && !description.contains(_searchQuery)) {
                      return false;
                    }
                  }
                  if (_selectedCategories.isNotEmpty) {
                    final cat = (data['category'] as String?) ?? '';
                    if (!_selectedCategories.contains(cat)) return false;
                  }
                  return true;
                }).toList();

                if (allDocs.isEmpty) {
                  return const Center(
                    child: Text('No challenges available.', style: TextStyle(color: Colors.white54)),
                  );
                }

                return Column(
                  children: [
                    if (sortedCategories.isNotEmpty)
                      SizedBox(
                        height: 44,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          itemCount: sortedCategories.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final cat = sortedCategories[i];
                            final selected = _selectedCategories.contains(cat);
                            return GestureDetector(
                              onTap: () => setState(() {
                                if (selected) {
                                  _selectedCategories.remove(cat);
                                } else {
                                  _selectedCategories.add(cat);
                                }
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  color: selected ? const Color(0xFF7B2CBF) : const Color(0xFF1A0533),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected ? const Color(0xFF7B2CBF) : const Color(0xFF4A1A7A),
                                  ),
                                ),
                                child: Text(
                                  cat,
                                  style: TextStyle(
                                    color: selected ? Colors.white : Colors.white60,
                                    fontSize: 13,
                                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (docs.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            _selectedCategories.isNotEmpty || _searchQuery.isNotEmpty
                                ? 'No challenges match your filters'
                                : 'No challenges available.',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final title = data['title'] ?? 'Challenge';
                            return GestureDetector(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChallengeDetail(
                                    title: title,
                                    instructions: data['instructions'] ?? 'No instructions',
                                    videoUrl: data['videoUrl'] ?? '',
                                    challengeId: doc.id,
                                  ),
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF1A0533), Color(0xFF3A1C71)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Image.asset('assets/images/live.png', height: 22),
                                    const Spacer(),
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if ((data['description'] ?? '').toString().isNotEmpty)
                                      Text(
                                        data['description'],
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                                      ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Tap to participate →',
                                      style: TextStyle(
                                        color: Color(0xFFBB6BD9),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
