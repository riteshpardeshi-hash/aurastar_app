import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/screens/auth_choice_screen.dart';
import '../../dashboard/dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  int _slide = 0; // 0=logo  1=see-it  2=your-moves  3=climb-board

  // Version check (runs in parallel with splash animation)
  _VersionStatus _versionStatus = _VersionStatus.ok;
  String _storeUrl = '';

  late final List<AnimationController> _ctrl;
  late final AnimationController _orbPulse;
  late final Animation<double> _orbScale;
  // Shared repeating animations for onboarding slides
  late final AnimationController _iconGlow; // pulsing glow on icon circle
  late final AnimationController _btnGlow;  // pulsing glow on Start Playing button
  late final AnimationController _starSpin; // continuous slow rotation on star
  final List<Timer> _timers = [];

  static const _durations = [2800, 3000, 3000, 3200]; // ms per slide

  @override
  void initState() {
    super.initState();
    _ctrl = List.generate(
      4,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 850)),
    );
    _orbPulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _orbScale = Tween<double>(begin: 0.80, end: 1.20).animate(
        CurvedAnimation(parent: _orbPulse, curve: Curves.easeInOut));
    _iconGlow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _btnGlow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat(reverse: true);
    _starSpin = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
    _startSequence();
    _checkVersion();
  }

  void _startSequence() {
    _ctrl[0].forward();
    _orbPulse.repeat(reverse: true);
    int ms = 0;
    for (int i = 0; i < _durations.length; i++) {
      ms += _durations[i];
      final target = i + 1;
      _timers.add(Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        if (target < 4) {
          setState(() => _slide = target);
          _ctrl[target].forward();
        } else {
          _goToApp();
        }
      }));
    }
  }

  Future<void> _goToApp() async {
    for (final t in _timers) { t.cancel(); }
    if (!mounted) return;

    if (_versionStatus == _VersionStatus.forceUpdate) {
      _showForceUpdateDialog();
      return; // Stay on splash — user must update
    }
    if (_versionStatus == _VersionStatus.softUpdate && mounted) {
      await _showSoftUpdateDialog();
    }
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, __, ___) =>
          user != null ? const Dashboard() : const AuthChoiceScreen(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  // ── Version check ───────────────────────────────────────────────────────────

  static const _currentBuild = 12;

  Future<void> _checkVersion() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('appConfig')
          .doc('version')
          .get();
      if (!mounted || !doc.exists) return;
      final data = doc.data()!;
      final minBuild = (data['minBuildNumber'] as num?)?.toInt() ?? 0;
      final recBuild = (data['recommendedBuildNumber'] as num?)?.toInt() ?? 0;
      _storeUrl = Platform.isIOS
          ? (data['iosStoreUrl'] as String? ?? 'https://apps.apple.com/')
          : (data['androidStoreUrl'] as String? ?? 'https://play.google.com/');
      if (_currentBuild < minBuild) {
        setState(() => _versionStatus = _VersionStatus.forceUpdate);
      } else if (_currentBuild < recBuild) {
        setState(() => _versionStatus = _VersionStatus.softUpdate);
      }
    } catch (_) {
      // Non-fatal: version check failure must never block app launch
    }
  }

  void _showForceUpdateDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF100A20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Update Required',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'A critical update is required to continue using Aura Arena. Please update to the latest version.',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => _launchStoreUrl(),
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

  Future<void> _showSoftUpdateDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF100A20),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Update Available',
          style:
              TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'A new version of Aura Arena is available with improvements and new features.',
          style: TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Later',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 14),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _launchStoreUrl();
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

  Future<void> _launchStoreUrl() async {
    final uri = Uri.tryParse(_storeUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    for (final t in _timers) { t.cancel(); }
    for (final c in _ctrl) { c.dispose(); }
    _orbPulse.dispose();
    _iconGlow.dispose();
    _btnGlow.dispose();
    _starSpin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        transitionBuilder: (child, anim) {
          final scale = Tween<double>(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOut));
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: ScaleTransition(scale: scale, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_slide),
          child: _buildSlide(_slide, size),
        ),
      ),
    );
  }

  Widget _buildSlide(int slide, Size size) {
    switch (slide) {
      case 0:  return _screen1Logo(size);
      case 1:  return _screen2SeeIt(size);
      case 2:  return _screen3YourMoves(size);
      case 3:  return _screen4ClimbBoard(size);
      default: return const SizedBox.shrink();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Screen 1 — Logo / Loading
  // ───────────────────────────────────────────────────────────────────────────
  Widget _screen1Logo(Size size) {
    final c = _ctrl[0];
    final fade = _fadeIn(c);
    final elastic = _elastic(c);
    final up = _up(c);
    return AnimatedBuilder(
      animation: Listenable.merge([c, _orbPulse]),
      builder: (_, __) => Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/Splash screen/BG.png', fit: BoxFit.cover),

          Positioned(
            top: size.height * 0.17,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: up,
                child: Center(
                  child: Image.asset(
                    'assets/images/Splash screen/Play score flex.png',
                    width: size.width * 0.70,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),

          Center(
            child: FadeTransition(
              opacity: fade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: elastic,
                    child: Image.asset(
                      'assets/images/Splash screen/Star icon.png',
                      width: size.width * 0.22,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(height: size.height * 0.022),
                  SlideTransition(
                    position: up,
                    child: Image.asset(
                      'assets/images/Splash screen/Aura arena.png',
                      width: size.width * 0.78,
                      fit: BoxFit.contain,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: size.height * 0.10,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: fade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: _orbScale,
                    child: Image.asset(
                      'assets/images/Splash screen/Orb.png',
                      width: size.width * 0.17,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(height: size.height * 0.014),
                  Image.asset(
                    'assets/images/Splash screen/Charging your aura.png',
                    width: size.width * 0.58,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Screen 2 — See It. Copy It. Slay It.
  // ───────────────────────────────────────────────────────────────────────────
  Widget _screen2SeeIt(Size size) {
    final c = _ctrl[1];
    return AnimatedBuilder(
      animation: Listenable.merge([c, _iconGlow]),
      builder: (_, __) {
        final iconScale  = _iconEntrance(c);
        final logoFade   = _logoEntrance(c);
        final titleFade  = _titleEntrance(c);
        final titleSlide = _titleSlideAnim(c);
        final subFade    = _subtitleEntrance(c);
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/Splash screen/onbarding-screen-bg.jpg',
              fit: BoxFit.cover,
            ),

            // Logo fades in from top
            Positioned(
              top: size.height * 0.055,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: logoFade,
                child: Center(
                  child: Image.asset(
                    'assets/images/Splash screen/logo.png',
                    width: size.width * 0.44,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // Staggered centered content
            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Icon: elastic pop-in + glow ring
                    ScaleTransition(
                      scale: iconScale,
                      child: _glowCircle(
                        iconSize: size.width * 0.12,
                        glowValue: _iconGlow.value,
                        child: Image.asset(
                          'assets/images/Splash screen/ICON.png',
                          width: size.width * 0.12,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.028),

                    // Title: slides up
                    FadeTransition(
                      opacity: titleFade,
                      child: SlideTransition(
                        position: titleSlide,
                        child: Text(
                          'See It. Copy It. Slay It.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: size.width * 0.072,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.014),

                    // Subtitle: fades in last
                    FadeTransition(
                      opacity: subFade,
                      child: Text(
                        'Copy the challenge as close as you can.\nAuraSense is watching.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: size.width * 0.038,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Dots fade in with subtitle
            Positioned(
              bottom: size.height * 0.05,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: subFade,
                child: Center(child: _dots(active: 0, size: size)),
              ),
            ),
          ],
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Screen 3 — Your Moves. Your Score. Your Aura.
  // ───────────────────────────────────────────────────────────────────────────
  Widget _screen3YourMoves(Size size) {
    final c = _ctrl[2];
    return AnimatedBuilder(
      animation: Listenable.merge([c, _iconGlow, _starSpin]),
      builder: (_, __) {
        final iconScale  = _iconEntrance(c);
        final logoFade   = _logoEntrance(c);
        final titleFade  = _titleEntrance(c);
        final titleSlide = _titleSlideAnim(c);
        final subFade    = _subtitleEntrance(c);
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/Splash screen/onbarding-screen-bg.jpg',
              fit: BoxFit.cover,
            ),

            Positioned(
              top: size.height * 0.055,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: logoFade,
                child: Center(
                  child: Image.asset(
                    'assets/images/Splash screen/logo.png',
                    width: size.width * 0.44,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Star: elastic pop + continuous slow rotation + glow
                    ScaleTransition(
                      scale: iconScale,
                      child: _glowCircle(
                        iconSize: size.width * 0.12,
                        glowValue: _iconGlow.value,
                        child: RotationTransition(
                          turns: _starSpin,
                          child: Image.asset(
                            'assets/images/Splash screen/star motion.png',
                            width: size.width * 0.12,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.028),

                    FadeTransition(
                      opacity: titleFade,
                      child: SlideTransition(
                        position: titleSlide,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Your Moves.Your Score.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: size.width * 0.072,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                height: 1.1,
                              ),
                            ),
                            Text(
                              'Your Aura.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: const Color(0xFF7B2CBF),
                                fontSize: size.width * 0.072,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.014),

                    FadeTransition(
                      opacity: subFade,
                      child: Text(
                        'The closer you get, the higher your Aura.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: size.width * 0.038,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: size.height * 0.05,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: subFade,
                child: Center(child: _dots(active: 1, size: size)),
              ),
            ),
          ],
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Screen 4 — Climb the Board. Unlock Real Rewards.
  // ───────────────────────────────────────────────────────────────────────────
  Widget _screen4ClimbBoard(Size size) {
    final c = _ctrl[3];
    return AnimatedBuilder(
      animation: Listenable.merge([c, _iconGlow, _btnGlow]),
      builder: (_, __) {
        final iconScale  = _iconEntrance(c);
        final logoFade   = _logoEntrance(c);
        final titleFade  = _titleEntrance(c);
        final titleSlide = _titleSlideAnim(c);
        final subFade    = _subtitleEntrance(c);
        final btnFade    = _btnEntrance(c);
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/Splash screen/onbarding-screen-bg.jpg',
              fit: BoxFit.cover,
            ),

            Positioned(
              top: size.height * 0.055,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: logoFade,
                child: Center(
                  child: Image.asset(
                    'assets/images/Splash screen/logo.png',
                    width: size.width * 0.44,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.06),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: iconScale,
                      child: _glowCircle(
                        iconSize: size.width * 0.12,
                        glowValue: _iconGlow.value,
                        child: Image.asset(
                          'assets/images/Splash screen/Crown.png',
                          width: size.width * 0.12,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.028),

                    FadeTransition(
                      opacity: titleFade,
                      child: SlideTransition(
                        position: titleSlide,
                        child: Text(
                          'Climb the Board.\nUnlock Real Rewards.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: size.width * 0.068,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.012),

                    FadeTransition(
                      opacity: subFade,
                      child: Text(
                        'Level up faster and unlock offers\nfrom the brands you love.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: size.width * 0.038,
                          height: 1.5,
                        ),
                      ),
                    ),
                    SizedBox(height: size.height * 0.036),

                    // Button fades in last with a breathing glow
                    FadeTransition(
                      opacity: btnFade,
                      child: GestureDetector(
                        onTap: _goToApp,
                        child: Container(
                          width: size.width * 0.88,
                          height: size.height * 0.068,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF5A1A9A), Color(0xFF9D4EDD)],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: const Color(0xFF9D4EDD).withValues(alpha: 0.6),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF9D4EDD).withValues(
                                    alpha: 0.25 + 0.35 * _btnGlow.value),
                                blurRadius: 16 + 22 * _btnGlow.value,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'Start Playing',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: size.width * 0.045,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: size.height * 0.05,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: subFade,
                child: Center(child: _dots(active: 2, size: size)),
              ),
            ),
          ],
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared: icon in a pulsing glow circle
  // ───────────────────────────────────────────────────────────────────────────
  Widget _glowCircle({
    required double iconSize,
    required double glowValue,
    required Widget child,
  }) {
    final circleSize = iconSize * 1.9;
    return Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Color.lerp(
            Colors.white24,
            const Color(0xFF9D4EDD),
            glowValue * 0.55,
          )!,
          width: 0.8 + glowValue * 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B2CBF)
                .withValues(alpha: 0.12 + 0.28 * glowValue),
            blurRadius: 8 + 20 * glowValue,
            spreadRadius: 1 + 4 * glowValue,
          ),
        ],
      ),
      child: Center(child: child),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared: page dot indicator  active=0,1,2
  // ───────────────────────────────────────────────────────────────────────────
  Widget _dots({required int active, required Size size}) {
    final dotSize = size.width * 0.046;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.016),
          child: Image.asset(
            i == active
                ? 'assets/images/Splash screen/On page scroll icon.png'
                : 'assets/images/Splash screen/Grey scroll icon.png',
            width: dotSize,
            height: dotSize,
            fit: BoxFit.contain,
          ),
        );
      }),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Animation helpers — Screen 1 (legacy)
  // ───────────────────────────────────────────────────────────────────────────
  Animation<double> _fadeIn(AnimationController c) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.0, 0.55, curve: Curves.easeIn)));

  Animation<double> _elastic(AnimationController c) =>
      Tween<double>(begin: 0.40, end: 1.0).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.0, 0.82, curve: Curves.elasticOut)));

  Animation<Offset> _up(AnimationController c) =>
      Tween<Offset>(begin: const Offset(0, 0.26), end: Offset.zero).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.05, 0.70, curve: Curves.easeOut)));

  // ───────────────────────────────────────────────────────────────────────────
  // Animation helpers — Screens 2–4 (staggered entrance)
  // ───────────────────────────────────────────────────────────────────────────

  // Icon pops in first with elastic overshoot
  Animation<double> _iconEntrance(AnimationController c) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.0, 0.55, curve: Curves.elasticOut)));

  // Logo fades in quickly at the start
  Animation<double> _logoEntrance(AnimationController c) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.0, 0.40, curve: Curves.easeIn)));

  // Title slides up after icon settles
  Animation<double> _titleEntrance(AnimationController c) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.22, 0.65, curve: Curves.easeOut)));

  Animation<Offset> _titleSlideAnim(AnimationController c) =>
      Tween<Offset>(begin: const Offset(0, 0.30), end: Offset.zero).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.22, 0.65, curve: Curves.easeOut)));

  // Subtitle and dots fade in last
  Animation<double> _subtitleEntrance(AnimationController c) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.42, 0.88, curve: Curves.easeOut)));

  // Button fades in after subtitle on screen 4
  Animation<double> _btnEntrance(AnimationController c) =>
      Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: c, curve: const Interval(0.60, 1.0, curve: Curves.easeOut)));
}

enum _VersionStatus { ok, softUpdate, forceUpdate }
