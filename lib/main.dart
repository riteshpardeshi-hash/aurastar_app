import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/globals.dart';
import 'core/services/api_client.dart';
import 'core/services/auth_api_service.dart';
import 'core/services/boot_gate.dart';
import 'core/services/challenges_service.dart';
import 'core/utils/deep_link_validation.dart';
import 'firebase_options.dart';
import 'features/auth/screens/phone_auth_screen.dart';
import 'features/auth/screens/profile_setup_screen.dart';
import 'features/challenges/screens/challenge_detail.dart';
import 'features/dashboard/dashboard.dart';
import 'features/notifications/notifications_screen.dart';
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
    // Bounded: on some devices/networks this call has been observed to
    // never resolve rather than throw, which — since nothing after it runs
    // until it settles — left the app stuck before runApp() ever fired
    // (device shows the native launch image forever, with no Flutter code
    // running yet to recover from it).
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  try {
    cameras = await availableCameras().timeout(const Duration(seconds: 5));
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
      // Wait for the boot screen's own post-boot navigation to land first
      // (see BootGate) — otherwise its pushReplacement, which always
      // replaces whatever is currently on top of the navigator stack, would
      // silently discard this push if it happened to fire after us. The
      // timeout is just a safety net (e.g. a force-update dialog blocking
      // boot forever) so a deep link can never hang indefinitely.
      await BootGate.done.timeout(const Duration(seconds: 20), onTimeout: () {});
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
      home: const _BootScreen(),
    );
  }
}

// Decides where the app lands (Dashboard/ProfileSetup/PhoneAuth) and gates
// that decision on a force/soft update check, without a dedicated
// onboarding screen — just a brief branded frame while the checks resolve.
class _BootScreen extends StatefulWidget {
  const _BootScreen();

  @override
  State<_BootScreen> createState() => _BootScreenState();
}

enum _VersionStatus { ok, softUpdate, forceUpdate }

class _BootScreenState extends State<_BootScreen> {
  static const _currentBuild = 12;

  // TEMPORARY diagnostics for the "stuck on boot" field report — some
  // affected devices can't be reproduced under adb (remote tester, no
  // physical/USB access), so this surfaces which await is still pending
  // directly on-screen instead. Shown only after a 3s grace period so a
  // normal fast boot never flashes it. Remove once the report is resolved.
  final _bootStopwatch = Stopwatch()..start();
  String _bootStep = 'starting';
  Timer? _diagTicker;
  bool _showDiag = false;

  void _setStep(String step) {
    _bootStep = step;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _diagTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!_showDiag && _bootStopwatch.elapsed.inSeconds >= 3) {
        setState(() => _showDiag = true);
      } else if (_showDiag) {
        setState(() {}); // just refresh the displayed elapsed time
      }
    });
    _boot();
  }

  @override
  void dispose() {
    _diagTicker?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    _setStep('checking app version');
    final version = await _checkVersion();
    if (!mounted) return;

    if (version.status == _VersionStatus.forceUpdate) {
      _setStep('force update required');
      _showForceUpdateDialog(version.storeUrl);
      return; // Stay put — the force-update dialog blocks further progress.
    }
    if (version.status == _VersionStatus.softUpdate) {
      _setStep('showing update prompt');
      await _showSoftUpdateDialog(version.storeUrl);
      if (!mounted) return;
    }

    _setStep('computing destination');
    Widget destination;
    try {
      // Safety net #1: a native platform-channel call (SharedPreferences) or
      // any other unbounded read in here must never leave the app stuck with
      // no usable screen — fall back to the recoverable login screen instead.
      destination = await _computeDestination().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          _setStep('destination timed out — falling back to login');
          return const PhoneAuthScreen();
        },
      );
    } catch (e) {
      // Safety net #2: .timeout() only guards against slowness — it does
      // nothing if a call throws outright instead of hanging (e.g. a
      // corrupted-Keystore PlatformException from secure storage on some
      // devices). Any such error must land the user on the recoverable
      // login screen too, never leave the boot sequence dead in the water.
      _setStep('destination computation failed — falling back to login');
      debugPrint('Boot destination computation failed: $e');
      destination = const PhoneAuthScreen();
    }
    if (!mounted) return;

    _setStep('navigating');
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => destination,
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
    BootGate.complete();
  }

  Future<Widget> _computeDestination() async {
    final authService = AuthApiService();
    _setStep('checking login status');
    final loggedIn = await authService.isLoggedIn();
    if (!loggedIn) return const PhoneAuthScreen();

    _setStep('reading local user id');
    final uid = await ApiClient().userId;
    _setStep('loading local preferences');
    final prefs = await SharedPreferences.getInstance();

    // Fast path: local flag set when this user finished onboarding.
    final localComplete =
        uid != null && (prefs.getBool('setup_complete_$uid') ?? false);
    if (localComplete) return const Dashboard();

    // Fall back to API check.
    _setStep('fetching profile from server');
    final profile = await authService.getProfile();

    // Consider setup complete if:
    //   • API explicitly says so, OR
    //   • Profile already has a username/name (completed before local flag
    //     was introduced), OR
    //   • API call failed entirely (don't block a logged-in returning user
    //     due to a network hiccup).
    final apiSaysComplete = profile?['isProfileComplete'] as bool? ?? false;
    final hasUsername = (profile?['profileName'] as String? ??
            profile?['username'] as String? ??
            '')
        .isNotEmpty;
    final hasName = (profile?['displayName'] as String? ?? '').isNotEmpty;
    final apiUnavailable = profile == null;

    final isComplete =
        apiSaysComplete || hasUsername || hasName || apiUnavailable;

    if (isComplete) {
      if (uid != null) await prefs.setBool('setup_complete_$uid', true);
      return const Dashboard();
    }
    return const ProfileSetupScreen();
  }

  Future<({_VersionStatus status, String storeUrl})> _checkVersion() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('version')
          .get()
          .timeout(const Duration(seconds: 3));
      if (!doc.exists) return (status: _VersionStatus.ok, storeUrl: '');
      final data = doc.data()!;
      final minBuild = (data['minBuildNumber'] as num?)?.toInt() ?? 0;
      final recBuild = (data['recommendedBuildNumber'] as num?)?.toInt() ?? 0;
      final storeUrl = Platform.isIOS
          ? (data['iosStoreUrl'] as String? ?? 'https://apps.apple.com/')
          : (data['androidStoreUrl'] as String? ?? 'https://play.google.com/');
      if (_currentBuild < minBuild) {
        return (status: _VersionStatus.forceUpdate, storeUrl: storeUrl);
      } else if (_currentBuild < recBuild) {
        return (status: _VersionStatus.softUpdate, storeUrl: storeUrl);
      }
      return (status: _VersionStatus.ok, storeUrl: storeUrl);
    } catch (_) {
      // Non-fatal: version check failure must never block app launch.
      return (status: _VersionStatus.ok, storeUrl: '');
    }
  }

  void _showForceUpdateDialog(String storeUrl) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF100A20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Update Required',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'A critical update is required to continue using Aura Arena. Please update to the latest version.',
            style: TextStyle(color: AppColors.textMuted, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => _launchStoreUrl(storeUrl),
              child: const Text(
                'Update Now',
                style: TextStyle(
                    color: Color(0xFF7B2CBF),
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSoftUpdateDialog(String storeUrl) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF100A20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Update Available',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'A new version of Aura Arena is available with improvements and new features.',
          style: TextStyle(color: AppColors.textMuted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Later',
                style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launchStoreUrl(storeUrl);
            },
            child: const Text(
              'Update',
              style: TextStyle(
                  color: Color(0xFF7B2CBF),
                  fontWeight: FontWeight.w700,
                  fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchStoreUrl(String storeUrl) async {
    final uri = Uri.tryParse(storeUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/Splash screen/Aura arena.png',
              width: width * 0.55,
              fit: BoxFit.contain,
            ),
            if (_showDiag) ...[
              const SizedBox(height: 28),
              Text(
                '$_bootStep · ${_bootStopwatch.elapsed.inSeconds}s',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
