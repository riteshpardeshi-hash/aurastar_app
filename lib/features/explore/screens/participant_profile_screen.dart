import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ParticipantProfileScreen extends StatelessWidget {
  final String userId;

  const ParticipantProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Participant Profile")),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

          final name = data['name'] ?? 'User';
          final username = data['username'] ?? '';
          final email = data['email'] ?? '';
          final totalRewards = data['totalRewards'] ?? 0;
          final bio = data['bio'] ?? '';

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 40,
                  child: Icon(Icons.person, size: 40),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  "@$username",
                  style: const TextStyle(color: Colors.black54, fontSize: 16),
                ),
                const SizedBox(height: 6),
                Text(email, style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 20),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.auto_awesome),
                    title: const Text("Total Aura Points"),
                    trailing: Text("$totalRewards"),
                  ),
                ),
                if (bio.toString().isNotEmpty)
                  Card(
                    child: ListTile(
                      title: const Text("Bio"),
                      subtitle: Text(bio),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
