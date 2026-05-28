import 'package:flutter/material.dart';
import '../../dashboard/dashboard.dart';

class CreatorChallengeSubmittedScreen extends StatelessWidget {
  const CreatorChallengeSubmittedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircleAvatar(
                  radius: 36,
                  backgroundColor: Color(0xFFE8F5E9),
                  child: Icon(Icons.check_circle, color: Colors.green, size: 42),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Your video is sent for approval",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Once admin approves it, your challenge will go live on the app.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => Dashboard()),
                        (route) => false,
                      );
                    },
                    child: const Text("Go to Dashboard"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
