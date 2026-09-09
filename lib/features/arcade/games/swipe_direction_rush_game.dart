import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

enum _Phase { intro, playing, result }
enum _Feedback { neutral, correct, wrong }
enum _Dir { up, right, down, left }

class SwipeDirectionRushGame extends StatefulWidget {
  final int bestScore;
  final VoidCallback onBack;
  final void Function(int score) onFinish;

  const SwipeDirectionRushGame({
    super.key,
    required this.bestScore,
    required this.onBack,
    required this.onFinish,
  });

  @override
  State<SwipeDirectionRushGame> createState() => _SwipeDirectionRushGameState();
}

class _SwipeDirectionRushGameState extends State<SwipeDirectionRushGame>
    with SingleTickerProviderStateMixin {
  static const _kGameSeconds = 20;
  static const _kSwipeThreshold = 34.0;
  static const _bg = Color(0xFF070B18);
  static const _surface = Color(0xFF0F1629);
  static const _surfaceElevated = Color(0xFF18203A);
  static const _surfacePurple = Color(0xFF1A0D38);
  static const _borderBright = Color(0xFF3A4870);
  static const _text = Color(0xFFF7F8FF);
  static const _textMuted = Color(0xFF9CA8C7);
  static const _violet = Color(0xFF8C6CFF);
  static const _pink = Color(0xFFFF62B7);
  static const _green = Color(0xFF36DCA2);
  static const _danger = Color(0xFFFF6577);

  _Phase _phase = _Phase.intro;
  _Dir _direction = _Dir.up;
  int _timeLeft = _kGameSeconds;
  int _score = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _correct = 0;
  int _misses = 0;
  _Feedback _feedback = _Feedback.neutral;
  bool _acceptingSwipe = false;

  Timer? _countdownTimer;
  Timer? _directionTimer;
  Timer? _nextTimer;
  Offset _panDelta = Offset.zero;

  late final AnimationController _arrowAnim;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _arrowAnim = AnimationController(
      vsync: this,
      lowerBound: 0.5,
      upperBound: 1.5,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _clearTimers();
    _arrowAnim.dispose();
    super.dispose();
  }

  void _clearTimers() {
    _countdownTimer?.cancel();
    _directionTimer?.cancel();
    _nextTimer?.cancel();
  }

  _Dir _nextDir(_Dir prev) {
    final choices = _Dir.values.where((d) => d != prev).toList();
    return choices[_rng.nextInt(choices.length)];
  }

  void _animateSignal() {
    _arrowAnim.value = 0.72;
    _arrowAnim.animateWith(SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 120, damping: 8),
      0.72, 1.0, 0,
    ));
  }

  void _showNext() {
    if (_phase != _Phase.playing) return;
    final next = _nextDir(_direction);
    final window = (1000 - _correct * 25).clamp(450, 1000);
    setState(() {
      _direction = next;
      _feedback = _Feedback.neutral;
      _acceptingSwipe = true;
    });
    _animateSignal();

    _directionTimer?.cancel();
    _directionTimer = Timer(Duration(milliseconds: window), () {
      if (_phase != _Phase.playing) return;
      setState(() { _acceptingSwipe = false; _combo = 0; _misses++; _feedback = _Feedback.wrong; });
      _nextTimer = Timer(const Duration(milliseconds: 180), _showNext);
    });
  }

  void _start() {
    _clearTimers();
    setState(() {
      _phase = _Phase.playing;
      _score = 0; _combo = 0; _bestCombo = 0;
      _correct = 0; _misses = 0;
      _feedback = _Feedback.neutral;
      _timeLeft = _kGameSeconds;
      _acceptingSwipe = false;
    });

    var rem = _kGameSeconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      rem--;
      if (mounted) setState(() => _timeLeft = rem);
      if (rem <= 0) { t.cancel(); _finish(); }
    });
    _showNext();
  }

  void _finish() {
    _clearTimers();
    widget.onFinish(_score);
    if (mounted) setState(() => _phase = _Phase.result);
  }

  void _handleSwipe(Offset delta) {
    if (_phase != _Phase.playing || !_acceptingSwipe) return;
    final dx = delta.dx;
    final dy = delta.dy;
    if (dx.abs() < _kSwipeThreshold && dy.abs() < _kSwipeThreshold) return;

    final swiped = dx.abs() > dy.abs()
        ? (dx > 0 ? _Dir.right : _Dir.left)
        : (dy > 0 ? _Dir.down : _Dir.up);

    setState(() => _acceptingSwipe = false);
    _directionTimer?.cancel();

    if (swiped == _direction) {
      final nc = _combo + 1;
      final pts = 20 + (nc - 1).clamp(0, 10) * 3;
      setState(() { _combo = nc; if (nc > _bestCombo) _bestCombo = nc; _correct++; _score += pts; _feedback = _Feedback.correct; });
      _nextTimer = Timer(const Duration(milliseconds: 120), _showNext);
    } else {
      setState(() { _combo = 0; _misses++; _feedback = _Feedback.wrong; });
      _nextTimer = Timer(const Duration(milliseconds: 220), _showNext);
    }
  }

  String _arrowFor(_Dir d) => switch (d) {
    _Dir.up => '↑', _Dir.right => '→', _Dir.down => '↓', _Dir.left => '←',
  };
  String _labelFor(_Dir d) => switch (d) {
    _Dir.up => 'UP', _Dir.right => 'RIGHT', _Dir.down => 'DOWN', _Dir.left => 'LEFT',
  };

  @override
  Widget build(BuildContext context) {
    final attempts = _correct + _misses;
    final accuracy = attempts > 0 ? (_correct / attempts * 100).round() : 0;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(
            children: [
              _buildNav(),
              const SizedBox(height: 18),
              _buildHeader(),
              const SizedBox(height: 18),
              _buildStats(),
              const SizedBox(height: 14),
              Expanded(child: _buildBoard(accuracy)),
              const SizedBox(height: 16),
              if (_phase != _Phase.playing) _buildButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNav() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      GestureDetector(
        onTap: widget.onBack,
        child: const Text('‹ ARCADE', style: TextStyle(color: _violet, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, fontFamily: 'SpaceGrotesk')),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: _borderBright), borderRadius: BorderRadius.circular(13)),
        child: Text('BEST ${widget.bestScore}', style: const TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'SpaceGrotesk')),
      ),
    ],
  );

  Widget _buildHeader() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('FOCUS', style: TextStyle(color: _pink, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 6),
            const Text('Swipe Direction Rush', style: TextStyle(color: _text, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.8, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 5),
            const Text('Read it. Swipe it. Keep moving.', style: TextStyle(color: _textMuted, fontSize: 13, fontFamily: 'SpaceGrotesk')),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: _surfaceElevated, borderRadius: BorderRadius.circular(17), border: Border.all(color: _borderBright)),
        child: Column(
          children: [
            Text('$_timeLeft', style: const TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            const Text('SEC', style: TextStyle(color: _textMuted, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 1, fontFamily: 'SpaceGrotesk')),
          ],
        ),
      ),
    ],
  );

  Widget _buildStats() => Row(
    children: [
      Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          decoration: BoxDecoration(color: _surfacePurple, borderRadius: BorderRadius.circular(18), border: Border.all(color: _violet)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SCORE', style: TextStyle(color: _text, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
              Text('$_score', style: const TextStyle(color: _text, fontSize: 36, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            ],
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
          decoration: BoxDecoration(color: _surfaceElevated, borderRadius: BorderRadius.circular(18), border: Border.all(color: _borderBright)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('COMBO', style: TextStyle(color: _text, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
              Text('x$_combo', style: const TextStyle(color: _violet, fontSize: 31, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _buildBoard(int accuracy) => GestureDetector(
    onPanStart: (_) => _panDelta = Offset.zero,
    onPanUpdate: (d) => _panDelta += d.delta,
    onPanEnd: (_) => _handleSwipe(_panDelta),
    child: Container(
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: _borderBright)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: _phase == _Phase.playing
            ? _buildPlaying()
            : _phase == _Phase.intro
                ? _buildIntro()
                : _buildResult(accuracy),
      ),
    ),
  );

  Widget _buildPlaying() {
    Color feedbackColor;
    Color discBorder;
    final feedbackText = switch (_feedback) {
      _Feedback.correct => 'CLEAN', _Feedback.wrong => 'MISSED', _Feedback.neutral => 'SWIPE',
    };
    switch (_feedback) {
      case _Feedback.correct: feedbackColor = _green; discBorder = _green;
      case _Feedback.wrong: feedbackColor = _danger; discBorder = _danger;
      case _Feedback.neutral: feedbackColor = _violet; discBorder = _violet;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(feedbackText, style: TextStyle(color: feedbackColor, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2.5, fontFamily: 'SpaceGrotesk')),
        const SizedBox(height: 18),
        AnimatedBuilder(
          animation: _arrowAnim,
          builder: (_, __) => Transform.scale(
            scale: _arrowAnim.value,
            child: Container(
              width: 154,
              height: 154,
              decoration: BoxDecoration(color: _surfacePurple, shape: BoxShape.circle, border: Border.all(color: discBorder, width: 2)),
              alignment: Alignment.center,
              child: Text(_arrowFor(_direction), style: const TextStyle(color: _text, fontSize: 76, fontFamily: 'SpaceGrotesk')),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(_labelFor(_direction), style: const TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 3, fontFamily: 'SpaceGrotesk')),
        const SizedBox(height: 8),
        const Text('Swipe anywhere in this panel', style: TextStyle(color: _textMuted, fontSize: 12, fontFamily: 'SpaceGrotesk')),
      ],
    );
  }

  Widget _buildIntro() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 34),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('HOW TO PLAY', style: TextStyle(color: _violet, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk')),
        const SizedBox(height: 12),
        const Text('Follow the signal', style: TextStyle(color: _text, fontSize: 27, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
        const SizedBox(height: 10),
        const Text(
          'Swipe in the direction shown. Correct swipes build your combo, and each new signal gives you less time to react.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _textMuted, fontSize: 14, height: 1.5, fontFamily: 'SpaceGrotesk'),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: ['↑', '→', '↓', '←'].map((a) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Text(a, style: const TextStyle(color: _violet, fontSize: 30, fontWeight: FontWeight.w800)),
          )).toList(),
        ),
      ],
    ),
  );

  Widget _buildResult(int accuracy) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 34),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('RUSH COMPLETE', style: TextStyle(color: _violet, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk')),
        const SizedBox(height: 7),
        Text('$_score', style: const TextStyle(color: _text, fontSize: 54, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
        const SizedBox(height: 10),
        Text('$_correct clean swipes · $accuracy% accuracy · best combo x$_bestCombo',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _textMuted, fontSize: 14, height: 1.5, fontFamily: 'SpaceGrotesk')),
      ],
    ),
  );

  Widget _buildButton() => GestureDetector(
    onTap: _start,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: _surfacePurple, borderRadius: BorderRadius.circular(18), border: Border.all(color: _borderBright, width: 2)),
      child: Text(
        _phase == _Phase.result ? 'PLAY AGAIN' : 'START RUSH',
        textAlign: TextAlign.center,
        style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontFamily: 'SpaceGrotesk'),
      ),
    ),
  );
}
