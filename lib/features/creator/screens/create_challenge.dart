import 'package:flutter/material.dart';
import 'brand_camera_screen.dart';

class CreateChallenge extends StatefulWidget {
  const CreateChallenge({super.key});

  @override
  State<CreateChallenge> createState() => _CreateChallengeState();
}

class _CreateChallengeState extends State<CreateChallenge> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  final _titleCtrl       = TextEditingController();
  final _stepInputCtrl   = TextEditingController();
  final _checkInputCtrl  = TextEditingController();

  final _stepFocus  = FocusNode();
  final _checkFocus = FocusNode();

  String             _difficulty = 'Medium';
  final List<String> _steps      = [];
  final List<String> _checklist  = [];

  static const _difficulties = [
    ('Easy',   Color(0xFF22C55E)),
    ('Medium', Color(0xFFF59E0B)),
    ('Hard',   Color(0xFFEF4444)),
    ('Expert', Color(0xFF9333EA)),
  ];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _stepInputCtrl.dispose();
    _checkInputCtrl.dispose();
    _stepFocus.dispose();
    _checkFocus.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _addStep() {
    final text = _stepInputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _steps.add(text);
      _stepInputCtrl.clear();
    });
    _stepFocus.requestFocus();
  }

  void _addCheckItem() {
    final text = _checkInputCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _checklist.add(text);
      _checkInputCtrl.clear();
    });
    _checkFocus.requestFocus();
  }

  void _openRecorder() {
    if (_titleCtrl.text.trim().isEmpty) {
      _snack('Please enter a challenge title');
      return;
    }
    if (_steps.isEmpty) {
      _snack('Add at least one instruction step');
      return;
    }

    // Derive a flat instructions string for backward-compat display
    final instructions = _steps
        .asMap()
        .entries
        .map((e) => '${e.key + 1}. ${e.value}')
        .join('\n');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BrandCameraScreen(
          challengeTitle:  _titleCtrl.text.trim(),
          description:     '',
          instructions:    instructions,
          difficulty:      _difficulty,
          instructionSteps: List.unmodifiable(_steps),
          scoringChecklist: List.unmodifiable(_checklist),
        ),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A0A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Create Challenge',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              fontFamily: 'ClashDisplay'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ──────────────────────────────────────────────────
            _SectionLabel('Challenge Title'),
            const SizedBox(height: 6),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              decoration: _inputDecor('e.g. Bollywood Walk Challenge'),
            ),

            const SizedBox(height: 22),

            // ── Difficulty ─────────────────────────────────────────────
            _SectionLabel('Difficulty'),
            const SizedBox(height: 10),
            Row(
              children: _difficulties.map((pair) {
                final name  = pair.$1;
                final color = pair.$2;
                final sel   = _difficulty == name;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _difficulty = name),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: sel
                            ? color.withValues(alpha: 0.20)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel
                              ? color.withValues(alpha: 0.75)
                              : Colors.white.withValues(alpha: 0.10),
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: sel ? color : Colors.white38,
                          fontSize: 12,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // ── Instruction builder ────────────────────────────────────
            Row(
              children: [
                const _SectionLabel('Instructions'),
                const Spacer(),
                if (_steps.isNotEmpty)
                  Text(
                    '${_steps.length} step${_steps.length == 1 ? '' : 's'}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Add step-by-step instructions participants must follow.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 10),

            // Existing steps
            if (_steps.isNotEmpty)
              _StepList(
                items: _steps,
                icon: Icons.format_list_numbered_rounded,
                onDelete: (i) => setState(() => _steps.removeAt(i)),
                numberItems: true,
              ),

            // Add step input
            _AddItemRow(
              ctrl:        _stepInputCtrl,
              focusNode:   _stepFocus,
              hint:        'Describe a step…',
              buttonLabel: 'Add step',
              onAdd:       _addStep,
            ),

            const SizedBox(height: 24),

            // ── Scoring checklist builder ──────────────────────────────
            Row(
              children: [
                const _SectionLabel('AI Scoring Checklist'),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: _accent.withValues(alpha: 0.35)),
                  ),
                  child: const Text(
                    'Optional',
                    style: TextStyle(
                        color: Color(0xFFD4A8FF),
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                if (_checklist.isNotEmpty)
                  Text(
                    '${_checklist.length} item${_checklist.length == 1 ? '' : 's'}',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Each item is a YES/NO question the AI uses to score entries. '
              'If empty, the AI scores holistically.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 10),

            // Existing checklist items
            if (_checklist.isNotEmpty)
              _StepList(
                items: _checklist,
                icon: Icons.check_circle_outline_rounded,
                onDelete: (i) => setState(() => _checklist.removeAt(i)),
                numberItems: false,
              ),

            // Add checklist item input
            _AddItemRow(
              ctrl:        _checkInputCtrl,
              focusNode:   _checkFocus,
              hint:        'e.g. Does the participant maintain eye contact?',
              buttonLabel: 'Add item',
              onAdd:       _addCheckItem,
            ),

            const SizedBox(height: 32),

            // ── CTA ────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _openRecorder,
                icon: const Icon(Icons.videocam_rounded, size: 20),
                label: const Text('Record Challenge Video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        filled: true,
        fillColor: _card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: Colors.white.withValues(alpha: 0.12))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _accent, width: 1.5)),
      );
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          fontFamily: 'ClashDisplay',
        ),
      );
}

// ── Reorderable step/checklist list ──────────────────────────────────────────

class _StepList extends StatelessWidget {
  final List<String>    items;
  final IconData        icon;
  final void Function(int) onDelete;
  final bool            numberItems;

  const _StepList({
    required this.items,
    required this.icon,
    required this.onDelete,
    required this.numberItems,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.asMap().entries.map((e) {
        final i    = e.key;
        final text = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF100A20),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: const Color(0xFF7B2CBF).withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: numberItems
                      ? Text(
                          '${i + 1}',
                          style: const TextStyle(
                              color: Color(0xFFD4A8FF),
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        )
                      : Icon(icon,
                          color: const Color(0xFFD4A8FF), size: 13),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              GestureDetector(
                onTap: () => onDelete(i),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded,
                      color: Colors.white24, size: 18),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Add-item input row ────────────────────────────────────────────────────────

class _AddItemRow extends StatelessWidget {
  final TextEditingController ctrl;
  final FocusNode             focusNode;
  final String                hint;
  final String                buttonLabel;
  final VoidCallback          onAdd;

  const _AddItemRow({
    required this.ctrl,
    required this.focusNode,
    required this.hint,
    required this.buttonLabel,
    required this.onAdd,
  });

  static const _accent = Color(0xFF7B2CBF);
  static const _card   = Color(0xFF100A20);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            focusNode:  focusNode,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            onSubmitted: (_) => onAdd(),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: _card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.10))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _accent, width: 1.5)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            onPressed: onAdd,
            style: ElevatedButton.styleFrom(
              backgroundColor: _accent.withValues(alpha: 0.25),
              foregroundColor: const Color(0xFFD4A8FF),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: _accent.withValues(alpha: 0.40))),
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: Text(buttonLabel),
          ),
        ),
      ],
    );
  }
}
