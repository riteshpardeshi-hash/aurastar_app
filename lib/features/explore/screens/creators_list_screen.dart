import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'creator_profile_screen.dart';

class CreatorsListScreen extends StatelessWidget {
  const CreatorsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Creators")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('challenges')
            .limit(200)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load creators.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          final creatorsMap = <String, List<QueryDocumentSnapshot>>{};
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final creatorId = data['creatorId'] as String? ?? '';
            if (creatorId.isEmpty || creatorId == 'system') continue;
            creatorsMap.putIfAbsent(creatorId, () => []).add(doc);
          }

          final creatorIds = creatorsMap.keys.toList();

          return ListView.builder(
            itemCount: creatorIds.length,
            itemBuilder: (context, index) {
              final creatorId = creatorIds[index];

              return ListTile(
                title: Text("Creator: $creatorId"),
                subtitle: Text("${creatorsMap[creatorId]!.length} challenges"),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreatorProfileScreen(creatorId: creatorId),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
