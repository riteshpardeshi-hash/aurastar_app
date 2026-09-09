import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

enum _Phase { intro, playing, result }

class CatchTheAuraGame extends StatefulWidget {
  final int bestScore;
  final VoidCallback onBack;
  final void Function(int score) onFinish;

  const CatchTheAuraGame({
    super.key,
    required this.bestScore,
    required this.onBack,
    required this.onFinish,
  });

  @override
  State<CatchTheAuraGame> createState() => _CatchTheAuraGameState();
}

class _CatchTheAuraGameState extends State<CatchTheAuraGame>
    with SingleTickerProviderStateMixin {
  static const _gameSeconds = 20;
  static const _orbSize = 72.0;
  static const _pad = 12.0;

  static const _bg = Color(0xFF070B18);
  static const _surface = Color(0xFF11172B);
  static const _surfaceElevated = Color(0xFF18203A);
  static const _border = Color(0xFF293455);
  static const _text = Color(0xFFF7F8FF);
  static const _textMuted = Color(0xFF9CA8C7);
  static const _cyan = Color(0xFF48D7FF);

  _Phase _phase = _Phase.intro;
  int _timeLeft = _gameSeconds;
  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _hits = 0;
  int _misses = 0;
  Size _boardSize = Size.zero;
  Offset _orbPos = const Offset(30, 30);

  Timer? _countdown;
  Timer? _orbTimer;
  late final AnimationController _orbScale;

  @override
  void initState() {
    super.initState();
    _orbScale = AnimationController(
      vsync: this,
      lowerBound: 0.0,
      upperBound: 1.5,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _orbTimer?.cancel();
    _orbScale.dispose();
    super.dispose();
  }

  void _moveOrb() {
    if (_boardSize.width == 0 || _boardSize.height == 0) return;
    final maxX =
        (_boardSize.width - _orbSize - _pad).clamp(_pad, double.infinity);
    final maxY =
        (_boardSize.height - _orbSize - _pad).clamp(_pad, double.infinity);
    setState(() {
      _orbPos = Offset(
        _pad + Random().nextDouble() * (maxX - _pad),
        _pad + Random().nextDouble() * (maxY - _pad),
      );
    });
    _orbScale.value = 0.55;
    _orbScale.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 110, damping: 8),
      0.55,
      1.0,
      0,
    ));
  }

  void _scheduleOrb() {
    _orbTimer?.cancel();
    final windowMs = (950 - _hits * 22).clamp(470, 950);
    _orbTimer = Timer(Duration(milliseconds: windowMs), () {
      if (_phase != _Phase.playing || !mounted) return;
      setState(() {
        _combo = 0;
        _misses++;
      });
      _moveOrb();
      _scheduleOrb();
    });
  }

  void _start() {
    _countdown?.cancel();
    _orbTimer?.cancel();
    setState(() {
      _phase = _Phase.playing;
      _score = 0;
      _combo = 0;
      _bestCombo = 0;
      _hits = 0;
      _misses = 0;
      _timeLeft = _gameSeconds;
    });

    var remaining = _gameSeconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _timeLeft = remaining);
      if (remaining <= 0) {
        t.cancel();
        _finish();
      }
    });

    // Board is already visible during intro, so _boardSize is already set.
    _moveOrb();
    _scheduleOrb();
  }

  void _finish() {
    _countdown?.cancel();
    _orbTimer?.cancel();
    setState(() => _phase = _Phase.result);
    widget.onFinish(_score);
  }

  void _catchOrb() {
    if (_phase != _Phase.playing) return;
    _orbTimer?.cancel();
    final nextCombo = _combo + 1;
    final points = 10 + (nextCombo - 1).clamp(0, 10) * 2;
    setState(() {
      _combo = nextCombo;
      _score += points;
      _bestCombo = nextCombo > _bestCombo ? nextCombo : _bestCombo;
      _hits++;
    });
    _moveOrb();
    _scheduleOrb();
  }

  int get _accuracy {
    final total = _hits + _misses;
    return total == 0 ? 0 : (_hits * 100 ~/ total);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(
            children: [
              // ── Nav ──────────────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: widget.onBack,
                    child: const Text(
                      'BACK',
                      style: TextStyle(
                        color: _textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                  ),
                  const Text(
                    'PRECISION',
                    style: TextStyle(
                      color: _cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                  Text(
                    'BEST ${widget.bestScore}',
                    style: const TextStyle(
                      color: _textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ],
              ),

              // ── Title + timer pill ────────────────────────────────────────────
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Catch The Aura',
                          style: TextStyle(
                            color: _text,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            fontFamily: 'ClashDisplay',
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Catch it before it fades.',
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 14,
                            fontFamily: 'SpaceGrotesk',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 62),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _surfaceElevated,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$_timeLeft',
                          style: const TextStyle(
                            color: _text,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'ClashDisplay',
                          ),
                        ),
                        const Text(
                          'SEC',
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            fontFamily: 'SpaceGrotesk',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Stats row ─────────────────────────────────────────────────────
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _stat('SCORE', '$_score', _text),
                  _stat('COMBO', 'x$_combo', _cyan, align: CrossAxisAlignment.end),
                ],
              ),

              // ── Board ─────────────────────────────────────────────────────────
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(builder: (ctx, constraints) {
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  if (_boardSize != size) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _boardSize = size);
                    });
                  }
                  return Container(
                    clipBehavior: Clip.hardEdge,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: _border),
                    ),
                    child: Stack(
                      children: [
                        // Orb (playing phase only)
                        if (_phase == _Phase.playing &&
                            _boardSize.width > 0)
                          Positioned(
                            left: _orbPos.dx,
                            top: _orbPos.dy,
                            child: ScaleTransition(
                              scale: _orbScale,
                              child: GestureDetector(
                                onTap: _catchOrb,
                                child: Container(
                                  width: _orbSize,
                                  height: _orbSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF2FC9F3),
                                    border: Border.all(
                                        color: const Color(0xFFC5F6FF),
                                        width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _cyan.withValues(alpha: 0.9),
                                        blurRadius: 20,
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: _text,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // Intro overlay
                        if (_phase == _Phase.intro)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 34),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Text(
                                  'HOW TO PLAY',
                                  style: TextStyle(
                                    color: _cyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.8,
                                    fontFamily: 'SpaceGrotesk',
                                  ),
                                ),
                                SizedBox(height: 12),
                                Text(
                                  'Follow the glow',
                                  style: TextStyle(
                                    color: _text,
                                    fontSize: 27,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'ClashDisplay',
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Tap each aura before it moves. Build a combo for bonus points. The pace gets faster as you improve.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _textMuted,
                                    fontSize: 14,
                                    height: 1.5,
                                    fontFamily: 'SpaceGrotesk',
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Result overlay
                        if (_phase == _Phase.result)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 34),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'RUN COMPLETE',
                                  style: TextStyle(
                                    color: _cyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.8,
                                    fontFamily: 'SpaceGrotesk',
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  '$_score',
                                  style: const TextStyle(
                                    color: _text,
                                    fontSize: 54,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'ClashDisplay',
                                  ),
                                ),
                                Text(
                                  '$_hits caught · $_accuracy% accuracy · best combo x$_bestCombo',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: _textMuted,
                                    fontSize: 14,
                                    height: 1.5,
                                    fontFamily: 'SpaceGrotesk',
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),

              // ── Start / Play Again button ──────────────────────────────────────
              const SizedBox(height: 16),
              AnimatedOpacity(
                opacity: _phase != _Phase.playing ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: GestureDetector(
                  onTap: _phase != _Phase.playing ? _start : null,
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: _cyan,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Text(
                        _phase == _Phase.result ? 'PLAY AGAIN' : 'START RUN',
                        style: const TextStyle(
                          color: _bg,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                          fontFamily: 'SpaceGrotesk',
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
    );
  }

  Widget _stat(String label, String value, Color valueColor,
      {CrossAxisAlignment align = CrossAxisAlignment.start}) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            fontFamily: 'SpaceGrotesk',
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            fontFamily: 'ClashDisplay',
          ),
        ),
      ],
    );
  }
}
