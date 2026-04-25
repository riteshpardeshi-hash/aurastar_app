import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  cameras = await availableCameras();
  runApp(const MyApp());
}

//////////////////////////////////////////////////////
// APP ROOT
//////////////////////////////////////////////////////

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FirebaseAuth.instance.currentUser != null
          ? Dashboard()
          : const LoginScreen(),
    );
  }
}

//////////////////////////////////////////////////////
// LOGIN SCREEN
//////////////////////////////////////////////////////

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLogin = true;
  bool keepMeLoggedIn = true;
  bool isLoading = false;

  Future<void> handleAuth() async {
    try {
      setState(() => isLoading = true);

      debugPrint("Login button clicked");

      UserCredential userCred;

      if (isLogin) {
        userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      } else {
        userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: emailController.text.trim(),
          password: passwordController.text.trim(),
        );
      }

      debugPrint("User logged in: ${userCred.user?.uid}");

      final user = userCred.user;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

      debugPrint("User doc exists: ${doc.exists}");

      if (!mounted) return;

      setState(() => isLoading = false);

      if (!doc.exists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => Dashboard()),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoading = false);

      debugPrint("ERROR: $e");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple, Colors.deepPurple],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "AURA",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: emailController,
                  decoration: input("Email"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: input("Password"),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Checkbox(
                      value: keepMeLoggedIn,
                      activeColor: Colors.white,
                      checkColor: Colors.deepPurple,
                      onChanged: (value) {
                        setState(() {
                          keepMeLoggedIn = value ?? true;
                        });
                      },
                    ),
                    const Expanded(
                      child: Text(
                        "Keep me logged in",
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : handleAuth,
                    child: isLoading
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Text(isLogin ? "Login" : "Sign Up"),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => isLogin = !isLogin);
                  },
                  child: Text(
                    isLogin
                        ? "Don't have an account? Sign Up"
                        : "Already have an account? Login",
                    style: const TextStyle(color: Colors.white),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration input(String hint) {
    return InputDecoration(
      filled: true,
      fillColor: Colors.white,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}


//////////////////////////////////////////////////////
// PROFILE SETUP
//////////////////////////////////////////////////////

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  DateTime? selectedDate;

  Future<void> pickDate() async {
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() => selectedDate = picked);
    }
  }

  Future<void> saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .set({
      'name': nameController.text,
      'username': usernameController.text,
      'dob': selectedDate,
      'email': user.email,
      'totalRewards': 0,
      'isCreator': false,
      'isAdmin': false,
      'bio': '',
      'profileImageUrl': '',
      'pageName': '',
      'createdAt': Timestamp.now(),
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => Dashboard()),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create Profile")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Full Name"),
            ),
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(labelText: "Username"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: pickDate,
              child: Text(selectedDate == null
                  ? "Select DOB"
                  : "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: saveProfile,
              child: const Text("Create Profile"),
            )
          ],
        ),
      ),
    );
  }
}

//////////////////////////////////////////////////////
// DASHBOARD (FIREBASE CONNECTED)
//////////////////////////////////////////////////////

class Dashboard extends StatelessWidget {
  Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Dashboard"),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ////////////////////////////////
            /// REWARD CARD (DYNAMIC)
            ////////////////////////////////
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purple, Colors.deepPurple],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Your Rewards",
                        style: TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 5),
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(FirebaseAuth.instance.currentUser!.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Text(
                              "...",
                              style: TextStyle(color: Colors.white),
                            );
                          }

                          final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                          final points = data['totalRewards'] ?? 0;

                          return Text(
                            "$points pts",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const Icon(
                    Icons.emoji_events,
                    color: Colors.white,
                    size: 40,
                  ),
                ],
              ),
            ),

            ////////////////////////////////
            /// QUICK BUTTONS
            ////////////////////////////////
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepPurple,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LeaderboardScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.emoji_events),
                      label: const Text(
                        "Leaderboard",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepPurple,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MyAccountScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.person),
                      label: const Text(
                        "My Account",
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            ////////////////////////////////
            /// FIREBASE CHALLENGES
            ////////////////////////////////
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('challenges')
                    .where('status', isEqualTo: 'approved')
                    .where('creatorId', isEqualTo: 'system')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }

                  final challenges = snapshot.data!.docs;

                  if (challenges.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text("No challenges yet 😢"),
                    );
                  }

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: challenges.length,
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemBuilder: (context, index) {
                      final c = challenges[index];

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChallengeDetail(
                                title: c['title'] ?? "",
                                instructions:
                                c['instructions'] ?? "No instructions",
                                videoUrl: c['videoUrl'] ?? "",
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blue.shade400,
                                Colors.blue.shade700,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.flash_on,
                                color: Colors.white,
                                size: 30,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                c['title'] ?? "No Title",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                c['description'] ?? "",
                                style: const TextStyle(
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            ////////////////////////////////
            /// ACTION BUTTONS
            ////////////////////////////////
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6A00), Color(0xFFFF3D00)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ExploreCreatorsScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "Explore Creators 🔥",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    height: 55,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade300,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user == null) return;

                        final doc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .get();

                        final data = doc.data() ?? {};
                        final isCreator = data['isCreator'] ?? false;

                        if (!context.mounted) return;

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => isCreator
                                ? const CreatorHomeScreen()
                                : const CreateCreatorProfileScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "Become a Creator",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final isCreator = data['isCreator'] ?? false;

                if (!isCreator) return const SizedBox.shrink();

                return Container(
                  width: double.infinity,
                  height: 55,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF5B2EFF), Color(0xFF9B4DFF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withValues(alpha: 0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreatorAdminScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      "Creator Admin Panel",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),


            ////////////////////////////////
            /// ADMIN BUTTON ONLY
            ////////////////////////////////
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox.shrink();

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final isAdmin = data['isAdmin'] ?? false;

                if (!isAdmin) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminScreen(),
                        ),
                      );
                    },
                    child: const Text("Admin Panel"),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}




//////////////////////////////////////////////////////
// CHALLENGE DETAIL
//////////////////////////////////////////////////////

class ChallengeDetail extends StatelessWidget {
  final String title;
  final String instructions;
  final String videoUrl;

  const ChallengeDetail({
    super.key,
    required this.title,
    required this.instructions,
    required this.videoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //////////////////////////////
            /// VIDEO BOX
            //////////////////////////////
            SizedBox(
              height: 200,
              child: VideoPlayerWidget(videoUrl),
            ),
            const SizedBox(height: 20),

            //////////////////////////////
            /// INSTRUCTIONS
            //////////////////////////////
            const Text(
              "Instructions:",
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            Text(
              instructions,
              style: const TextStyle(fontSize: 16),
            ),

            const Spacer(),

            //////////////////////////////
            /// RECORD BUTTON
            //////////////////////////////
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CameraScreen(
                        challengeTitle: title,
                      ),
                    ),
                  );
                },
                child: const Text("Start Recording"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final String url;

  const VideoPlayerWidget(this.url, {super.key});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController controller;

  @override
  void initState() {
    super.initState();
    controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.url),
    )..initialize().then((_) {
      setState(() {});
      controller.play();
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }
}
//////////////////////////////////////////////////////
// CAMERA SCREEN 🎥
//////////////////////////////////////////////////////

class CameraScreen extends StatefulWidget {
  final String challengeTitle;

  const CameraScreen({
    super.key,
    required this.challengeTitle,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  bool recording = false;
  XFile? videoFile;

  @override
  void initState() {
    super.initState();
    controller = CameraController(cameras[0], ResolutionPreset.medium);
    controller!.initialize().then((_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> recordVideo() async {
    if (!recording) {
      await controller!.startVideoRecording();
      setState(() => recording = true);
    } else {
      videoFile = await controller!.stopVideoRecording();
      setState(() => recording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Record")),
      body: Column(
        children: [
          Expanded(child: CameraPreview(controller!)),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              /////////////////////////////
              /// RECORD BUTTON
              /////////////////////////////
              ElevatedButton(
                onPressed: recordVideo,
                child: Text(recording ? "Stop" : "Record"),
              ),

              /////////////////////////////
              /// PREVIEW BUTTON
              /////////////////////////////
              ElevatedButton(
                onPressed: videoFile == null
                    ? null
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PreviewScreen(
                        videoPath: videoFile!.path, // ✅ FIXED
                        challengeTitle: widget.challengeTitle,
                      ),
                    ),
                  );
                },
                child: const Text("Preview"),
              ),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class PreviewScreen extends StatefulWidget {
  final String videoPath;
  final String challengeTitle;

  const PreviewScreen({
    super.key,
    required this.videoPath,
    required this.challengeTitle,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late VideoPlayerController _controller;
  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.file(
      File(widget.videoPath),
    )..initialize().then((_) {
      setState(() {});
      _controller.play();
    });
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  bool isUploading = false;

  Future<void> uploadVideo() async {
    try {
      setState(() => isUploading = true);

      final user = FirebaseAuth.instance.currentUser;
      final file = File(widget.videoPath);

      final fileName =
          "${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}";

      final ref = FirebaseStorage.instance
          .ref()
          .child('submissions')
          .child(user!.uid)
          .child(fileName);

      // 🔥 Upload
      await ref.putFile(file);

      // 🔥 Get URL
      final videoUrl = await ref.getDownloadURL();

      // 🔥 Save in Firestore
      await FirebaseFirestore.instance.collection('submissions').add({
        'userId': user.uid,
        'challengeTitle': widget.challengeTitle,
        'videoUrl': videoUrl,
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });

      setState(() => isUploading = false);

      // ✅ Success
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Video uploaded")),
      );

      Navigator.pop(context);

    } catch (e) {
      setState(() => isUploading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Preview")),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _controller.value.isInitialized
                  ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
                  : const CircularProgressIndicator(),
            ),
          ),

          const SizedBox(height: 20),

          isUploading
              ? const CircularProgressIndicator()
              : Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: uploadVideo,
              child: const Text("Submit Video"),
            ),
          ),
        ],
      ),
    );
  }
}

//////////////////////////////////////////////////////
// CREATOR FLOW
//////////////////////////////////////////////////////

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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
        const SnackBar(content: Text("Creator profile created successfully")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const CreatorHomeScreen(),
        ),
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
      appBar: AppBar(title: const Text("Create Creator Profile")),
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
                child: const Text("Create Creator Profile"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreatorHomeScreen extends StatelessWidget {
  const CreatorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Creator Home")),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data =
              snapshot.data!.data() as Map<String, dynamic>? ?? {};

          final pageName = data['pageName'] ?? 'Creator';
          final bio = data['bio'] ?? '';
          final username = data['username'] ?? '';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pageName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "@$username",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        bio.isNotEmpty
                            ? bio
                            : "Add a bio to tell people about your page.",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateChallenge(),
                        ),
                      );
                    },
                    child: const Text("Create Challenge"),
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreatorProfileScreen(
                            creatorId: user.uid,
                          ),
                        ),
                      );
                    },
                    child: const Text("View My Creator Profile"),
                  ),
                ),

                const SizedBox(height: 20),

                const Text(
                  "My Challenge Requests",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('creator_requests')
                      .where('creatorId', isEqualTo: user.uid)
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, requestSnapshot) {
                    if (!requestSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final requests = requestSnapshot.data!.docs;

                    if (requests.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          "No challenge requests submitted yet.",
                        ),
                      );
                    }

                    return Column(
                      children: requests.map((r) {
                        final status = r['status'] ?? 'pending';
                        final rejectionReason = r['rejectionReason'] ?? '';

                        return Card(
                          child: ListTile(
                            title: Text(r['title'] ?? 'No Title'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Status: $status"),
                                if (status == 'rejected' &&
                                    rejectionReason.toString().isNotEmpty)
                                  Text("Reason: $rejectionReason"),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}


class CreateChallenge extends StatefulWidget {
  const CreateChallenge({super.key});

  @override
  State<CreateChallenge> createState() => _CreateChallengeState();
}

class _CreateChallengeState extends State<CreateChallenge> {
  final titleController = TextEditingController();
  final descController = TextEditingController();
  final instructionController = TextEditingController();

  XFile? videoFile;
  bool isSubmitting = false;

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    instructionController.dispose();
    super.dispose();
  }

  Future<void> openRecorder() async {
    final recordedVideo = await Navigator.push<XFile>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreatorVideoRecorderScreen(),
      ),
    );

    if (recordedVideo != null) {
      setState(() {
        videoFile = recordedVideo;
      });
    }
  }

  Future<void> submitChallenge() async {
    if (videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please record video first")),
      );
      return;
    }

    if (titleController.text.isEmpty ||
        descController.text.isEmpty ||
        instructionController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Fill all fields")),
      );
      return;
    }

    try {
      setState(() => isSubmitting = true);

      final user = FirebaseAuth.instance.currentUser;
      final file = File(videoFile!.path);

      final fileName =
          "${DateTime.now().millisecondsSinceEpoch}_${path.basename(file.path)}";

      final ref = FirebaseStorage.instance
          .ref()
          .child('creator_videos')
          .child(user!.uid)
          .child(fileName);

      await ref.putFile(file);

      final videoUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('creator_requests').add({
        'title': titleController.text.trim(),
        'description': descController.text.trim(),
        'instructions': instructionController.text.trim(),
        'videoUrl': videoUrl,
        'creatorId': user.uid,
        'status': 'pending',
        'rejectionReason': '',
        'createdAt': Timestamp.now(),
      });

      if (!mounted) return;

      setState(() => isSubmitting = false);

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const CreatorChallengeSubmittedScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  InputDecoration input(String hint) {
    return InputDecoration(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      hintText: hint,
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
            const SizedBox(height: 20),
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  videoFile == null ? "No video recorded yet" : "Video Recorded ✅",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: openRecorder,
                    child: const Text("Record Video"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: videoFile == null
                        ? null
                        : () {
                      setState(() {
                        videoFile = null;
                      });
                    },
                    child: const Text("Delete"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                onPressed: isSubmitting ? null : submitChallenge,
                child: isSubmitting
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.4,
                  ),
                )
                    : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      "Send for Approval",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            )

          ],
        ),
      ),
    );
  }
}

class CreatorVideoRecorderScreen extends StatefulWidget {
  const CreatorVideoRecorderScreen({super.key});

  @override
  State<CreatorVideoRecorderScreen> createState() =>
      _CreatorVideoRecorderScreenState();
}

class _CreatorVideoRecorderScreenState
    extends State<CreatorVideoRecorderScreen> {
  CameraController? controller;
  bool isRecording = false;
  XFile? recordedVideo;

  @override
  void initState() {
    super.initState();
    initCamera();
  }

  Future<void> initCamera() async {
    controller = CameraController(cameras[0], ResolutionPreset.medium);
    await controller!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> toggleRecording() async {
    if (controller == null || !controller!.value.isInitialized) return;

    if (!isRecording) {
      await controller!.startVideoRecording();
      setState(() => isRecording = true);
    } else {
      recordedVideo = await controller!.stopVideoRecording();
      setState(() => isRecording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Record Challenge Video")),
      body: Column(
        children: [
          Expanded(
            child: CameraPreview(controller!),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: toggleRecording,
                    child: Text(
                      isRecording ? "Stop Recording" : "Start Recording",
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: recordedVideo == null
                        ? null
                        : () {
                      Navigator.pop(context, recordedVideo);
                    },
                    child: const Text("Use This Video"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Your video is sent for approval",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Once admin approves it, your challenge will go live on the app.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => Dashboard(),
                        ),
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


//////////////////////////////////////////////////////
// ADMIN SCREEN
//////////////////////////////////////////////////////

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Admin Panel"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Submissions"),
              Tab(text: "Creator Requests"),
            ],
          ),
        ),
        body:  TabBarView(
          children: [
            SubmissionTab(),     // existing logic
            CreatorRequestTab(), // new tab 🔥
          ],
        ),
      ),
    );
  }
}

class SubmissionTab extends StatelessWidget {
  const SubmissionTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('submissions')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final submissions = snapshot.data!.docs;

        if (submissions.isEmpty) {
          return const Center(child: Text("No submissions"));
        }

        return ListView.builder(
          itemCount: submissions.length,
          itemBuilder: (context, index) {
            final s = submissions[index];

            return Card(
              child: ListTile(
                title: Text(s['challengeTitle'] ?? ''),
                subtitle: Text("User: ${s['userId']}"),
                trailing: ElevatedButton(
                  child: const Text("Review"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReviewScreen(submission: s),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class CreatorRequestTab extends StatelessWidget {
  const CreatorRequestTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('creator_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final requests = snapshot.data!.docs;

        if (requests.isEmpty) {
          return const Center(child: Text("No creator requests"));
        }

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final r = requests[index];

            return Card(
              child: ListTile(
                title: Text(r['title'] ?? ''),
                subtitle: Text("Creator: ${r['creatorId']}"),
                trailing: ElevatedButton(
                  child: const Text("Review"),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CreatorReviewScreen(request: r),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class CreatorReviewScreen extends StatefulWidget {
  final QueryDocumentSnapshot request;

  const CreatorReviewScreen({super.key, required this.request});

  @override
  State<CreatorReviewScreen> createState() =>
      _CreatorReviewScreenState();
}

class _CreatorReviewScreenState extends State<CreatorReviewScreen> {
  final reasonController = TextEditingController();

  Future<void> approve() async {
    final data = widget.request;

    /// 🔥 Move to challenges collection
    await FirebaseFirestore.instance.collection('challenges').add({
      'title': data['title'],
      'description': data['description'],
      'instructions': data['instructions'],
      'videoUrl': data['videoUrl'],

      'creatorId': data['creatorId'], // 🔥 THIS LINE IS CRITICAL

      'status': 'approved',
      'createdAt': Timestamp.now(),
    });

    /// 🔥 Update request
    await FirebaseFirestore.instance
        .collection('creator_requests')
        .doc(data.id)
        .update({'status': 'approved'});

    Navigator.pop(context);
  }

  Future<void> reject() async {
    await FirebaseFirestore.instance
        .collection('creator_requests')
        .doc(widget.request.id)
        .update({
      'status': 'rejected',
      'rejectionReason': reasonController.text,
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final videoUrl = widget.request['videoUrl'];

    return Scaffold(
      appBar: AppBar(title: const Text("Review Challenge")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ////////////////////////////
            /// VIDEO
            ////////////////////////////
            SizedBox(
              height: 200,
              child: VideoPlayerWidget(videoUrl),
            ),

            const SizedBox(height: 20),

            ////////////////////////////
            /// DETAILS
            ////////////////////////////
            Text(widget.request['title'],
                style:
                const TextStyle(fontWeight: FontWeight.bold)),

            Text(widget.request['description']),

            const SizedBox(height: 10),

            Text(widget.request['instructions']),

            const SizedBox(height: 20),

            ////////////////////////////
            /// REJECTION INPUT
            ////////////////////////////
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: "Rejection Reason (if rejecting)",
              ),
            ),

            const SizedBox(height: 20),

            ////////////////////////////
            /// ACTION BUTTONS
            ////////////////////////////
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: approve,
                    child: const Text("Approve"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: reject,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red),
                    child: const Text("Reject"),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

//////////////////////////////////////////////////////
// REVIEW SCREEN
//////////////////////////////////////////////////////

class ReviewScreen extends StatefulWidget {
  final QueryDocumentSnapshot submission;

  const ReviewScreen({super.key, required this.submission});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final pointsController = TextEditingController();

  Future<void> approveSubmission() async {
    final points = int.tryParse(pointsController.text) ?? 0;
    final userId = widget.submission['userId'];

    await FirebaseFirestore.instance
        .collection('submissions')
        .doc(widget.submission.id)
        .update({
      'status': 'approved',
      'auraPoints': points,
      'reviewed': true,
    });

    final userRef =
    FirebaseFirestore.instance.collection('users').doc(userId);

    final userDoc = await userRef.get();
    final currentPoints = userDoc['totalRewards'] ?? 0;

    await userRef.update({
      'totalRewards': currentPoints + points,
    });

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final videoUrl = widget.submission['videoUrl'];

    return Scaffold(
      appBar: AppBar(title: const Text("Review Submission")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 200,
              child: VideoPlayerWidget(videoUrl),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: pointsController,
              keyboardType: TextInputType.number,
              decoration:
              const InputDecoration(labelText: "Aura Points"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: approveSubmission,
              child: const Text("Approve"),
            )
          ],
        ),
      ),
    );
  }
}

class CreatorsListScreen extends StatelessWidget {
  const CreatorsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Creators")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('challenges')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;

          /// 🔥 GROUP BY creatorId
          final creatorsMap = <String, List<QueryDocumentSnapshot>>{};

          for (var doc in docs) {
            final creatorId = doc['creatorId'];
            creatorsMap.putIfAbsent(creatorId, () => []).add(doc);
          }

          final creatorIds = creatorsMap.keys.toList();

          return ListView.builder(
            itemCount: creatorIds.length,
            itemBuilder: (context, index) {
              final creatorId = creatorIds[index];

              return ListTile(
                title: Text("Creator: $creatorId"),
                subtitle:
                Text("${creatorsMap[creatorId]!.length} challenges"),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CreatorProfileScreen(
                        creatorId: creatorId,
                      ),
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

class CreatorProfileScreen extends StatelessWidget {
  final String creatorId;

  const CreatorProfileScreen({super.key, required this.creatorId});

  @override
  Widget build(BuildContext context) {
    final userRef =
    FirebaseFirestore.instance.collection('users').doc(creatorId);

    final challengesRef = FirebaseFirestore.instance
        .collection('challenges')
        .where('creatorId', isEqualTo: creatorId)
        .where('status', isEqualTo: 'approved');

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: StreamBuilder<DocumentSnapshot>(
        stream: userRef.snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final userData =
              userSnapshot.data!.data() as Map<String, dynamic>? ?? {};

          final name = userData['name'] ?? 'Creator';
          final username = userData['username'] ?? 'creator';
          final pageName = userData['pageName'] ?? '';
          final bio = userData['bio'] ?? '';
          final profileImageUrl = userData['profileImageUrl'] ?? '';
          final totalRewards = userData['totalRewards'] ?? 0;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 290,
                pinned: true,
                backgroundColor: Colors.deepPurple,
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            CircleAvatar(
                              radius: 42,
                              backgroundColor: Colors.white24,
                              backgroundImage: profileImageUrl.isNotEmpty
                                  ? NetworkImage(profileImageUrl)
                                  : null,
                              child: profileImageUrl.isEmpty
                                  ? const Icon(
                                Icons.person,
                                size: 42,
                                color: Colors.white,
                              )
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              pageName.isNotEmpty ? pageName : name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "@$username",
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              bio.isNotEmpty
                                  ? bio
                                  : "This creator has not added a bio yet.",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: challengesRef.snapshots(),
                    builder: (context, challengeSnapshot) {
                      if (!challengeSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final challenges = challengeSnapshot.data!.docs;
                      final challengeCount = challenges.length;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _statCard(
                                  title: "Challenges",
                                  value: "$challengeCount",
                                  icon: Icons.flash_on,
                                  color: Colors.orange,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _statCard(
                                  title: "Aura Points",
                                  value: "$totalRewards",
                                  icon: Icons.auto_awesome,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            "Live Challenges",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (challenges.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text(
                                "No live challenges yet.",
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            GridView.builder(
                              itemCount: challenges.length,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.88,
                              ),
                              itemBuilder: (context, index) {
                                final c = challenges[index];

                                return GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ChallengeDetail(
                                          title: c['title'] ?? "",
                                          instructions:
                                          c['instructions'] ?? "No instructions",
                                          videoUrl: c['videoUrl'] ?? "",
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF2E86DE),
                                          Color(0xFF54A0FF),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withValues(alpha: 0.18),
                                          blurRadius: 10,
                                          offset: const Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.videocam_rounded,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        const Spacer(),
                                        Text(
                                          c['title'] ?? 'No Title',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          c['description'] ?? '',
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}


class ExploreCreatorsScreen extends StatefulWidget {
  const ExploreCreatorsScreen({super.key});

  @override
  State<ExploreCreatorsScreen> createState() =>
      _ExploreCreatorsScreenState();
}

class _ExploreCreatorsScreenState extends State<ExploreCreatorsScreen> {
  String searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Explore Creators")),
      body: Column(
        children: [
          /// SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search creators...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value.toLowerCase();
                });
              },
            ),
          ),

          /// CREATOR LIST
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('challenges')
                  .where('creatorId', isNotEqualTo: 'system')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                final creatorIds = docs
                    .map((doc) => doc['creatorId'])
                    .toSet()
                    .toList();

                return ListView.builder(
                  itemCount: creatorIds.length,
                  itemBuilder: (context, index) {
                    final creatorId = creatorIds[index];

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(creatorId)
                          .get(),
                      builder: (context, userSnap) {
                        if (!userSnap.hasData) return const SizedBox();

                        final name =
                            userSnap.data!['name'] ?? 'Creator';

                        if (!name
                            .toLowerCase()
                            .contains(searchQuery)) {
                          return const SizedBox();
                        }

                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.orange,
                            child: Icon(Icons.person,
                                color: Colors.white),
                          ),
                          title: Text(name),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CreatorProfileScreen(
                                  creatorId: creatorId,
                                ),
                              ),
                            );
                          },
                        );
                      },
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

class MyAccountScreen extends StatelessWidget {
  const MyAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text("My Account"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text("Logout"),
                    content: const Text("Are you sure you want to log out?"),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Cancel"),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Logout"),
                      ),
                    ],
                  );
                },
              );

              if (shouldLogout != true) return;

              await FirebaseAuth.instance.signOut();

              if (!context.mounted) return;

              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
                    (route) => false,
              );
            },
          ),
        ],
      ),

      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user!.uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (userSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text("User data error: ${userSnapshot.error}"),
              ),
            );
          }

          if (userSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
            return const Center(child: Text("User profile not found."));
          }

          final userData =
              userSnapshot.data!.data() as Map<String, dynamic>? ?? {};

          final name = userData['name'] ?? 'User';
          final username = userData['username'] ?? '';
          final totalRewards = userData['totalRewards'] ?? 0;

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('submissions')
                .where('userId', isEqualTo: user.uid)
                .snapshots(),
            builder: (context, submissionSnapshot) {
              if (submissionSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      "Submission error: ${submissionSnapshot.error}",
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (submissionSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!submissionSnapshot.hasData) {
                return const Center(child: Text("No submission data found."));
              }

              final submissions = submissionSnapshot.data!.docs.toList();

              submissions.sort((a, b) {
                final aData = a.data() as Map<String, dynamic>;
                final bData = b.data() as Map<String, dynamic>;

                final aCreatedAt = aData['createdAt'];
                final bCreatedAt = bData['createdAt'];

                if (aCreatedAt is Timestamp && bCreatedAt is Timestamp) {
                  return bCreatedAt.compareTo(aCreatedAt);
                }

                return 0;
              });

              final totalSubmissions = submissions.length;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF3A1C71), Color(0xFFD76D77)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "@$username",
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "$totalRewards Aura Points",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.video_collection,
                            size: 32,
                            color: Colors.deepPurple,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "$totalSubmissions",
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Total Videos Submitted",
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      "My Videos",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (submissions.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          "You have not submitted any videos yet.",
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Column(
                        children: submissions.asMap().entries.map((entry) {
                          final index = entry.key;
                          final doc = entry.value;
                          final data = doc.data() as Map<String, dynamic>;

                          final auraPoints = data['auraPoints'] ?? 0;
                          final videoUrl = data['videoUrl'] ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Video ${index + 1}",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Aura Points: $auraPoints",
                                  style: const TextStyle(
                                    color: Colors.deepPurple,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (videoUrl.toString().isNotEmpty)
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => UserVideoDetailScreen(
                                              videoNumber: index + 1,
                                              auraPoints: auraPoints,
                                              videoUrl: videoUrl,
                                            ),
                                          ),
                                        );
                                      },
                                      child: const Text("View Video"),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}


class UserVideoDetailScreen extends StatelessWidget {
  final int videoNumber;
  final int auraPoints;
  final String videoUrl;

  const UserVideoDetailScreen({
    super.key,
    required this.videoNumber,
    required this.auraPoints,
    required this.videoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Video $videoNumber")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: VideoPlayerWidget(videoUrl),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Aura Points"),
                  subtitle: Text(
                    "$auraPoints pts",
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Leaderboard"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .orderBy('totalRewards', descending: true)
              .limit(20)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final users = snapshot.data!.docs;

            if (users.isEmpty) {
              return const Center(child: Text("No players yet"));
            }

            return ListView.builder(
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                final name = user['name'] ?? 'User';
                final points = user['totalRewards'] ?? 0;

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text("${index + 1}"),
                    ),
                    title: Text(name),
                    trailing: Text("$points pts"),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class CreatorAdminScreen extends StatelessWidget {
  const CreatorAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text("Creator Admin Panel"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('challenges')
            .where('creatorId', isEqualTo: currentUser.uid)
            .where('status', isEqualTo: 'approved')
            .snapshots(),
        builder: (context, challengeSnapshot) {
          if (challengeSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text("Error: ${challengeSnapshot.error}"),
              ),
            );
          }

          if (challengeSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final challenges = challengeSnapshot.data?.docs ?? [];
          final challengeTitles = challenges
              .map((doc) => (doc.data() as Map<String, dynamic>)['title']?.toString() ?? '')
              .where((title) => title.isNotEmpty)
              .toSet()
              .toList();

          if (challengeTitles.isEmpty) {
            return const Center(
              child: Text("No approved creator challenges yet."),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('submissions').snapshots(),
            builder: (context, submissionSnapshot) {
              if (submissionSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text("Error: ${submissionSnapshot.error}"),
                  ),
                );
              }

              if (submissionSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final allSubmissions = submissionSnapshot.data?.docs ?? [];

              final creatorSubmissions = allSubmissions.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final title = data['challengeTitle']?.toString() ?? '';
                return challengeTitles.contains(title);
              }).toList();

              final totalChallenges = challenges.length;
              final totalSubmissions = creatorSubmissions.length;
              final uniqueUsers = creatorSubmissions
                  .map((doc) => (doc.data() as Map<String, dynamic>)['userId']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toSet()
                  .length;
              final videosCreated = totalSubmissions;

              int totalAuraPoints = 0;
              for (final doc in creatorSubmissions) {
                final data = doc.data() as Map<String, dynamic>;
                totalAuraPoints += (data['auraPoints'] ?? 0) as int;
              }

              final avgAttemptsPerUser =
              uniqueUsers == 0 ? 0.0 : totalSubmissions / uniqueUsers;

              int repeatUsers = 0;
              final userSubmissionCount = <String, int>{};
              for (final doc in creatorSubmissions) {
                final data = doc.data() as Map<String, dynamic>;
                final userId = data['userId']?.toString() ?? '';
                if (userId.isEmpty) continue;
                userSubmissionCount[userId] = (userSubmissionCount[userId] ?? 0) + 1;
              }
              for (final count in userSubmissionCount.values) {
                if (count > 1) repeatUsers++;
              }

              final repeatRate =
              uniqueUsers == 0 ? 0.0 : (repeatUsers / uniqueUsers) * 100;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Campaign Overview",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: _reportCard(
                            title: "Total Challenges",
                            value: "$totalChallenges",
                            icon: Icons.flash_on,
                            color: Colors.deepPurple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _reportCard(
                            title: "Total Submissions",
                            value: "$totalSubmissions",
                            icon: Icons.video_collection,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _reportCard(
                            title: "Unique Users",
                            value: "$uniqueUsers",
                            icon: Icons.people,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _reportCard(
                            title: "Videos Created",
                            value: "$videosCreated",
                            icon: Icons.smart_display,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _reportCard(
                            title: "Avg Attempts/User",
                            value: avgAttemptsPerUser.toStringAsFixed(1),
                            icon: Icons.analytics,
                            color: Colors.pink,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _reportCard(
                            title: "Repeat Rate",
                            value: "${repeatRate.toStringAsFixed(0)}%",
                            icon: Icons.repeat,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    _wideReportCard(
                      title: "Total Aura Awarded",
                      value: "$totalAuraPoints pts",
                      icon: Icons.auto_awesome,
                      color: Colors.indigo,
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      "Challenge-wise Report",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Column(
                      children: challenges.map((challengeDoc) {
                        final challengeData =
                        challengeDoc.data() as Map<String, dynamic>;
                        final title = challengeData['title'] ?? 'No Title';

                        final challengeSubmissions = creatorSubmissions.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return data['challengeTitle'] == title;
                        }).toList();

                        final attempts = challengeSubmissions.length;
                        final uniqueChallengeUsers = challengeSubmissions
                            .map((doc) =>
                        (doc.data() as Map<String, dynamic>)['userId']?.toString() ?? '')
                            .where((id) => id.isNotEmpty)
                            .toSet()
                            .length;

                        int auraForChallenge = 0;
                        for (final doc in challengeSubmissions) {
                          final data = doc.data() as Map<String, dynamic>;
                          auraForChallenge += (data['auraPoints'] ?? 0) as int;
                        }

                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text("Total Attempts: $attempts"),
                              Text("Unique Submissions: $uniqueChallengeUsers"),
                              Text("Videos Created: $attempts"),
                              Text("Aura Awarded: $auraForChallenge pts"),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _reportCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _wideReportCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                title,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
