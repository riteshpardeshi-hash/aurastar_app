import 'package:flutter/material.dart';
import '../../../core/services/creator_gates_service.dart';
import '../../../shared/theme/app_colors.dart';

class CreatorGateRulesScreen extends StatefulWidget {
  const CreatorGateRulesScreen({super.key});

  @override
  State<CreatorGateRulesScreen> createState() => _CreatorGateRulesScreenState();
}

class _CreatorGateRulesScreenState extends State<CreatorGateRulesScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  bool _loading = true;
  Map<String, dynamic>? _rules;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await CreatorGatesService().fetchGateRules();
    if (!mounted) return;
    setState(() {
      _rules = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gates = (_rules?['gates'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final policy = _rules?['policy'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Gate Rules'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _rules == null
              ? const Center(
                  child: Text('Could not load gate rules', style: TextStyle(color: AppColors.textMuted)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                  children: [
                    const Text('How Gates Work',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    const Text(
                      'Every LIVE challenge unlocks a series of participant-count gates. '
                      'Reach a gate\'s target and you earn its Aura reward automatically.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    ...gates.map(_gateTile),
                    if (policy != null) ...[
                      const SizedBox(height: 8),
                      const Text('Policies',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      if ((policy['rewardPolicy'] as String?)?.isNotEmpty == true)
                        _policyCard('Reward Policy', policy['rewardPolicy'] as String),
                      if ((policy['antiSpamPolicy'] as String?)?.isNotEmpty == true)
                        _policyCard('Anti-Spam Policy', policy['antiSpamPolicy'] as String),
                      if ((policy['validParticipantRules'] as List?)?.isNotEmpty == true)
                        _policyListCard('Valid Participant Rules',
                            (policy['validParticipantRules'] as List).cast<String>()),
                    ],
                  ],
                ),
    );
  }

  Widget _gateTile(Map<String, dynamic> g) {
    final order = g['order'] as int? ?? 0;
    final name = g['name'] as String? ?? 'Gate $order';
    final required = g['requiredParticipants'] as int? ?? 0;
    final reward = g['rewardPoints'] as int? ?? 0;
    final description = g['description'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$order',
                style: const TextStyle(color: _accent, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text('$required participants to unlock',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                if ((description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(description!, style: const TextStyle(color: AppColors.textFaint, fontSize: 12, height: 1.4)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 14),
              const SizedBox(width: 3),
              Text('$reward', style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _policyCard(String title, String body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.5)),
        ],
      ),
    );
  }

  Widget _policyListCard(String title, List<String> items) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 8),
          ...items.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.circle, color: Colors.white38, size: 5),
                    const SizedBox(width: 8),
                    Expanded(child: Text(i, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
