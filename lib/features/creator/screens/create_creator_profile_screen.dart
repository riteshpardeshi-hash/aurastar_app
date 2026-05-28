import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'creator_home_screen.dart';

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

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isCreator': true,
        'pageName': pageNameController.text.trim(),
        'bio': bioController.text.trim(),
      });

      if (!mounted) return;

      setState(() => isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Brand profile created successfully")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CreatorHomeScreen()),
      );
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
