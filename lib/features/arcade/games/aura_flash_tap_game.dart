import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

enum _Phase { intro, waiting, ready, result }

class AuraFlashTapGame extends StatefulWidget {
  final int bestScore;
  final VoidCallback onBack;
  final void Function(int score) onFinish;

  const AuraFlashTapGame({
    super.key,
    required this.bestScore,
    required this.onBack,
    required this.onFinish,
  });

  @override
  State<AuraFlashTapGame> createState() => _AuraFlashTapGameState();
}

class _AuraFlashTapGameState extends State<AuraFlashTapGame>
    with SingleTickerProviderStateMixin {
  static const _totalRounds = 5;
  static const _violet = Color(0xFF8C6CFF);
  static const _cyan = Color(0xFF48D7FF);
  static const _text = Color(0xFFF7F8FF);
  static const _textMuted = Color(0xFF9CA8C7);
  static const _surface = Color(0xFF11172B);
  static const _border = Color(0xFF293455);
  static const _bg = Color(0xFF070B18);

  _Phase _phase = _Phase.intro;
  int _round = 1;
  final List<int> _reactionTimes = [];
  String _message = 'Wait for the flash';
  DateTime? _readyAt;
  Timer? _timer;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      lowerBound: 0.5,
      upperBound: 1.5,
      value: 0.82,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _animateAura() {
    _pulse.value = 0.78;
    _pulse.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 90, damping: 6),
      0.78,
      1.0,
      0,
    ));
  }

  void _scheduleRound() {
    _timer?.cancel();
    setState(() {
      _phase = _Phase.waiting;
      _message = 'Hold...';
    });
    final delay = 1300 + Random().nextInt(2200);
    _timer = Timer(Duration(milliseconds: delay), () {
      if (!mounted) return;
      _readyAt = DateTime.now();
      setState(() {
        _phase = _Phase.ready;
        _message = 'TAP!';
      });
      _animateAura();
    });
  }

  void _start() {
    _timer?.cancel();
    setState(() {
      _round = 1;
      _reactionTimes.clear();
    });
    _scheduleRound();
  }

  void _finishRound(int reactionMs) {
    _reactionTimes.add(reactionMs);

    if (_round == _totalRounds) {
      final avg =
          _reactionTimes.reduce((a, b) => a + b) ~/ _reactionTimes.length;
      final score = (1200 - avg).clamp(100, 9999);
      setState(() {
        _phase = _Phase.result;
        _message = 'Run complete';
      });
      widget.onFinish(score);
      return;
    }

    setState(() => _message = '$reactionMs ms');
    _timer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _round++);
      _scheduleRound();
    });
  }

  void _handleTap() {
    if (_phase == _Phase.waiting) {
      _timer?.cancel();
      setState(() => _message = 'Too soon');
      _timer = Timer(const Duration(milliseconds: 900), () {
        if (mounted) _scheduleRound();
      });
      return;
    }
    if (_phase == _Phase.ready && _readyAt != null) {
      _finishRound(DateTime.now().difference(_readyAt!).inMilliseconds);
    }
  }

  int get _finalScore {
    if (_reactionTimes.isEmpty) return 0;
    final avg =
        _reactionTimes.reduce((a, b) => a + b) ~/ _reactionTimes.length;
    return (1200 - avg).clamp(100, 9999);
  }

  int get _avgMs {
    if (_reactionTimes.isEmpty) return 0;
    return _reactionTimes.reduce((a, b) => a + b) ~/ _reactionTimes.length;
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying =
        _phase == _Phase.waiting || _phase == _Phase.ready;
    final canStart =
        _phase == _Phase.intro || _phase == _Phase.result;

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
                  Text(
                    _phase == _Phase.intro
                        ? 'REACTION'
                        : 'ROUND $_round / $_totalRounds',
                    style: const TextStyle(
                      color: _violet,
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

              // ── Centre ───────────────────────────────────────────────────────
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Aura Flash Tap',
                      style: TextStyle(
                        color: _text,
                        fontSize: 31,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                        fontFamily: 'ClashDisplay',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _message,
                      style: const TextStyle(
                        color: _textMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'SpaceGrotesk',
                      ),
                    ),
                    const SizedBox(height: 30),

                    // Orb tap target
                    GestureDetector(
                      onTap: isPlaying ? _handleTap : null,
                      child: SizedBox(
                        width: 270,
                        height: 270,
                        child: Center(
                          child: ScaleTransition(
                            scale: _pulse,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              width: 210,
                              height: 210,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _phase == _Phase.ready
                                    ? const Color(0xFF6F4EFF)
                                    : const Color(0xFF202647),
                                border: Border.all(
                                  color: _phase == _Phase.ready
                                      ? const Color(0xFFB7A7FF)
                                      : _border,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _violet.withValues(
                                      alpha: _phase == _Phase.ready
                                          ? 0.95
                                          : 0.2,
                                    ),
                                    blurRadius: _phase == _Phase.ready
                                        ? 34
                                        : 24,
                                    spreadRadius:
                                        _phase == _Phase.ready ? 4 : 0,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _phase == _Phase.ready
                                        ? Colors.white
                                        : const Color(0xFF333B68),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_phase == _Phase.intro)
                      Column(
                        children: const [
                          Text(
                            'HOW TO PLAY',
                            style: TextStyle(
                              color: _cyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                              fontFamily: 'SpaceGrotesk',
                            ),
                          ),
                          SizedBox(height: 8),
                          SizedBox(
                            width: 300,
                            child: Text(
                              'Tap only when the aura turns bright. Five flashes. Fastest average wins.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _textMuted,
                                fontSize: 14,
                                height: 1.5,
                                fontFamily: 'SpaceGrotesk',
                              ),
                            ),
                          ),
                        ],
                      ),

                    if (_phase == _Phase.result)
                      Container(
                        constraints: const BoxConstraints(minWidth: 250),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _border),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'AURA SCORE',
                              style: TextStyle(
                                color: _cyan,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.7,
                                fontFamily: 'SpaceGrotesk',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$_finalScore',
                              style: const TextStyle(
                                color: _text,
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'ClashDisplay',
                              ),
                            ),
                            Text(
                              '$_avgMs ms average reaction',
                              style: const TextStyle(
                                color: _textMuted,
                                fontSize: 13,
                                fontFamily: 'SpaceGrotesk',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // ── Primary button ────────────────────────────────────────────────
              AnimatedOpacity(
                opacity: canStart ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: GestureDetector(
                  onTap: canStart ? _start : null,
                  child: Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: _violet,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Text(
                        _phase == _Phase.result ? 'PLAY AGAIN' : 'START RUN',
                        style: const TextStyle(
                          color: _text,
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
}
