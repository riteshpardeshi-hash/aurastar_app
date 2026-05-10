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
          : const AuthChoiceScreen(),
    );
  }
}

class AuthChoiceScreen extends StatelessWidget {
  const AuthChoiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/power-music-concept-portrait (2).jpg',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.20),
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Image.asset(
                    'assets/images/logo_1stdraft_forapp (1).png',
                    height: 100,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 40),
                  const Text(
                    "Choose how you want to continue",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF7B2CBF),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7B2CBF)
                                .withValues(alpha: 0.45),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Continue with Email",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepPurple,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PhoneAuthScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "Continue with Phone",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final phoneController = TextEditingController();
  final otpController = TextEditingController();

  String verificationId = '';
  bool otpSent = false;
  bool isLoading = false;

  @override
  void dispose() {
    phoneController.dispose();
    otpController.dispose();
    super.dispose();
  }

  Future<void> sendOtp() async {
    final phone = phoneController.text.trim();

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter phone number")),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);

          if (!mounted) return;
          await handlePostLogin();
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;

          setState(() => isLoading = false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Verification failed: ${e.message}")),
          );
        },
        codeSent: (String verId, int? resendToken) {
          if (!mounted) return;

          setState(() {
            verificationId = verId;
            otpSent = true;
            isLoading = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("OTP sent successfully")),
          );
        },
        codeAutoRetrievalTimeout: (String verId) {
          verificationId = verId;
        },
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Future<void> verifyOtp() async {
    final otp = otpController.text.trim();

    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter OTP")),
      );
      return;
    }

    try {
      setState(() => isLoading = true);

      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: otp,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;
      await handlePostLogin();
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Invalid OTP or verification failed")),
      );
    }
  }

  Future<void> handlePostLogin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!mounted) return;

    setState(() => isLoading = false);

    if (!doc.exists) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const ProfileSetupScreen(),
        ),
            (route) => false,
      );
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => Dashboard(),
        ),
            (route) => false,
      );
    }
  }

  InputDecoration input(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Colors.black54,
        fontSize: 16,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 18,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Colors.white,
          width: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/power-music-concept-portrait (2).jpg',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.20),
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.65),
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Text(
                      "Continue with Phone",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: input("Phone Number (+91XXXXXXXXXX)"),
                    ),
                    const SizedBox(height: 16),
                    if (otpSent)
                      TextField(
                        controller: otpController,
                        keyboardType: TextInputType.number,
                        decoration: input("Enter OTP"),
                      ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B2CBF),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7B2CBF)
                                  .withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: isLoading
                              ? null
                              : (otpSent ? verifyOtp : sendOtp),
                          child: isLoading
                              ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          )
                              : Text(
                            otpSent ? "Verify OTP" : "Send OTP",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        "Back",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Image.asset(
                      'assets/images/logo_1stdraft_forapp (1).png',
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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

      final user = userCred.user;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();

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

  InputDecoration input(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Colors.black54,
        fontSize: 16,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 18,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(
          color: Colors.white,
          width: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/power-music-concept-portrait (2).jpg',
            fit: BoxFit.cover,
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.15),
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
              child: SizedBox(
                height: MediaQuery.of(context).size.height - 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextField(
                      controller: emailController,
                      decoration: input("Email/Username"),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: input("Password"),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: keepMeLoggedIn,
                            activeColor: Colors.white,
                            checkColor: const Color(0xFF7B2CBF),
                            side: const BorderSide(color: Colors.white, width: 1.4),
                            onChanged: (value) {
                              setState(() {
                                keepMeLoggedIn = value ?? true;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text(
                          "Keep me logged in",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B2CBF),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7B2CBF).withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          onPressed: isLoading ? null : handleAuth,
                          child: isLoading
                              ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          )
                              : Text(
                            isLogin ? "Login" : "Sign Up",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () {
                        setState(() => isLogin = !isLogin);
                      },
                      child: Text(
                        isLogin
                            ? "Don't have an account? Sign Up"
                            : "Already have an account? Login",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    Image.asset(
                      'assets/images/logo_1stdraft_forapp (1).png',
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
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
// DASHBOARD (ROLE-BASED)
//////////////////////////////////////////////////////

class Dashboard extends StatelessWidget {
  Dashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final userData =
            userSnapshot.data!.data() as Map<String, dynamic>? ?? {};

        final isAdmin = userData['isAdmin'] ?? false;
        final isBrand = userData['isCreator'] ?? false;
        final points = userData['totalRewards'] ?? 0;

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
                /// REWARD CARD
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
                          Text(
                            "$points pts",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
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
                /// COMMON QUICK BUTTONS
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
                /// GENERAL USER + ADMIN
                ////////////////////////////////
                if (!isBrand || isAdmin) ...[
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
                            child: Text("No challenges yet"),
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
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
                          "Explore Brands 🔥",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                ////////////////////////////////
                /// BRAND + ADMIN
                ////////////////////////////////
                if (isBrand || isAdmin) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
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
                          final doc = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(userId)
                              .get();

                          final data = doc.data() ?? {};
                          final alreadyBrand = data['isCreator'] ?? false;

                          if (!context.mounted) return;

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => alreadyBrand
                                  ? const CreatorHomeScreen()
                                  : const CreateCreatorProfileScreen(),
                            ),
                          );
                        },
                        child: Text(
                          isBrand ? "Brand Home" : "Start Brand Page",
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
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
                          "Brand Admin Panel",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                ////////////////////////////////
                /// ADMIN ONLY
                ////////////////////////////////
                if (isAdmin)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
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
  int selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    initCamera(selectedCameraIndex);
  }

  Future<void> initCamera(int cameraIndex) async {
    if (cameras.isEmpty) return;

    controller?.dispose();

    controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.medium,
    );

    await controller!.initialize();

    if (mounted) {
      setState(() {
        selectedCameraIndex = cameraIndex;
      });
    }
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2 || recording) return;

    final nextIndex = selectedCameraIndex == 0 ? 1 : 0;
    await initCamera(nextIndex);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Future<void> recordVideo() async {
    if (controller == null || !controller!.value.isInitialized) return;

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
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Record"),
        actions: [
          IconButton(
            onPressed: switchCamera,
            icon: const Icon(Icons.flip_camera_android),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CameraPreview(controller!),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: recordVideo,
                    child: Text(recording ? "Stop" : "Record"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: videoFile == null
                        ? null
                        : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PreviewScreen(
                            videoPath: videoFile!.path,
                            challengeTitle: widget.challengeTitle,
                          ),
                        ),
                      );
                    },
                    child: const Text("Preview"),
                  ),
                ),
              ],
            ),
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
        'auraPoints': 0,
        'views': 0,
        'reach': 0,
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
        const SnackBar(content: Text("Brand profile created successfully")),
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

class CreatorHomeScreen extends StatelessWidget {
  const CreatorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text("Brand Home")),
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
                    child: const Text("View My Brand Profile"),
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

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    instructionController.dispose();
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


class BrandCameraScreen extends StatefulWidget {
  final String challengeTitle;
  final String description;
  final String instructions;

  const BrandCameraScreen({
    super.key,
    required this.challengeTitle,
    required this.description,
    required this.instructions,
  });

  @override
  State<BrandCameraScreen> createState() => _BrandCameraScreenState();
}

class _BrandCameraScreenState extends State<BrandCameraScreen> {
  CameraController? controller;
  bool recording = false;
  XFile? videoFile;
  int selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    initCamera(selectedCameraIndex);
  }

  Future<void> initCamera(int cameraIndex) async {
    if (cameras.isEmpty) return;

    controller?.dispose();

    controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.medium,
    );

    await controller!.initialize();

    if (mounted) {
      setState(() {
        selectedCameraIndex = cameraIndex;
      });
    }
  }

  Future<void> switchCamera() async {
    if (cameras.length < 2 || recording) return;

    final nextIndex = selectedCameraIndex == 0 ? 1 : 0;
    await initCamera(nextIndex);
  }

  Future<void> recordVideo() async {
    if (controller == null || !controller!.value.isInitialized) return;

    if (!recording) {
      await controller!.startVideoRecording();
      setState(() => recording = true);
    } else {
      videoFile = await controller!.stopVideoRecording();
      setState(() => recording = false);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Record Challenge Video"),
        actions: [
          IconButton(
            onPressed: switchCamera,
            icon: const Icon(Icons.flip_camera_android),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CameraPreview(controller!),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: recordVideo,
                    child: Text(recording ? "Stop Recording" : "Record Video"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: videoFile == null
                        ? null
                        : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BrandPreviewScreen(
                            videoPath: videoFile!.path,
                            challengeTitle: widget.challengeTitle,
                            description: widget.description,
                            instructions: widget.instructions,
                          ),
                        ),
                      );
                    },
                    child: const Text("Preview Video"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        videoFile = null;
                        recording = false;
                      });
                    },
                    child: const Text("Record Again"),
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


class BrandPreviewScreen extends StatefulWidget {
  final String videoPath;
  final String challengeTitle;
  final String description;
  final String instructions;

  const BrandPreviewScreen({
    super.key,
    required this.videoPath,
    required this.challengeTitle,
    required this.description,
    required this.instructions,
  });

  @override
  State<BrandPreviewScreen> createState() => _BrandPreviewScreenState();
}

class _BrandPreviewScreenState extends State<BrandPreviewScreen> {
  late VideoPlayerController _controller;
  bool isUploading = false;

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

  Future<void> submitChallenge() async {
    try {
      setState(() => isUploading = true);

      final user = FirebaseAuth.instance.currentUser;
      final file = File(widget.videoPath);

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
        'title': widget.challengeTitle,
        'description': widget.description,
        'instructions': widget.instructions,
        'videoUrl': videoUrl,
        'creatorId': user.uid,
        'status': 'pending',
        'rejectionReason': '',
        'createdAt': Timestamp.now(),
      });

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const CreatorChallengeSubmittedScreen(),
        ),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => isUploading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  void recordAgain() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Preview Video")),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isUploading ? null : submitChallenge,
                    child: isUploading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Submit"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: isUploading ? null : recordAgain,
                    child: const Text("Record Again"),
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
              Tab(text: "Brand Requests"),
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
          return const Center(child: Text("No brand requests"));
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
    try {
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

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Submission approved successfully")),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Approve failed: $e")),
      );
    }
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
                                  : "This brand has not added a bio yet.",
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
      appBar: AppBar(title: const Text("Explore Brands")),
      body: Column(
        children: [
          /// SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search brands...",
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
        title: const Text("Brand Admin Panel"),
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
              child: Text("Error: ${challengeSnapshot.error}"),
            );
          }

          if (challengeSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final challenges = challengeSnapshot.data?.docs ?? [];

          final challengeTitles = challenges
              .map((doc) =>
          (doc.data() as Map<String, dynamic>)['title']?.toString() ?? '')
              .where((title) => title.isNotEmpty)
              .toSet()
              .toList();

          if (challengeTitles.isEmpty) {
            return const Center(
              child: Text("No approved brand challenges yet."),
            );
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('submissions').snapshots(),
            builder: (context, submissionSnapshot) {
              if (submissionSnapshot.hasError) {
                return Center(
                  child: Text("Error: ${submissionSnapshot.error}"),
                );
              }

              if (submissionSnapshot.connectionState ==
                  ConnectionState.waiting) {
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

              final uniqueUserIds = creatorSubmissions
                  .map((doc) =>
              (doc.data() as Map<String, dynamic>)['userId']?.toString() ?? '')
                  .where((id) => id.isNotEmpty)
                  .toSet()
                  .toList();

              final uniqueUsers = uniqueUserIds.length;

              final averageVideosPerUser =
              uniqueUsers == 0 ? 0.0 : totalSubmissions / uniqueUsers;

              // Frontend-only placeholder for now
              const costPerUser = "₹0";

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
                          child: GestureDetector(
                            onTap: uniqueUserIds.isEmpty
                                ? null
                                : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BrandParticipantsScreen(
                                    userIds: uniqueUserIds,
                                  ),
                                ),
                              );
                            },
                            child: _reportCard(
                              title: "Unique Users",
                              value: "$uniqueUsers",
                              icon: Icons.people,
                              color: Colors.orange,
                              subtitle: "Tap to view",
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _reportCard(
                            title: "Total Submissions",
                            value: "$totalSubmissions",
                            icon: Icons.video_collection,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _reportCard(
                            title: "Average Videos/User",
                            value: averageVideosPerUser.toStringAsFixed(1),
                            icon: Icons.analytics,
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
                            title: "Cost Per User",
                            value: costPerUser,
                            icon: Icons.currency_rupee,
                            color: Colors.pink,
                            subtitle: "Frontend only",
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: SizedBox(),
                        ),
                      ],
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

                        final challengeSubmissions =
                        creatorSubmissions.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return data['challengeTitle'] == title;
                        }).toList();

                        final totalChallengeSubmissions = challengeSubmissions.length;
                        final challengeUserIds = challengeSubmissions
                            .map((doc) => (doc.data()
                        as Map<String, dynamic>)['userId']
                            ?.toString() ??
                            '')
                            .where((id) => id.isNotEmpty)
                            .toSet()
                            .toList();

                        final challengeUniqueUsers = challengeUserIds.length;
                        final avgVideosPerUser = challengeUniqueUsers == 0
                            ? 0.0
                            : totalChallengeSubmissions / challengeUniqueUsers;

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
                              Text("Total Submissions: $totalChallengeSubmissions"),
                              Text("Unique Users: $challengeUniqueUsers"),
                              Text(
                                "Average Videos/User: ${avgVideosPerUser.toStringAsFixed(1)}",
                              ),
                              const Text("Cost Per User: ₹0"),
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
    String? subtitle,
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
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.deepPurple,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class BrandParticipantsScreen extends StatelessWidget {
  final List<String> userIds;

  const BrandParticipantsScreen({
    super.key,
    required this.userIds,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Participants"),
      ),
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
                return const Card(
                  child: ListTile(
                    title: Text("Loading..."),
                  ),
                );
              }

              final data =
                  snapshot.data!.data() as Map<String, dynamic>? ?? {};

              final name = data['name'] ?? 'User';
              final username = data['username'] ?? '';
              final totalRewards = data['totalRewards'] ?? 0;

              return Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text(name),
                  subtitle: Text("@$username"),
                  trailing: Text("$totalRewards pts"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ParticipantProfileScreen(
                          userId: userId,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ParticipantProfileScreen extends StatelessWidget {
  final String userId;

  const ParticipantProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Participant Profile"),
      ),
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
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "@$username",
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email,
                  style: const TextStyle(
                    color: Colors.black54,
                  ),
                ),
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



