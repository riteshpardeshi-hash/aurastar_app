import 'package:flutter/material.dart';
import 'brand_camera_screen.dart';

class CreateChallenge extends StatefulWidget {
  const CreateChallenge({super.key});

  @override
  State<CreateChallenge> createState() => _CreateChallengeState();
}

class _CreateChallengeState extends State<CreateChallenge> {
  final titleController = TextEditingController();
  final descController = TextEditingController();
  final instructionController = TextEditingController();

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    instructionController.dispose();
    super.dispose();
  }

  InputDecoration input(String hint) {
    return InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      hintText: hint,
    );
  }

  void openRecorder() {
    if (titleController.text.trim().isEmpty ||
        descController.text.trim().isEmpty ||
        instructionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fill all fields first")),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrandCameraScreen(
          challengeTitle: titleController.text.trim(),
          description: descController.text.trim(),
          instructions: instructionController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Challenge")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: titleController,
              decoration: input("Challenge Title"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descController,
              decoration: input("Short Description"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: instructionController,
              maxLines: 4,
              decoration: input("Detailed Instructions"),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: openRecorder,
                child: const Text("Record Video"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
