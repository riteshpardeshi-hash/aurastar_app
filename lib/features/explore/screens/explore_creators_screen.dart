import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'creator_profile_screen.dart';

class ExploreCreatorsScreen extends StatefulWidget {
  const ExploreCreatorsScreen({super.key});

  @override
  State<ExploreCreatorsScreen> createState() => _ExploreCreatorsScreenState();
}

class _ExploreCreatorsScreenState extends State<ExploreCreatorsScreen> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Explore Brands")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search brands...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('challenges')
                  .where('creatorId', isNotEqualTo: 'system')
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Failed to load brands.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;
                final creatorIds = <String>{};
                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final id = data['creatorId'] as String? ?? '';
                  if (id.isNotEmpty) creatorIds.add(id);
                }

                final idList = creatorIds.toList();
                return ListView.builder(
                  itemCount: idList.length,
                  itemBuilder: (context, index) {
                    return _CreatorTile(
                      creatorId: idList[index],
                      searchQuery: searchQuery,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatorTile extends StatefulWidget {
  final String creatorId;
  final String searchQuery;
  const _CreatorTile({required this.creatorId, required this.searchQuery});

  @override
  State<_CreatorTile> createState() => _CreatorTileState();
}

class _CreatorTileState extends State<_CreatorTile> {
  late final Future<DocumentSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.creatorId)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox();
        final data = snap.data!.data() as Map<String, dynamic>? ?? {};
        final name = data['name'] as String? ?? 'Creator';
        if (!name.toLowerCase().contains(widget.searchQuery)) {
          return const SizedBox();
        }
        return ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.orange,
            child: Icon(Icons.person, color: Colors.white),
          ),
          title: Text(name),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CreatorProfileScreen(creatorId: widget.creatorId),
            ),
          ),
        );
      },
    );
  }
}
