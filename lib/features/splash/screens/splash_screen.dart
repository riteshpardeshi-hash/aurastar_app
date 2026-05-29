import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  late final List<AnimationController> _ctrl;
  late final AnimationController _orbPulse;
  late final Animation<double> _orbScale;
  final List<Timer> _timers = [];

  static const _durations = [2800, 3000, 3000, 3200]; // ms per slide

  @override
  void initState() {
    super.initState();
    _ctrl = List.generate(
      4,
      (_) => AnimationController(
          vsync: this, duration: const Duration(milliseconds: 750)),
    );
    _orbPulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100));
    _orbScale = Tween<double>(begin: 0.80, end: 1.20).animate(
        CurvedAnimation(parent: _orbPulse, curve: Curves.easeInOut));
    _startSequence();
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

  void _goToApp() {
    for (final t in _timers) {
      t.cancel();
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

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    for (final c in _ctrl) {
      c.dispose();
    }
    _orbPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: KeyedSubtree(
          key: ValueKey(_slide),
          child: _buildSlide(_slide, size),
        ),
      ),
    );
  }

  Widget _buildSlide(int slide, Size size) {
    switch (slide) {
      case 0:
        return _screen1Logo(size);
      case 1:
        return _screen2SeeIt(size);
      case 2:
        return _screen3YourMoves(size);
      case 3:
        return _screen4ClimbBoard(size);
      default:
        return const SizedBox.shrink();
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

          // "Play. Score. Flex." – upper
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

          // Star icon + AURA ARENA – center
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

          // Orb + "Charging your aura…" – bottom
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
    final fade = _fadeIn(c);
    final up = _up(c);
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed background: person + purple portal + challenge cards
          Image.asset(
            'assets/images/Splash screen/bg 2.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),

          // Gradient: image fades to black in lower half
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.40, 0.58, 0.74, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.50),
                    Colors.black.withValues(alpha: 0.92),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          // Content
          FadeTransition(
            opacity: fade,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // AURA ARENA header
                Positioned(
                  top: size.height * 0.055,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Image.asset(
                      'assets/images/Splash screen/logo.png',
                      width: size.width * 0.44,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // Bottom content block
                Positioned(
                  bottom: size.height * 0.042,
                  left: size.width * 0.06,
                  right: size.width * 0.06,
                  child: SlideTransition(
                    position: up,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Icon row with dividers
                        _iconRow(
                          size: size,
                          icon: 'assets/images/Splash screen/ICON.png',
                          iconSize: size.width * 0.12,
                        ),
                        SizedBox(height: size.height * 0.020),

                        // Title (PNG asset — correct font)
                        Image.asset(
                          'assets/images/Splash screen/See It. Copy It. Slay It.png',
                          width: size.width * 0.88,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: size.height * 0.014),

                        // Subtitle (PNG asset — correct font)
                        Image.asset(
                          'assets/images/Splash screen/Copy the challenge as close as you can.png',
                          width: size.width * 0.82,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: size.height * 0.028),

                        // Page dots — screen 1 of 3
                        _dots(active: 0, size: size),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Screen 3 — Your Moves. Your Score. Your Aura.
  // ───────────────────────────────────────────────────────────────────────────
  Widget _screen3YourMoves(Size size) {
    final c = _ctrl[2];
    final fade = _fadeIn(c);
    final elastic = _elastic(c);
    final up = _up(c);
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => Stack(
        fit: StackFit.expand,
        children: [
          // Neon 4-pointed star + floating crystals background
          Image.asset(
            'assets/images/Splash screen/BG 3.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),

          // Gradient: fades to black toward bottom
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.38, 0.56, 0.72, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.90),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          FadeTransition(
            opacity: fade,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // AURA ARENA header
                Positioned(
                  top: size.height * 0.055,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Image.asset(
                      'assets/images/Splash screen/logo.png',
                      width: size.width * 0.44,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // Bottom content block
                Positioned(
                  bottom: size.height * 0.042,
                  left: size.width * 0.06,
                  right: size.width * 0.06,
                  child: SlideTransition(
                    position: up,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Star icon 2 with dividers
                        _iconRow(
                          size: size,
                          icon: 'assets/images/Splash screen/Star icon 2.png',
                          iconSize: size.width * 0.11,
                          iconWidget: ScaleTransition(
                            scale: elastic,
                            child: Image.asset(
                              'assets/images/Splash screen/Star icon 2.png',
                              width: size.width * 0.11,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        SizedBox(height: size.height * 0.020),

                        // "Your Moves. Your Score." — white bold text
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

                        // "Your Aura." — PNG asset (purple text, correct font)
                        Image.asset(
                          'assets/images/Splash screen/headline.png',
                          width: size.width * 0.60,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: size.height * 0.010),

                        // Subtitle PNG — "The closer you get, the higher your Aura."
                        Image.asset(
                          'assets/images/Splash screen/Subhead.png',
                          width: size.width * 0.82,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: size.height * 0.028),

                        // Page dots — screen 2 of 3
                        _dots(active: 1, size: size),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Screen 4 — Climb the Board. Unlock Real Rewards.
  // ───────────────────────────────────────────────────────────────────────────
  Widget _screen4ClimbBoard(Size size) {
    final c = _ctrl[3];
    final fade = _fadeIn(c);
    final elastic = _elastic(c);
    final up = _up(c);
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => Stack(
        fit: StackFit.expand,
        children: [
          // Three leaderboard player cards background
          Image.asset(
            'assets/images/Splash screen/bg 4.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),

          // Gradient: fades to black
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.36, 0.54, 0.70, 1.0],
                  colors: [
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.45),
                    Colors.black.withValues(alpha: 0.92),
                    Colors.black,
                  ],
                ),
              ),
            ),
          ),

          FadeTransition(
            opacity: fade,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // AURA ARENA header
                Positioned(
                  top: size.height * 0.055,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Image.asset(
                      'assets/images/Splash screen/logo.png',
                      width: size.width * 0.44,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),

                // Bottom content block
                Positioned(
                  bottom: size.height * 0.042,
                  left: size.width * 0.06,
                  right: size.width * 0.06,
                  child: SlideTransition(
                    position: up,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Crown with dividers
                        _iconRow(
                          size: size,
                          icon: 'assets/images/Splash screen/Crown.png',
                          iconSize: size.width * 0.11,
                          iconWidget: ScaleTransition(
                            scale: elastic,
                            child: Image.asset(
                              'assets/images/Splash screen/Crown.png',
                              width: size.width * 0.11,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        SizedBox(height: size.height * 0.020),

                        // "Climb the Board. Unlock Real Rewards." — white bold text
                        Text(
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
                        SizedBox(height: size.height * 0.012),

                        // Subtitle PNG — "Level up faster and unlock offers…"
                        Image.asset(
                          'assets/images/Splash screen/subtext.png',
                          width: size.width * 0.82,
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: size.height * 0.024),

                        // Start Playing button (bg + text as stacked PNGs)
                        GestureDetector(
                          onTap: _goToApp,
                          child: SizedBox(
                            width: size.width * 0.88,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/Splash screen/button.png',
                                  width: size.width * 0.88,
                                  fit: BoxFit.contain,
                                ),
                                Image.asset(
                                  'assets/images/Splash screen/start text.png',
                                  width: size.width * 0.55,
                                  fit: BoxFit.contain,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared: icon row with horizontal dividers on each side
  // ───────────────────────────────────────────────────────────────────────────
  Widget _iconRow({
    required Size size,
    required String icon,
    required double iconSize,
    Widget? iconWidget,
  }) {
    final circleSize = iconSize * 1.9;
    return Row(
      children: [
        const Expanded(
          child: Divider(color: Colors.white24, thickness: 0.6),
        ),
        SizedBox(width: size.width * 0.03),
        Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 0.8),
          ),
          child: Center(
            child: iconWidget ??
                Image.asset(icon, width: iconSize, fit: BoxFit.contain),
          ),
        ),
        SizedBox(width: size.width * 0.03),
        const Expanded(
          child: Divider(color: Colors.white24, thickness: 0.6),
        ),
      ],
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
  // Animation helpers
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
}
