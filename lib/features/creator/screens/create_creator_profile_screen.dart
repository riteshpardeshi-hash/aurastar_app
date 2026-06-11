import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreateCreatorProfileScreen extends StatefulWidget {
  const CreateCreatorProfileScreen({super.key});

  @override
  State<CreateCreatorProfileScreen> createState() =>
      _CreateCreatorProfileScreenState();
}

class _CreateCreatorProfileScreenState
    extends State<CreateCreatorProfileScreen> {
  final pageNameController = TextEditingController();
  final bioController = TextEditingController();
  bool isSaving = false;

  @override
  void dispose() {
    pageNameController.dispose();
    bioController.dispose();
    super.dispose();
  }

  InputDecoration input(String hint) {
    return InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      hintText: hint,
    );
  }

  Future<void> saveCreatorProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (pageNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter page name")),
      );
      return;
    }

    try {
      setState(() => isSaving = true);

      // Save display fields on the user doc (no role change from client)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'pageName': pageNameController.text.trim(),
        'bio': bioController.text.trim(),
      });

      // Submit application for admin review — isCreator is set server-side on approval
      await FirebaseFirestore.instance.collection('creator_applications').doc(user.uid).set({
        'uid': user.uid,
        'pageName': pageNameController.text.trim(),
        'bio': bioController.text.trim(),
        'status': 'pending',
        'submittedAt': Timestamp.now(),
      });

      if (!mounted) return;

      setState(() => isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Application submitted! You'll be notified once approved."),
          duration: Duration(seconds: 4),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Brand Profile")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: pageNameController,
              decoration: input("Page Name"),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bioController,
              maxLines: 4,
              decoration: input("Bio"),
            ),
            const SizedBox(height: 20),
            isSaving
                ? const CircularProgressIndicator()
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saveCreatorProfile,
                      child: const Text("Create Brand Profile"),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
