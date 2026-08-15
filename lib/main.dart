import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/globals.dart';
import 'core/services/api_client.dart';
import 'core/services/challenges_service.dart';
import 'core/services/splash_gate.dart';
import 'core/utils/deep_link_validation.dart';
import 'firebase_options.dart';
import 'features/auth/screens/phone_auth_screen.dart';
import 'features/challenges/screens/challenge_detail.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/splash/screens/splash_screen.dart';
import 'shared/theme/app_colors.dart';
import 'shared/theme/app_text_styles.dart';

// Must be a top-level (or static) function — the FCM plugin runs it in a
// separate background isolate that hasn't executed main(), so Firebase
// needs its own init call here. No work is done beyond that: the OS tray
// notification for a background/terminated push is rendered natively by
// the FCM plugin without any app code involved.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  try {
    cameras = await availableCameras();
  } catch (_) {
    cameras = [];
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
  StreamSubscription<void>? _sessionExpiredSub;
  StreamSubscription<RemoteMessage>? _notificationTapSub;
  // Guards against a burst of near-simultaneous 401s (e.g. Dashboard's
  // Future.wait of several authed calls) each firing onSessionExpired and
  // triggering a duplicate navigation reset.
  bool _handlingSessionExpiry = false;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
    _initPushTapHandling();
    _sessionExpiredSub =
        ApiClient.onSessionExpired.listen((_) => _handleSessionExpired());
  }

  // Push payloads don't carry a documented per-type deep-link target today
  // (NudgeTemplate.deepLinkScreen is admin-editable copy, not a contract the
  // client can safely branch on), so tapping any push just surfaces the
  // in-app notification list rather than guessing a destination.
  Future<void> _initPushTapHandling() async {
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openNotifications());
    }
    _notificationTapSub =
        FirebaseMessaging.onMessageOpenedApp.listen((_) => _openNotifications());
  }

  void _openNotifications() {
    _navigatorKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  void _handleSessionExpired() {
    if (_handlingSessionExpiry) return;
    _handlingSessionExpiry = true;
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const PhoneAuthScreen()),
      (route) => false,
    );
    _scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text('Your session has expired. Please log in again.')),
    );
    Future.delayed(const Duration(seconds: 2), () {
      _handlingSessionExpiry = false;
    });
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
    if (deepLinkValidationError(uri) != null) {
      _showLinkError();
      return;
    }
    final segments = uri.pathSegments;

    if (segments[0] == 'challenge') {
      final challengeId = segments[1];
      final raw = await ChallengesService().fetchChallenge(challengeId);
      if (raw == null) {
        _showLinkError();
        return;
      }
      final data = normaliseChallenge(raw);
      // Wait for Splash's own post-boot navigation to land first (see
      // SplashGate) — otherwise its pushReplacement, which always replaces
      // whatever is currently on top of the navigator stack, would silently
      // discard this push if it happened to fire after us. The timeout is
      // just a safety net (e.g. a force-update dialog blocking Splash
      // forever) so a deep link can never hang indefinitely.
      await SplashGate.done.timeout(const Duration(seconds: 20), onTimeout: () {});
      if (!mounted) return;
      _navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ChallengeDetail(
          challengeId: challengeId,
          title: data['title'] as String,
          instructions: data['instructions'] as String,
          videoUrl: data['videoUrl'] as String,
        ),
      ));
    } else if (segments[0] == 'ref') {
      final code = segments[1].trim().toUpperCase();
      // Only save for new (not yet logged-in) users — existing users are ignored
      if (!await ApiClient().isLoggedIn()) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_referral_code', code);
      }
    }
  }

  void _showLinkError() {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      const SnackBar(content: Text("That link couldn't be opened.")),
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _sessionExpiredSub?.cancel();
    _notificationTapSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'SpaceGrotesk',
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // One convention app-wide — screens used to leave this unset and
          // silently inherit the platform default (centered on iOS, left on
          // Android), so the same screen's title alignment differed by OS
          // with nobody having chosen that on purpose.
          centerTitle: false,
          titleTextStyle: AppTextStyles.screenTitle,
        ),
        textTheme: const TextTheme(
          displayLarge: AppTextStyles.heroTitle,
          displayMedium: TextStyle(fontFamily: 'ClashDisplay'),
          displaySmall: TextStyle(fontFamily: 'ClashDisplay'),
          headlineLarge: AppTextStyles.compactTitle,
          headlineMedium: TextStyle(fontFamily: 'ClashDisplay'),
          headlineSmall: TextStyle(fontFamily: 'ClashDisplay'),
          titleLarge: AppTextStyles.screenTitle,
          titleMedium: AppTextStyles.sectionHeader,
          titleSmall: TextStyle(fontFamily: 'SpaceGrotesk'),
          bodyLarge: AppTextStyles.body,
          bodyMedium: AppTextStyles.body,
          bodySmall: AppTextStyles.caption,
          labelLarge: TextStyle(fontFamily: 'SpaceGrotesk'),
          labelMedium: TextStyle(fontFamily: 'SpaceGrotesk'),
          labelSmall: AppTextStyles.eyebrow,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
