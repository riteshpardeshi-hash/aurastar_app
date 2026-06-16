import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _Challenge {
  final int gridSize;
  final Set<int> activeCells;
  final int revealMs;
  final String fingerprint;

  const _Challenge({
    required this.gridSize,
    required this.activeCells,
    required this.revealMs,
    required this.fingerprint,
  });

  int get activeCount => activeCells.length;
}

({int gridSize, int activeCount, int revealMs}) _settingsFor(String diff) {
  return switch (diff) {
    'easy'   => (gridSize: 3, activeCount: 3, revealMs: 2500),
    'medium' => (gridSize: 4, activeCount: 5, revealMs: 2000),
    _        => (gridSize: 4, activeCount: 7, revealMs: 1500),
  };
}

String _difficulty(int round, int correct) {
  if (round >= 7 || correct >= 6) return 'hard';
  if (round >= 3 || correct >= 3) return 'medium';
  return 'easy';
}

_Challenge? _generate(Random rng, String diff, Set<String> seen) {
  final s = _settingsFor(diff);
  for (int attempt = 0; attempt < 300; attempt++) {
    final total = s.gridSize * s.gridSize;
    final all = List.generate(total, (i) => i)..shuffle(rng);
    final active = all.take(s.activeCount).toSet();
    final sorted = active.toList()..sort();
    final fp = '${s.gridSize}|${sorted.join(",")}';
    if (!seen.contains(fp)) {
      return _Challenge(gridSize: s.gridSize, activeCells: active, revealMs: s.revealMs, fingerprint: fp);
    }
  }
  return null;
}

// ── Game widget ───────────────────────────────────────────────────────────────

enum _Phase { intro, reveal, recall, feedback, result }

class BlinkMemoryGame extends StatefulWidget {
  final int bestScore;
  final VoidCallback onBack;
  final void Function(int score) onFinish;

  const BlinkMemoryGame({
    super.key,
    required this.bestScore,
    required this.onBack,
    required this.onFinish,
  });

  @override
  State<BlinkMemoryGame> createState() => _BlinkMemoryGameState();
}

class _BlinkMemoryGameState extends State<BlinkMemoryGame> {
  static const _kRounds = 10;
  static const _kRecallSeconds = 10;
  static const _bg = Color(0xFF070B18);
  static const _surface = Color(0xFF0F1629);
  static const _surfaceElevated = Color(0xFF18203A);
  static const _surfacePurple = Color(0xFF1A0D38);
  static const _borderBright = Color(0xFF3A4870);
  static const _text = Color(0xFFF7F8FF);
  static const _textMuted = Color(0xFF9CA8C7);
  static const _violet = Color(0xFF8C6CFF);
  static const _green = Color(0xFF36DCA2);
  static const _danger = Color(0xFFFF6577);

  _Phase _phase = _Phase.intro;
  int _round = 0;
  int _timeLeft = _kRecallSeconds;
  int _score = 0;
  int _combo = 0;
  int _correct = 0;
  _Challenge? _challenge;
  Set<int> _selected = {};
  bool _wasCorrect = false;

  Timer? _timer;
  final _rng = Random();
  final Set<String> _seen = {};

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    _seen.clear();
    setState(() {
      _phase = _Phase.intro;
      _round = 0; _score = 0; _combo = 0; _correct = 0; _selected = {};
    });
    _nextRound();
  }

  void _nextRound() {
    if (_round >= _kRounds) { _finish(); return; }
    final diff = _difficulty(_round, _correct);
    final c = _generate(_rng, diff, _seen);
    if (c == null) { _finish(); return; }
    _seen.add(c.fingerprint);
    setState(() { _challenge = c; _selected = {}; _phase = _Phase.reveal; });

    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: c.revealMs), () {
      if (!mounted) return;
      setState(() { _phase = _Phase.recall; _timeLeft = _kRecallSeconds; });
      _startRecallTimer();
    });
  }

  void _startRecallTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
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
    _timer?.cancel();
    setState(() { _wasCorrect = false; _phase = _Phase.feedback; _combo = 0; });
    _afterFeedback();
  }

  void _submit() {
    if (_phase != _Phase.recall || _challenge == null) return;
    if (_selected.length != _challenge!.activeCount) return;
    _timer?.cancel();
    final correct = _selected.difference(_challenge!.activeCells).isEmpty &&
        _challenge!.activeCells.difference(_selected).isEmpty;
    if (correct) {
      final nc = _combo + 1;
      final speedBonus = (_timeLeft * 5).clamp(0, 50);
      final pts = 100 + speedBonus + (_combo.clamp(0, 5)) * 10;
      setState(() { _combo = nc; _correct++; _score += pts; _wasCorrect = true; });
    } else {
      setState(() { _combo = 0; _wasCorrect = false; });
    }
    setState(() => _phase = _Phase.feedback);
    _afterFeedback();
  }

  void _afterFeedback() {
    _timer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      setState(() { _round++; });
      _nextRound();
    });
  }

  void _finish() {
    _timer?.cancel();
    widget.onFinish(_score);
    if (mounted) setState(() => _phase = _Phase.result);
  }

  void _toggleCell(int index) {
    if (_phase != _Phase.recall || _challenge == null) return;
    setState(() {
      if (_selected.contains(index)) {
        _selected = {..._selected}..remove(index);
      } else if (_selected.length < _challenge!.activeCount) {
        _selected = {..._selected, index};
      }
    });
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
                _buildStartButton(),
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
      if (_phase == _Phase.recall || _phase == _Phase.reveal || _phase == _Phase.feedback)
        Text('ROUND ${_round + 1} / $_kRounds', style: const TextStyle(color: _violet, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: _borderBright), borderRadius: BorderRadius.circular(13)),
        child: Text('BEST ${widget.bestScore}', style: const TextStyle(color: _textMuted, fontSize: 11, fontWeight: FontWeight.w800, fontFamily: 'SpaceGrotesk')),
      ),
    ],
  );

  Widget _buildHeader() {
    final showTimer = _phase == _Phase.recall;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('IQ', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.5, fontFamily: 'SpaceGrotesk')),
              const SizedBox(height: 6),
              const Text('Blink Memory', style: TextStyle(color: _text, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.8, fontFamily: 'ClashDisplay')),
              const SizedBox(height: 5),
              Text(
                switch (_phase) {
                  _Phase.reveal   => 'Remember the lit cells…',
                  _Phase.recall   => 'Tap the cells you saw.',
                  _Phase.feedback => _wasCorrect ? 'Perfect recall!' : 'Not quite.',
                  _           => 'Memorise. Recall. Repeat.',
                },
                style: const TextStyle(color: _textMuted, fontSize: 13, fontFamily: 'SpaceGrotesk'),
              ),
            ],
          ),
        ),
        if (showTimer) ...[
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
  }

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
            const Text('HOW TO PLAY', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 12),
            const Text('Lights on. Lights off. Go.', style: TextStyle(color: _text, fontSize: 25, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 10),
            const Text(
              'A pattern of cells lights up briefly. Then the grid goes dark — tap every cell you remember. Speed matters: faster recall earns a bonus.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textMuted, fontSize: 14, height: 1.5, fontFamily: 'SpaceGrotesk'),
            ),
            const SizedBox(height: 20),
            _buildMiniGrid(3, {0, 4, 7}, {}, _Phase.reveal),
          ],
        ),
      ),
    ],
  );

  Widget _buildGame() {
    final c = _challenge!;
    final isRecall = _phase == _Phase.recall;
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

        // Phase label
        Text(
          switch (_phase) {
            _Phase.reveal   => 'MEMORISE',
            _Phase.recall   => '${_selected.length} / ${c.activeCount} selected',
            _Phase.feedback => _wasCorrect ? 'CORRECT' : 'WRONG',
            _           => '',
          },
          style: TextStyle(
            color: switch (_phase) {
              _Phase.feedback => _wasCorrect ? _green : _danger,
              _               => _textMuted,
            },
            fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4, fontFamily: 'SpaceGrotesk',
          ),
        ),
        const SizedBox(height: 12),

        // Grid
        Expanded(
          child: Center(
            child: _buildMiniGrid(
              c.gridSize,
              _phase == _Phase.reveal ? c.activeCells : {},
              isRecall ? _selected : isFeedback ? _selected : {},
              _phase,
              challenge: c,
            ),
          ),
        ),

        // Submit button
        if (isRecall) ...[
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _selected.length == c.activeCount ? _submit : null,
            child: AnimatedOpacity(
              opacity: _selected.length == c.activeCount ? 1.0 : 0.35,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(color: _surfacePurple, borderRadius: BorderRadius.circular(18), border: Border.all(color: _green, width: 2)),
                child: const Text('SUBMIT', textAlign: TextAlign.center,
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.4, fontFamily: 'SpaceGrotesk')),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMiniGrid(int gridSize, Set<int> activeCells, Set<int> selected, _Phase phase, {_Challenge? challenge}) {
    final isFeedback = phase == _Phase.feedback;
    return GridView.count(
      crossAxisCount: gridSize,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      children: List.generate(gridSize * gridSize, (i) {
        final isActive = activeCells.contains(i);
        final isSelected = selected.contains(i);
        final isCorrectActive = isFeedback && challenge != null && challenge.activeCells.contains(i);
        final isWrongSelected = isFeedback && isSelected && !isCorrectActive;

        Color bg = _surfaceElevated;
        Color border = _borderBright;
        if (isActive) { bg = _violet; border = _violet; }
        if (isSelected && !isFeedback) { bg = _violet; border = _violet; }
        if (isFeedback && isCorrectActive) { bg = const Color(0xFF0D2B1A); border = _green; }
        if (isFeedback && isWrongSelected) { bg = const Color(0xFF2B0D10); border = _danger; }

        return GestureDetector(
          onTap: phase == _Phase.recall && challenge != null ? () => _toggleCell(i) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border)),
          ),
        );
      }),
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
            const Text('MEMORY COMPLETE', style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.8, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 8),
            Text('$_score', style: const TextStyle(color: _text, fontSize: 54, fontWeight: FontWeight.w900, fontFamily: 'ClashDisplay')),
            const SizedBox(height: 6),
            Text('$_correct / $_kRounds recalled', style: const TextStyle(color: _textMuted, fontSize: 15, fontFamily: 'SpaceGrotesk')),
          ],
        ),
      ),
    ],
  );

  Widget _buildStartButton() => GestureDetector(
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
