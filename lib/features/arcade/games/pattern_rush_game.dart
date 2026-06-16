import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _Problem {
  final List<int> sequence;
  final int answer;
  final List<int> options; // 4 options (shuffled), includes answer
  final String ruleLabel;
  final String fingerprint;

  const _Problem({
    required this.sequence,
    required this.answer,
    required this.options,
    required this.ruleLabel,
    required this.fingerprint,
  });
}

// ── Generators ────────────────────────────────────────────────────────────────

List<int> _makeOptions(int answer, List<int> seq, Random rng) {
  final diffs = <int>[];
  for (int i = 1; i < seq.length; i++) {
    final d = (seq[i] - seq[i - 1]).abs();
    if (d > 0) diffs.add(d);
  }
  final step = diffs.isEmpty ? max(1, answer.abs() ~/ 5 + 1) : diffs.last.clamp(1, 999);

  final candidates = <int>{};
  for (final m in [1, 2, -1, 3, -2, 4]) {
    candidates.add(answer + m * step);
    if (step > 1) candidates.add(answer + m * (step - 1));
    candidates.add(answer + m * (step + 1));
  }
  candidates.removeWhere((v) => v == answer || v <= 0);

  final pool = candidates.toList()..shuffle(rng);
  final wrongs = pool.take(3).toList();
  int fallback = 1;
  while (wrongs.length < 3) {
    final v = answer + fallback;
    if (!wrongs.contains(v) && v != answer) wrongs.add(v);
    fallback++;
  }

  return ([answer, ...wrongs]..shuffle(rng));
}

_Problem? _arithmetic(Random rng, String diff) {
  int start, d, len;
  if (diff == 'easy') {
    start = rng.nextInt(10) + 1; d = rng.nextInt(5) + 1; len = 5;
  } else if (diff == 'medium') {
    start = rng.nextInt(20) + 5; d = rng.nextInt(9) + 3; len = 5;
  } else {
    start = rng.nextInt(40) + 10;
    d = rng.nextInt(15) + 5;
    if (rng.nextBool()) d = -d;
    len = 6;
  }
  final seq = List.generate(len, (i) => start + i * d);
  if (seq.any((v) => v <= 0)) return null;
  final answer = start + len * d;
  if (answer <= 0) return null;
  final label = d > 0 ? '+$d EACH TIME' : '$d EACH TIME';
  final fp = '${seq.join(",")}|$answer';
  return _Problem(sequence: seq, answer: answer, options: _makeOptions(answer, seq, rng), ruleLabel: label, fingerprint: fp);
}

_Problem? _geometric(Random rng, String diff) {
  int start, ratio, len;
  if (diff == 'easy') {
    start = rng.nextInt(3) + 1; ratio = 2; len = 4;
  } else if (diff == 'medium') {
    start = rng.nextInt(3) + 1; ratio = rng.nextInt(2) + 2; len = 4;
  } else {
    start = rng.nextInt(2) + 1; ratio = rng.nextInt(3) + 2; len = 5;
  }
  final seq = List.generate(len, (i) => start * pow(ratio, i).toInt());
  if (seq.last > 100000) return null;
  final answer = start * pow(ratio, len).toInt();
  final fp = '${seq.join(",")}|$answer';
  return _Problem(sequence: seq, answer: answer, options: _makeOptions(answer, seq, rng), ruleLabel: '×$ratio EACH TIME', fingerprint: fp);
}

_Problem? _growingStep(Random rng, String diff) {
  int start, stepStart, len;
  if (diff == 'easy') {
    start = rng.nextInt(10) + 1; stepStart = 1; len = 4;
  } else if (diff == 'medium') {
    start = rng.nextInt(15) + 1; stepStart = rng.nextInt(2) + 2; len = 5;
  } else {
    start = rng.nextInt(20) + 1; stepStart = rng.nextInt(3) + 3; len = 6;
  }
  final seq = <int>[start];
  int step = stepStart;
  for (int i = 1; i < len; i++) {
    seq.add(seq.last + step);
    step++;
  }
  final answer = seq.last + step;
  final fp = '${seq.join(",")}|$answer';
  return _Problem(sequence: seq, answer: answer, options: _makeOptions(answer, seq, rng), ruleLabel: 'STEPS GROW BY 1', fingerprint: fp);
}

_Problem? _alternating(Random rng, String diff) {
  int a, da, b, db;
  if (diff == 'easy') {
    a = rng.nextInt(10) + 1; da = rng.nextInt(3) + 2;
    b = rng.nextInt(10) + 20; db = rng.nextInt(3) + 2;
  } else if (diff == 'medium') {
    a = rng.nextInt(15) + 1; da = rng.nextInt(4) + 3;
    b = rng.nextInt(20) + 30; db = rng.nextInt(4) + 3;
  } else {
    a = rng.nextInt(20) + 5; da = rng.nextInt(6) + 5;
    b = rng.nextInt(30) + 50; db = rng.nextInt(6) + 5;
  }
  // Build 6-item sequence: a, b, a+da, b+db, a+2da, b+2db
  // Answer is position 6 → next even position → a+3da
  final seq = [a, b, a + da, b + db, a + 2 * da, b + 2 * db];
  final answer = a + 3 * da;
  final fp = '${seq.join(",")}|$answer';
  return _Problem(sequence: seq, answer: answer, options: _makeOptions(answer, seq, rng), ruleLabel: 'ALTERNATING PATTERN', fingerprint: fp);
}

_Problem? _squares(Random rng, String diff) {
  int n, len;
  if (diff == 'easy') { n = rng.nextInt(5) + 1; len = 4; }
  else if (diff == 'medium') { n = rng.nextInt(5) + 3; len = 5; }
  else { n = rng.nextInt(6) + 5; len = 5; }
  final seq = List.generate(len, (i) => (n + i) * (n + i));
  final answer = (n + len) * (n + len);
  final fp = '${seq.join(",")}|$answer';
  return _Problem(sequence: seq, answer: answer, options: _makeOptions(answer, seq, rng), ruleLabel: 'PERFECT SQUARES', fingerprint: fp);
}

_Problem? _fibonacciLike(Random rng, String diff) {
  int a, b, len;
  if (diff == 'easy') { a = rng.nextInt(3) + 1; b = rng.nextInt(3) + 1; len = 5; }
  else if (diff == 'medium') { a = rng.nextInt(4) + 1; b = rng.nextInt(5) + 2; len = 6; }
  else { a = rng.nextInt(6) + 2; b = rng.nextInt(8) + 4; len = 6; }
  final seq = <int>[a, b];
  while (seq.length < len) { seq.add(seq[seq.length - 2] + seq[seq.length - 1]); }
  final answer = seq[seq.length - 2] + seq.last;
  if (answer > 100000) return null;
  final fp = '${seq.join(",")}|$answer';
  return _Problem(sequence: seq, answer: answer, options: _makeOptions(answer, seq, rng), ruleLabel: 'ADD LAST TWO', fingerprint: fp);
}

typedef _Generator = _Problem? Function(Random, String);

final _kGenerators = <_Generator>[
  _arithmetic, _geometric, _growingStep, _alternating, _squares, _fibonacciLike,
];

String _difficulty(int round, int correct) {
  if (round >= 7 || correct >= 6) return 'hard';
  if (round >= 3 || correct >= 3) return 'medium';
  return 'easy';
}

_Problem? _generate(Random rng, String diff, Set<String> seen) {
  for (int attempt = 0; attempt < 200; attempt++) {
    final gen = _kGenerators[rng.nextInt(_kGenerators.length)];
    final p = gen(rng, diff);
    if (p != null && !seen.contains(p.fingerprint)) return p;
  }
  return null;
}

// ── Game widget ───────────────────────────────────────────────────────────────

enum _Phase { intro, playing, feedback, result }

class PatternRushGame extends StatefulWidget {
  final int bestScore;
  final VoidCallback onBack;
  final void Function(int score) onFinish;

  const PatternRushGame({
    super.key,
    required this.bestScore,
    required this.onBack,
    required this.onFinish,
  });

  @override
  State<PatternRushGame> createState() => _PatternRushGameState();
}

class _PatternRushGameState extends State<PatternRushGame> {
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
  static const _warning = Color(0xFFFFCE67);
  static const _green = Color(0xFF36DCA2);
  static const _danger = Color(0xFFFF6577);

  _Phase _phase = _Phase.intro;
  int _round = 0;
  int _timeLeft = _kRoundSeconds;
  int _score = 0;
  int _combo = 0;
  int _correct = 0;
  _Problem? _problem;
  int? _selected;
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
      _round = 0; _score = 0; _combo = 0; _correct = 0;
      _selected = null;
    });
    _nextRound();
  }

  void _nextRound() {
    if (_round >= _kRounds) { _finish(); return; }
    final diff = _difficulty(_round, _correct);
    final p = _generate(_rng, diff, _seen);
    if (p == null) { _finish(); return; }
    _seen.add(p.fingerprint);
    setState(() {
      _problem = p;
      _selected = null;
      _timeLeft = _kRoundSeconds;
    });
    _roundTimer?.cancel();
    _roundTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final next = _timeLeft - 1;
      if (!mounted) { t.cancel(); return; }
      if (next <= 0) {
        t.cancel();
        _onTimeout();
        return;
      }
      setState(() => _timeLeft = next);
    });
  }

  void _onTimeout() {
    _roundTimer?.cancel();
    setState(() { _wasCorrect = false; _selected = -1; _phase = _Phase.feedback; _combo = 0; });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() { _round++; _phase = _Phase.playing; });
      _nextRound();
    });
  }

  void _onAnswer(int value) {
    if (_phase != _Phase.playing || _selected != null) return;
    _roundTimer?.cancel();
    final correct = value == _problem!.answer;
    int earned = 0;
    if (correct) {
      final speed = _timeLeft >= 7 ? 100 : _timeLeft >= 4 ? 75 : 50;
      final nc = _combo + 1;
      earned = speed + (_combo.clamp(0, 5)) * 10;
      setState(() { _combo = nc; _correct++; _score += earned; });
    } else {
      setState(() => _combo = 0);
    }
    setState(() { _selected = value; _wasCorrect = correct; _phase = _Phase.feedback; });
    Future.delayed(const Duration(milliseconds: 950), () {
      if (!mounted) return;
      setState(() { _round++; _phase = _Phase.playing; });
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
            const Text('IQ', style: TextStyle(color: _warning, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 6),
            const Text('Pattern Rush', style: TextStyle(color: _text, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.8, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 5),
            const Text('Spot the rule. Pick the next number.', style: TextStyle(color: _textMuted, fontSize: 13, fontFamily: 'SpaceGrotesk')),
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
    if (_problem == null) return const SizedBox.shrink();
    return _buildPuzzle();
  }

  Widget _buildIntro() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderBright)),
        child: Column(
          children: [
            const Text('HOW TO PLAY', style: TextStyle(color: _warning, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 12),
            const Text('Crack the pattern', style: TextStyle(color: _text, fontSize: 27, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 10),
            const Text(
              'Each round shows a number sequence with a hidden rule. Identify the pattern and pick the next number from 4 options. Faster answers earn more points.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textMuted, fontSize: 14, height: 1.5, fontFamily: 'SpaceGrotesk'),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('2  ·  4  ·  6  ·  8  ·  ', style: TextStyle(color: _textMuted, fontSize: 18, fontFamily: 'SpaceGrotesk')),
                Text('?', style: TextStyle(color: _warning, fontSize: 22, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  Widget _buildPuzzle() {
    final p = _problem!;
    return Column(
      children: [
        // Score + combo row
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
        const SizedBox(height: 16),

        // Sequence box
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(22), border: Border.all(color: _borderBright)),
          child: Column(
            children: [
              if (_phase == _Phase.feedback)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _wasCorrect ? 'CLEAN · ${p.ruleLabel}' : (_selected == -1 ? 'TIME · ${p.ruleLabel}' : 'MISSED · ${p.ruleLabel}'),
                    style: TextStyle(
                      color: _wasCorrect ? _green : _danger,
                      fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  ...p.sequence.map((v) => Text('$v  ·', style: const TextStyle(color: _textMuted, fontSize: 22, fontFamily: 'SpaceGrotesk'))),
                  const Text('?', style: TextStyle(color: _warning, fontSize: 26, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
                ],
              ),
              if (_phase == _Phase.feedback)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Answer: ${p.answer}', style: const TextStyle(color: _textMuted, fontSize: 13, fontFamily: 'SpaceGrotesk')),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Options grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.6,
          children: p.options.map((opt) {
            Color bg = _surfaceElevated;
            Color border = _borderBright;
            if (_phase == _Phase.feedback) {
              if (opt == p.answer) { bg = const Color(0xFF0D2B1A); border = _green; }
              else if (opt == _selected) { bg = const Color(0xFF2B0D10); border = _danger; }
            }
            return GestureDetector(
              onTap: _phase == _Phase.playing ? () => _onAnswer(opt) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: border)),
                alignment: Alignment.center,
                child: Text('$opt', style: const TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
              ),
            );
          }).toList(),
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
            const Text('IQ RUN COMPLETE', style: TextStyle(color: _warning, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 8),
            Text('$_score', style: const TextStyle(color: _text, fontSize: 54, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 6),
            Text('$_correct / $_kRounds correct', style: const TextStyle(color: _textMuted, fontSize: 15, fontFamily: 'SpaceGrotesk')),
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
