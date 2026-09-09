import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _RuleChallenge {
  final List<int> values; // 5 values: 4 conformers + 1 breaker (shuffled)
  final int breakerIndex; // index in values
  final String ruleLabel;
  final String fingerprint;

  const _RuleChallenge({
    required this.values,
    required this.breakerIndex,
    required this.ruleLabel,
    required this.fingerprint,
  });
}

bool _isPrime(int n) {
  if (n < 2) return false;
  if (n == 2) return true;
  if (n.isEven) return false;
  for (int i = 3; i * i <= n; i += 2) {
    if (n % i == 0) return false;
  }
  return true;
}

bool _isSquare(int n) {
  if (n < 0) return false;
  final r = sqrt(n).round();
  return r * r == n;
}

int _digitSum(int n) => n.toString().split('').map(int.parse).reduce((a, b) => a + b);

List<int> _uniqueValues(int count, bool Function(int) test, int minV, int maxV, Random rng, {Set<int> exclude = const {}}) {
  final pool = List.generate(maxV - minV + 1, (i) => i + minV).where((v) => test(v) && !exclude.contains(v)).toList();
  if (pool.length < count) return [];
  pool.shuffle(rng);
  return pool.take(count).toList();
}

String _difficulty(int round, int correct) {
  if (round >= 7 || correct >= 6) return 'hard';
  if (round >= 3 || correct >= 3) return 'medium';
  return 'easy';
}

_RuleChallenge? _parityRule(Random rng, String diff) {
  final isEven = rng.nextBool();
  final (min, max) = switch (diff) {
    'easy'   => (2, 30),
    'medium' => (10, 60),
    _        => (20, 100),
  };
  final conformers = _uniqueValues(4, (v) => isEven ? v.isEven : v.isOdd, min, max, rng);
  if (conformers.length < 4) return null;
  final breaker = _uniqueValues(1, (v) => isEven ? v.isOdd : v.isEven, min, max, rng, exclude: conformers.toSet());
  if (breaker.isEmpty) return null;
  final label = isEven ? 'ALL OTHERS ARE EVEN' : 'ALL OTHERS ARE ODD';
  final all = [...conformers, breaker.first]..shuffle(rng);
  final breakerIdx = all.indexOf(breaker.first);
  final sorted = [...conformers..sort(), breaker.first];
  final fp = 'parity|${sorted.join(",")}';
  return _RuleChallenge(values: all, breakerIndex: breakerIdx, ruleLabel: label, fingerprint: fp);
}

_RuleChallenge? _multipleRule(Random rng, String diff) {
  final divisor = diff == 'easy' ? (rng.nextInt(3) + 2) : diff == 'medium' ? (rng.nextInt(4) + 3) : (rng.nextInt(5) + 4);
  final (min, max) = switch (diff) {
    'easy'   => (2, 40),
    'medium' => (5, 80),
    _        => (10, 120),
  };
  final conformers = _uniqueValues(4, (v) => v % divisor == 0 && v > 0, min, max, rng);
  if (conformers.length < 4) return null;
  final breaker = _uniqueValues(1, (v) => v % divisor != 0 && v > 0, min, max, rng, exclude: conformers.toSet());
  if (breaker.isEmpty) return null;
  final label = 'ALL OTHERS DIVIDE BY $divisor';
  final all = [...conformers, breaker.first]..shuffle(rng);
  final breakerIdx = all.indexOf(breaker.first);
  final sorted = [...conformers..sort(), breaker.first];
  final fp = 'mult$divisor|${sorted.join(",")}';
  return _RuleChallenge(values: all, breakerIndex: breakerIdx, ruleLabel: label, fingerprint: fp);
}

_RuleChallenge? _squareRule(Random rng, String diff) {
  final (min, max) = switch (diff) {
    'easy'   => (1, 50),
    'medium' => (4, 144),
    _        => (9, 400),
  };
  final conformers = _uniqueValues(4, _isSquare, min, max, rng);
  if (conformers.length < 4) return null;
  final breaker = _uniqueValues(1, (v) => !_isSquare(v) && v > 0, min, max, rng, exclude: conformers.toSet());
  if (breaker.isEmpty) return null;
  final all = [...conformers, breaker.first]..shuffle(rng);
  final breakerIdx = all.indexOf(breaker.first);
  final sorted = [...conformers..sort(), breaker.first];
  final fp = 'sq|${sorted.join(",")}';
  return _RuleChallenge(values: all, breakerIndex: breakerIdx, ruleLabel: 'ALL OTHERS ARE PERFECT SQUARES', fingerprint: fp);
}

_RuleChallenge? _primeRule(Random rng, String diff) {
  final (min, max) = switch (diff) {
    'easy'   => (2, 30),
    'medium' => (5, 60),
    _        => (10, 100),
  };
  final conformers = _uniqueValues(4, _isPrime, min, max, rng);
  if (conformers.length < 4) return null;
  final breaker = _uniqueValues(1, (v) => !_isPrime(v) && v > 1, min, max, rng, exclude: conformers.toSet());
  if (breaker.isEmpty) return null;
  final all = [...conformers, breaker.first]..shuffle(rng);
  final breakerIdx = all.indexOf(breaker.first);
  final sorted = [...conformers..sort(), breaker.first];
  final fp = 'prime|${sorted.join(",")}';
  return _RuleChallenge(values: all, breakerIndex: breakerIdx, ruleLabel: 'ALL OTHERS ARE PRIME', fingerprint: fp);
}

_RuleChallenge? _digitSumRule(Random rng, String diff) {
  final divisor = diff == 'easy' ? (rng.nextInt(3) + 2) : diff == 'medium' ? (rng.nextInt(3) + 3) : (rng.nextInt(4) + 4);
  final (min, max) = switch (diff) {
    'easy'   => (10, 50),
    'medium' => (20, 99),
    _        => (20, 200),
  };
  final conformers = _uniqueValues(4, (v) => _digitSum(v) % divisor == 0, min, max, rng);
  if (conformers.length < 4) return null;
  final breaker = _uniqueValues(1, (v) => _digitSum(v) % divisor != 0, min, max, rng, exclude: conformers.toSet());
  if (breaker.isEmpty) return null;
  final label = 'DIGIT SUM DIVIDES BY $divisor';
  final all = [...conformers, breaker.first]..shuffle(rng);
  final breakerIdx = all.indexOf(breaker.first);
  final sorted = [...conformers..sort(), breaker.first];
  final fp = 'dsum$divisor|${sorted.join(",")}';
  return _RuleChallenge(values: all, breakerIndex: breakerIdx, ruleLabel: label, fingerprint: fp);
}

typedef _RuleGen = _RuleChallenge? Function(Random, String);

final _kRuleGens = <_RuleGen>[_parityRule, _multipleRule, _squareRule, _primeRule, _digitSumRule];

_RuleChallenge? _generate(Random rng, String diff, Set<String> seen) {
  for (int attempt = 0; attempt < 300; attempt++) {
    final gen = _kRuleGens[rng.nextInt(_kRuleGens.length)];
    final c = gen(rng, diff);
    if (c != null && !seen.contains(c.fingerprint)) return c;
  }
  return null;
}

// ── Game widget ───────────────────────────────────────────────────────────────

enum _Phase { intro, playing, feedback, result }

class RuleBreakerGame extends StatefulWidget {
  final int bestScore;
  final VoidCallback onBack;
  final void Function(int score) onFinish;

  const RuleBreakerGame({
    super.key,
    required this.bestScore,
    required this.onBack,
    required this.onFinish,
  });

  @override
  State<RuleBreakerGame> createState() => _RuleBreakerGameState();
}

class _RuleBreakerGameState extends State<RuleBreakerGame> {
  static const _kRounds = 10;
  static const _kRoundSeconds = 10;
  static const _bg = Color(0xFF070B18);
  static const _surface = Color(0xFF0F1629);
  static const _surfaceElevated = Color(0xFF18203A);
  static const _surfacePurple = Color(0xFF1A0D38);
  static const _borderBright = Color(0xFF3A4870);
  static const _text = Color(0xFFF7F8FF);
  static const _textMuted = Color(0xFF9CA8C7);
  static const _violet = Color(0xFF8C6CFF);
  static const _danger = Color(0xFFFF6577);
  static const _green = Color(0xFF36DCA2);

  _Phase _phase = _Phase.intro;
  int _round = 0;
  int _timeLeft = _kRoundSeconds;
  int _score = 0;
  int _combo = 0;
  int _correct = 0;
  _RuleChallenge? _challenge;
  int? _tapped; // index in values
  bool _wasCorrect = false;

  Timer? _roundTimer;
  final _rng = Random();
  final Set<String> _seen = {};

  @override
  void dispose() {
    _roundTimer?.cancel();
    super.dispose();
  }

  void _start() {
    _roundTimer?.cancel();
    _seen.clear();
    setState(() {
      _phase = _Phase.playing;
      _round = 0; _score = 0; _combo = 0; _correct = 0; _tapped = null;
    });
    _nextRound();
  }

  void _nextRound() {
    if (_round >= _kRounds) { _finish(); return; }
    final diff = _difficulty(_round, _correct);
    final c = _generate(_rng, diff, _seen);
    if (c == null) { _finish(); return; }
    _seen.add(c.fingerprint);
    setState(() { _challenge = c; _tapped = null; _timeLeft = _kRoundSeconds; _phase = _Phase.playing; });
    _roundTimer?.cancel();
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = _timeLeft - 1;
      if (!mounted) { t.cancel(); return; }
      if (next <= 0) { t.cancel(); _onTimeout(); return; }
      setState(() => _timeLeft = next);
    });
  }

  void _onTimeout() {
    _roundTimer?.cancel();
    setState(() { _wasCorrect = false; _tapped = -1; _phase = _Phase.feedback; _combo = 0; });
    _afterFeedback();
  }

  void _onTap(int valueIndex) {
    if (_phase != _Phase.playing || _challenge == null || _tapped != null) return;
    _roundTimer?.cancel();
    final correct = valueIndex == _challenge!.breakerIndex;
    if (correct) {
      final speed = _timeLeft >= 7 ? 100 : _timeLeft >= 4 ? 75 : 50;
      final nc = _combo + 1;
      setState(() { _combo = nc; _correct++; _score += speed + (_combo.clamp(0, 5)) * 10; _wasCorrect = true; });
    } else {
      setState(() { _combo = 0; _wasCorrect = false; });
    }
    setState(() { _tapped = valueIndex; _phase = _Phase.feedback; });
    _afterFeedback();
  }

  void _afterFeedback() {
    _roundTimer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() => _round++);
      _nextRound();
    });
  }

  void _finish() {
    _roundTimer?.cancel();
    widget.onFinish(_score);
    if (mounted) setState(() => _phase = _Phase.result);
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
              _buildNav(),
              const SizedBox(height: 18),
              _buildHeader(),
              const SizedBox(height: 20),
              Expanded(child: _buildContent()),
              if (_phase == _Phase.intro || _phase == _Phase.result) ...[
                const SizedBox(height: 16),
                _buildButton(),
              ],
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
      if (_phase == _Phase.playing || _phase == _Phase.feedback)
        Text('ROUND ${_round + 1} / $_kRounds', style: const TextStyle(color: _violet, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
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
            const Text('IQ', style: TextStyle(color: _danger, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 6),
            const Text('Rule Breaker', style: TextStyle(color: _text, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.8, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 5),
            const Text('Find the one that breaks the rule.', style: TextStyle(color: _textMuted, fontSize: 13, fontFamily: 'SpaceGrotesk')),
          ],
        ),
      ),
      if (_phase == _Phase.playing || _phase == _Phase.feedback) ...[
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
    ],
  );

  Widget _buildContent() {
    if (_phase == _Phase.intro) return _buildIntro();
    if (_phase == _Phase.result) return _buildResult();
    if (_challenge == null) return const SizedBox.shrink();
    return _buildGame();
  }

  Widget _buildIntro() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderBright)),
        child: Column(
          children: [
            const Text('HOW TO PLAY', style: TextStyle(color: _danger, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 12),
            const Text('One of these doesn\'t belong', style: TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 10),
            const Text(
              'Five numbers appear. Four of them share a hidden rule. One breaks it. Tap the outsider before time runs out. Speed earns bonus points.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textMuted, fontSize: 14, height: 1.5, fontFamily: 'SpaceGrotesk'),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              children: [4, 8, 12, 7, 16].map((v) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: v == 7 ? const Color(0xFF2B0D10) : _surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: v == 7 ? _danger : _borderBright),
                ),
                child: Text('$v', style: TextStyle(color: v == 7 ? _danger : _textMuted, fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
              )).toList(),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildGame() {
    final c = _challenge!;
    final isFeedback = _phase == _Phase.feedback;

    return Column(
      children: [
        // Stats row
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                decoration: BoxDecoration(color: _surfacePurple, borderRadius: BorderRadius.circular(18), border: Border.all(color: _violet)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SCORE', style: TextStyle(color: _text, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
                    Text('$_score', style: const TextStyle(color: _text, fontSize: 32, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
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
                    Text('x$_combo', style: const TextStyle(color: _violet, fontSize: 32, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Instruction
        if (isFeedback)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _wasCorrect ? 'RULE BROKEN' : (_tapped == -1 ? 'TIME FADED' : 'WRONG OUTSIDER'),
              style: TextStyle(color: _wasCorrect ? _green : _danger, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk'),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('TAP THE ONE THAT DOESN\'T BELONG', style: TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.4, fontFamily: 'SpaceGrotesk')),
          ),

        // Value cards
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: List.generate(c.values.length, (i) {
            final v = c.values[i];
            final isBreaker = i == c.breakerIndex;
            final isTapped = _tapped == i;

            Color bg = _surfaceElevated;
            Color border = _borderBright;
            Color textColor = _text;

            if (isFeedback) {
              if (isBreaker) { bg = const Color(0xFF0D2B1A); border = _green; textColor = _green; }
              else if (isTapped) { bg = const Color(0xFF2B0D10); border = _danger; textColor = _danger; }
            }

            return GestureDetector(
              onTap: _phase == _Phase.playing ? () => _onTap(i) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 90,
                height: 80,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: border, width: 2)),
                alignment: Alignment.center,
                child: Text('$v', style: TextStyle(color: textColor, fontSize: 26, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),

        // Rule label (shown after answer)
        if (isFeedback)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: _borderBright)),
            child: Text(c.ruleLabel, textAlign: TextAlign.center,
              style: const TextStyle(color: _textMuted, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1, fontFamily: 'SpaceGrotesk')),
          ),
      ],
    );
  }

  Widget _buildResult() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderBright)),
        child: Column(
          children: [
            const Text('BREAKER RUN COMPLETE', style: TextStyle(color: _danger, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 8),
            Text('$_score', style: const TextStyle(color: _text, fontSize: 54, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 6),
            Text('$_correct / $_kRounds broken', style: const TextStyle(color: _textMuted, fontSize: 15, fontFamily: 'SpaceGrotesk')),
          ],
        ),
      ),
    ],
  );

  Widget _buildButton() => GestureDetector(
    onTap: _start,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(color: _surfacePurple, borderRadius: BorderRadius.circular(18), border: Border.all(color: _borderBright, width: 2)),
      child: Text(
        _phase == _Phase.result ? 'PLAY AGAIN' : 'START RUN',
        textAlign: TextAlign.center,
        style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontFamily: 'SpaceGrotesk'),
      ),
    ),
  );
}
