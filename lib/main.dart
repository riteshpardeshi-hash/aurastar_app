import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_links/app_links.dart';
import 'core/globals.dart';
import 'firebase_options.dart';
import 'features/challenges/screens/challenge_detail.dart';
import 'features/splash/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Cold-start: app was opened via a link
    final initial = await _appLinks.getInitialLink();
    if (initial != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleLink(initial));
    }
    // Warm: app was already running when user tapped a link
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink, onError: (_) {});
  }

  Future<void> _handleLink(Uri uri) async {
    final segments = uri.pathSegments;
    // Expects paths like /challenge/{challengeId}
    if (segments.length < 2 || segments[0] != 'challenge') return;
    final challengeId = segments[1];
    if (challengeId.isEmpty) return;

    final doc = await FirebaseFirestore.instance
        .collection('challenges')
        .doc(challengeId)
        .get();
    if (!doc.exists) return;

    final data = doc.data()!;
    _navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => ChallengeDetail(
        challengeId: challengeId,
        title: data['title'] as String? ?? '',
        instructions: data['instructions'] as String? ?? '',
        videoUrl: data['videoUrl'] as String? ?? '',
      ),
    ));
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}
