import 'package:flutter/material.dart';
import '../services/arcade_progress_service.dart';
import '../widgets/game_card.dart';
import '../games/aura_flash_tap_game.dart';
import '../games/catch_the_aura_game.dart';
import '../games/swipe_direction_rush_game.dart';
import '../games/pattern_rush_game.dart';
import '../games/blink_memory_game.dart';
import '../games/rule_breaker_game.dart';

class ArcadeScreen extends StatefulWidget {
  const ArcadeScreen({super.key});

  @override
  State<ArcadeScreen> createState() => _ArcadeScreenState();
}

class _ArcadeScreenState extends State<ArcadeScreen> {
  ArcadeProgress _progress = const ArcadeProgress();
  bool _loaded = false;

  static const _bg = Color(0xFF070B18);
  static const _surfaceElevated = Color(0xFF18203A);
  static const _border = Color(0xFF293455);
  static const _text = Color(0xFFF7F8FF);
  static const _textMuted = Color(0xFF9CA8C7);
  static const _violet = Color(0xFF8C6CFF);
  static const _cyan = Color(0xFF48D7FF);
  static const _warning = Color(0xFFFFCE67);
  static const _accent = Color(0xFF7B2CBF);

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    final p = await ArcadeProgressService.load();
    if (mounted) setState(() { _progress = p; _loaded = true; });
  }

  Future<void> _recordScore(String gameId, int score) async {
    final updated = _progress.withScore(gameId, score);
    if (mounted) setState(() => _progress = updated);
    await ArcadeProgressService.save(updated);
  }

  void _openGame(String gameId) {
    final best = _progress.bestScores[gameId] ?? 0;
    Route<void> route;

    if (gameId == 'aura-flash-tap') {
      route = MaterialPageRoute(
        builder: (_) => AuraFlashTapGame(
          bestScore: best,
          onBack: () => Navigator.pop(context),
          onFinish: (score) => _recordScore(gameId, score),
        ),
      );
    } else if (gameId == 'catch-the-aura') {
      route = MaterialPageRoute(
        builder: (_) => CatchTheAuraGame(
          bestScore: best,
          onBack: () => Navigator.pop(context),
          onFinish: (score) => _recordScore(gameId, score),
        ),
      );
    } else if (gameId == 'swipe-direction-rush') {
      route = MaterialPageRoute(
        builder: (_) => SwipeDirectionRushGame(
          bestScore: best,
          onBack: () => Navigator.pop(context),
          onFinish: (score) => _recordScore(gameId, score),
        ),
      );
    } else if (gameId == 'pattern-rush') {
      route = MaterialPageRoute(
        builder: (_) => PatternRushGame(
          bestScore: best,
          onBack: () => Navigator.pop(context),
          onFinish: (score) => _recordScore(gameId, score),
        ),
      );
    } else if (gameId == 'blink-memory') {
      route = MaterialPageRoute(
        builder: (_) => BlinkMemoryGame(
          bestScore: best,
          onBack: () => Navigator.pop(context),
          onFinish: (score) => _recordScore(gameId, score),
        ),
      );
    } else if (gameId == 'rule-breaker') {
      route = MaterialPageRoute(
        builder: (_) => RuleBreakerGame(
          bestScore: best,
          onBack: () => Navigator.pop(context),
          onFinish: (score) => _recordScore(gameId, score),
        ),
      );
    } else {
      return;
    }

    Navigator.push(context, route);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _accent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Back button ─────────────────────────────────────────────────
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back_ios_new_rounded, color: _violet, size: 22),
              ),
              const SizedBox(height: 18),
              // ── Header ──────────────────────────────────────────────────────
              const Text(
                'AURA ARENA',
                style: TextStyle(
                  color: _violet,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Daily Arcade',
                style: TextStyle(
                  color: _text,
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                  fontFamily: 'ClashDisplay',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Six quick challenges. One sharper you.',
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 16,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),

              // ── Daily Pulse card ────────────────────────────────────────────
              const SizedBox(height: 26),
              Container(
                constraints: const BoxConstraints(minHeight: 92),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _surfaceElevated,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DAILY PULSE',
                          style: TextStyle(
                            color: _cyan,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.8,
                            fontFamily: 'SpaceGrotesk',
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${_progress.completedToday.length} / ${kArcadeGames.length} complete',
                          style: const TextStyle(
                            color: _text,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'SpaceGrotesk',
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 9),
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${_progress.streak}',
                            style: const TextStyle(
                              color: _warning,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'ClashDisplay',
                            ),
                          ),
                          const Text(
                            'DAY STREAK',
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
              ),

              // ── Game list ───────────────────────────────────────────────────
              const SizedBox(height: 18),
              ...kArcadeGames.map(
                (game) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: GameCard(
                    game: game,
                    bestScore: _progress.bestScores[game.id] ?? 0,
                    completed: _progress.completedToday.contains(game.id),
                    onTap: () => _openGame(game.id),
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
