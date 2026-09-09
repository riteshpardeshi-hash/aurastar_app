import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BrandParticipantsScreen extends StatelessWidget {
  final List<String> userIds;

  const BrandParticipantsScreen({super.key, required this.userIds});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Participants")),
      body: userIds.isEmpty
          ? const Center(child: Text("No participants yet"))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: userIds.length,
              itemBuilder: (context, index) {
                final userId = userIds[index];

                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .get(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Card(child: ListTile(title: Text("Loading...")));
                    }

                    final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

                    final name = data['name'] ?? 'User';
                    final username = data['username'] ?? '';
                    final totalRewards = data['totalRewards'] ?? 0;

                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(name),
                        subtitle: Text("@$username"),
                        trailing: Text("$totalRewards pts"),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
