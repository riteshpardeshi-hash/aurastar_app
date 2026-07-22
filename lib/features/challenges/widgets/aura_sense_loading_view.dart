import 'dart:async';
import 'package:flutter/material.dart';

const List<String> kAuraSenseTrivia = [
  'When did the first modern fashion runway happen?',
  'The word "aura" comes from the Greek word for breeze.',
  'Confidence is the one accessory that never goes out of style.',
  'The first color photograph was taken in 1861.',
  'Your first impression forms in less than a second.',
  'Vintage denim can take up to a year to fade naturally.',
  'The catwalk got its name from a narrow backstage walkway.',
];

/// Full-screen "Aura Sense" animation — pulsing diamond, a percent counter
/// climbing to 92%, and rotating trivia — shown while a submission is
/// uploading/scoring. `POST /challenges/{id}/submissions` runs content-safety,
/// face verification, and rubric scoring synchronously and can take up to 90s
/// (see ChallengesService._scoringTimeout), so this exists to make that wait
/// look alive instead of a frozen progress bar with no explanation.
class AuraSenseLoadingView extends StatefulWidget {
  /// Shown as a tappable "Check My Account later" affordance once the wait
  /// passes 90s. Omit to hide that bail-out entirely.
  final VoidCallback? onGiveUp;

  const AuraSenseLoadingView({super.key, this.onGiveUp});

  @override
  State<AuraSenseLoadingView> createState() => _AuraSenseLoadingViewState();
}

class _AuraSenseLoadingViewState extends State<AuraSenseLoadingView>
    with TickerProviderStateMixin {
  bool _timedOut = false;
  Timer? _timeoutTimer;
  Timer? _triviaTimer;
  int _triviaIndex = 0;

  late final AnimationController _enterCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _percentCtrl;
  late final Animation<double> _enterFade;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _percentAnim;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _percentCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 14));

    _enterFade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeIn);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _percentAnim = Tween<double>(begin: 0, end: 92)
        .animate(CurvedAnimation(parent: _percentCtrl, curve: Curves.easeOutCubic));

    _enterCtrl.forward();
    _percentCtrl.forward();
    _triviaTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      setState(() => _triviaIndex = (_triviaIndex + 1) % kAuraSenseTrivia.length);
    });

    if (widget.onGiveUp != null) {
      _timeoutTimer = Timer(const Duration(seconds: 90), () {
        if (mounted) setState(() => _timedOut = true);
      });
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _triviaTimer?.cancel();
    _enterCtrl.dispose();
    _pulseCtrl.dispose();
    _percentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Image.asset(
              'assets/images/analysing/Asset 132.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _enterFade,
                    child: Image.asset('assets/images/analysing/Asset 133.png',
                        height: 32),
                  ),
                  const Spacer(flex: 5),
                  AnimatedBuilder(
                    animation: _percentAnim,
                    builder: (_, __) {
                      final pct = _percentAnim.value.round();
                      return ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.white, Color(0xFFC9A6FF)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(bounds),
                        child: Text(
                          '$pct%',
                          style: const TextStyle(
                            fontFamily: 'ClashDisplay',
                            color: Colors.white,
                            fontSize: 64,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Image.asset('assets/images/analysing/Asset 135.png', height: 16),
                  const SizedBox(height: 18),
                  Image.asset('assets/images/analysing/Asset 136.png', height: 60),
                  const Spacer(flex: 6),
                  if (!_timedOut) ...[
                    Image.asset('assets/images/analysing/Asset 137.png', height: 22),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        kAuraSenseTrivia[_triviaIndex],
                        key: ValueKey(_triviaIndex),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text('Taking longer than usual...',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            decoration: TextDecoration.none)),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: widget.onGiveUp,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B2CBF).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFF9B4DCA).withValues(alpha: 0.5)),
                        ),
                        child: const Text('Check My Account later',
                            style: TextStyle(
                                color: Color(0xFFD4A8FF),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
