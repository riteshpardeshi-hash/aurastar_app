import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RubricBuilderScreen extends StatefulWidget {
  final String challengeId;
  final String challengeTitle;
  final Map<String, dynamic>? existingWeights;

  const RubricBuilderScreen({
    super.key,
    required this.challengeId,
    required this.challengeTitle,
    this.existingWeights,
  });

  @override
  State<RubricBuilderScreen> createState() => _RubricBuilderScreenState();
}

class _RubricBuilderScreenState extends State<RubricBuilderScreen> {
  static const _bg     = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  // Dimension weights (int, 0–100 each; movement+timing+expression+sound must = 100)
  late double _movement;
  late double _timing;
  late double _expression;
  late double _sound;
  late double _penalties; // 0–30 flat-deduction points

  bool _saving = false;

  static const _dims = ['movement', 'timing', 'expression', 'sound'];

  static const _dimMeta = {
    'movement':   (Icons.directions_run_rounded,   Color(0xFF06B6D4), 'Physical accuracy and technique quality'),
    'timing':     (Icons.timer_outlined,            Color(0xFF22C55E), 'Rhythm, tempo and synchronisation'),
    'expression': (Icons.auto_awesome,              Color(0xFFD4A8FF), 'Creativity, style and personality'),
    'sound':      (Icons.music_note_rounded,        Color(0xFFF59E0B), 'Audio quality, sync and music use'),
  };

  @override
  void initState() {
    super.initState();
    final w = widget.existingWeights;
    if (w != null && w.isNotEmpty) {
      _movement   = ((w['movement']   as num?)?.toDouble() ?? 25).clamp(0, 100);
      _timing     = ((w['timing']     as num?)?.toDouble() ?? 25).clamp(0, 100);
      _expression = ((w['expression'] as num?)?.toDouble() ?? 25).clamp(0, 100);
      _sound      = ((w['sound']      as num?)?.toDouble() ?? 25).clamp(0, 100);
      _penalties  = ((w['penalties']  as num?)?.toDouble() ?? 0 ).clamp(0, 30);
    } else {
      _movement   = 25;
      _timing     = 25;
      _expression = 25;
      _sound      = 25;
      _penalties  = 0;
    }
  }

  int get _total => (_movement + _timing + _expression + _sound).round();
  bool get _valid => _total == 100;

  double _get(String dim) => switch (dim) {
    'movement'   => _movement,
    'timing'     => _timing,
    'expression' => _expression,
    _            => _sound,
  };

  // When one slider moves, rebalance the other three proportionally.
  void _onDimChanged(String changed, double newVal) {
    final others = _dims.where((d) => d != changed).toList();
    final otherSum = others.fold<double>(0, (s, d) => s + _get(d));
    final remaining = (100 - newVal).clamp(0, 100);

    setState(() {
      switch (changed) {
        case 'movement':   _movement   = newVal; break;
        case 'timing':     _timing     = newVal; break;
        case 'expression': _expression = newVal; break;
        default:           _sound      = newVal;
      }

      if (otherSum <= 0) {
        // All others are zero — spread evenly
        final each = remaining / 3;
        for (final d in others) {
          _setDim(d, each);
        }
      } else {
        // Distribute remaining proportionally
        for (final d in others) {
          _setDim(d, (_get(d) / otherSum) * remaining);
        }
      }
    });
  }

  void _setDim(String dim, double val) {
    final clamped = val.clamp(0.0, 100.0);
    switch (dim) {
      case 'movement':   _movement   = clamped; break;
      case 'timing':     _timing     = clamped; break;
      case 'expression': _expression = clamped; break;
      default:           _sound      = clamped;
    }
  }

  void _reset() => setState(() {
    _movement   = 25;
    _timing     = 25;
    _expression = 25;
    _sound      = 25;
    _penalties  = 0;
  });

  Future<void> _save() async {
    if (!_valid) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('users').doc(uid).get();
    if (userDoc.data()?['isAdmin'] != true) {
      _snack('Admin access required', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('challenges')
          .doc(widget.challengeId)
          .update({
        'scoringWeights': {
          'movement':   _movement.round(),
          'timing':     _timing.round(),
          'expression': _expression.round(),
          'sound':      _sound.round(),
          'penalties':  _penalties.round(),
        },
        'rubricUpdatedAt': Timestamp.now(),
        'rubricUpdatedBy': uid,
      });
      if (!mounted) return;
      _snack('Rubric saved');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Save failed: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? Colors.red.shade800 : const Color(0xFF1A0A2E),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rubric Builder',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay')),
            Text(widget.challengeTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, color: Colors.white54,
                    fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('Reset',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Pie-chart style allocation bar ──────────────────────────
            _AllocationBar(
              movement:   _movement,
              timing:     _timing,
              expression: _expression,
              sound:      _sound,
            ),
            const SizedBox(height: 20),

            // ── Total indicator ──────────────────────────────────────────
            _TotalBadge(total: _total),
            const SizedBox(height: 20),

            // ── Dimension sliders ────────────────────────────────────────
            const _SectionHeader('Scoring Weights',
                'Each dimension contributes to the total score. They must sum to 100.'),
            const SizedBox(height: 16),

            for (final dim in _dims) ...[
              _DimSlider(
                name: dim[0].toUpperCase() + dim.substring(1),
                value: _get(dim),
                icon:  _dimMeta[dim]!.$1,
                color: _dimMeta[dim]!.$2,
                desc:  _dimMeta[dim]!.$3,
                onChanged: (v) => _onDimChanged(dim, v),
              ),
              const SizedBox(height: 18),
            ],

            const Divider(color: Colors.white10, height: 32),

            // ── Penalties ────────────────────────────────────────────────
            const _SectionHeader('Penalties',
                'Max points deducted when the submission poorly mirrors the reference. Applied proportionally when match accuracy is below 50%.'),
            const SizedBox(height: 16),

            _PenaltySlider(
              value: _penalties,
              onChanged: (v) => setState(() => _penalties = v),
            ),

            const SizedBox(height: 32),

            // ── Save ─────────────────────────────────────────────────────
            if (!_valid)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Colors.amber, size: 14),
                    const SizedBox(width: 6),
                    Text('Weights must sum to 100 (currently $_total)',
                        style: const TextStyle(
                            color: Colors.amber, fontSize: 12)),
                  ],
                ),
              ),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_saving || !_valid) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor:
                      Colors.white.withValues(alpha: 0.06),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Save Rubric'),
              ),
            ),

            const SizedBox(height: 16),

            // ── Info card ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _accent.withValues(alpha: 0.20)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: _accent.withValues(alpha: 0.70), size: 16),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'These weights apply to all new submissions after saving. Existing scored submissions are not retroactively updated.',
                      style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Allocation bar ────────────────────────────────────────────────────────────

class _AllocationBar extends StatelessWidget {
  final double movement;
  final double timing;
  final double expression;
  final double sound;

  const _AllocationBar({
    required this.movement,
    required this.timing,
    required this.expression,
    required this.sound,
  });

  @override
  Widget build(BuildContext context) {
    final total = movement + timing + expression + sound;
    if (total <= 0) return const SizedBox.shrink();

    final segments = [
      ('Movement',   movement,   const Color(0xFF06B6D4)),
      ('Timing',     timing,     const Color(0xFF22C55E)),
      ('Expression', expression, const Color(0xFFD4A8FF)),
      ('Sound',      sound,      const Color(0xFFF59E0B)),
    ];

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: segments.map((s) {
              final frac = s.$2 / total;
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: frac, end: frac),
                duration: const Duration(milliseconds: 200),
                builder: (_, v, __) => Expanded(
                  flex: (v * 1000).round(),
                  child: Container(
                    height: 10,
                    color: s.$3,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: segments.map((s) {
            final pct = total > 0 ? (s.$2 / total * 100).round() : 0;
            return Row(
              children: [
                Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                        color: s.$3, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('${s.$1[0]}$pct%',
                    style: TextStyle(
                        color: s.$3.withValues(alpha: 0.80),
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Total badge ───────────────────────────────────────────────────────────────

class _TotalBadge extends StatelessWidget {
  final int total;
  const _TotalBadge({required this.total});

  @override
  Widget build(BuildContext context) {
    final ok = total == 100;
    final color = ok ? const Color(0xFF22C55E) : Colors.amber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline_rounded : Icons.tune_rounded,
            color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            ok ? 'Weights balanced — $total / 100' : 'Total: $total / 100',
            style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'ClashDisplay')),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 12, height: 1.4)),
        ],
      );
}

// ── Dimension slider ──────────────────────────────────────────────────────────

class _DimSlider extends StatelessWidget {
  final String   name;
  final double   value;
  final IconData icon;
  final Color    color;
  final String   desc;
  final ValueChanged<double> onChanged;

  const _DimSlider({
    required this.name,
    required this.value,
    required this.icon,
    required this.color,
    required this.desc,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF100A20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text(desc,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Weight chip
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.40)),
                ),
                child: Text('${value.round()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: color,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor:   color,
              thumbColor:         color,
              inactiveTrackColor: color.withValues(alpha: 0.15),
              overlayColor:       color.withValues(alpha: 0.12),
              trackHeight:        3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(0, 100),
              min:   0,
              max:   100,
              divisions: 100,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Penalty slider ────────────────────────────────────────────────────────────

class _PenaltySlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _PenaltySlider({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF100A20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.remove_circle_outline_rounded,
                    color: Colors.redAccent, size: 15),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Penalties',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text('Max deduction when reference match < 50%',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.red.withValues(alpha: 0.35)),
                ),
                child: Text('−${value.round()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor:   Colors.redAccent,
              thumbColor:         Colors.redAccent,
              inactiveTrackColor: Colors.red.withValues(alpha: 0.15),
              overlayColor:       Colors.red.withValues(alpha: 0.12),
              trackHeight:        3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(0, 30),
              min:   0,
              max:   30,
              divisions: 30,
              onChanged: onChanged,
            ),
          ),
          if (value > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(
                'Up to ${value.round()} pts deducted when match accuracy is low.',
                style: TextStyle(
                    color: Colors.redAccent.withValues(alpha: 0.60),
                    fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
