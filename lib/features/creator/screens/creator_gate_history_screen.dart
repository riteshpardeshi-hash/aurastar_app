import 'package:flutter/material.dart';
import '../../../core/services/creator_gates_service.dart';
import '../../../shared/theme/app_colors.dart';

class CreatorGateHistoryScreen extends StatefulWidget {
  final String challengeId;
  const CreatorGateHistoryScreen({super.key, required this.challengeId});

  @override
  State<CreatorGateHistoryScreen> createState() => _CreatorGateHistoryScreenState();
}

class _CreatorGateHistoryScreenState extends State<CreatorGateHistoryScreen> {
  static const _bg     = Color(0xFF080810);
  static const _card   = Color(0xFF100A20);
  static const _accent = Color(0xFF7B2CBF);

  bool _loading = true;
  Map<String, dynamic>? _history;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await CreatorGatesService().fetchGateHistory(widget.challengeId);
    if (!mounted) return;
    setState(() {
      _history = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = (_history?['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final totalReward = _history?['totalRewardEarned'] as int? ?? 0;
    final completedGates = _history?['completedGates'] as int? ?? 0;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Reward History'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _history == null
              ? const Center(
                  child: Text('Could not load reward history', style: TextStyle(color: AppColors.textMuted)))
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                    children: [
                      Row(
                        children: [
                          Expanded(child: _summaryTile('Gates Unlocked', '$completedGates')),
                          const SizedBox(width: 10),
                          Expanded(child: _summaryTile('Aura Earned', '$totalReward')),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (entries.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text('No gates unlocked yet',
                                style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
                          ),
                        )
                      else
                        ...entries.map(_historyTile),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> e) {
    final gate = e['gate'] as Map<String, dynamic>?;
    final gateName = gate?['name'] as String? ?? 'Gate';
    final participantsReached = e['participantsReached'] as int?;
    final rewardPoints = e['rewardPoints'] as int? ?? 0;
    final creditedAt = e['creditedAt'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lock_open_rounded, color: Color(0xFF22C55E), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gateName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  [
                    if (participantsReached != null) '$participantsReached participants',
                    if (creditedAt != null) _formatDate(creditedAt),
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textFaint, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 14),
          const SizedBox(width: 3),
          Text('+$rewardPoints', style: const TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
