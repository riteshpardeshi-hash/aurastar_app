import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_ui.dart';

/// Rewards brands granted this creator for winning ads. The brand delivers
/// them; the creator confirms once received.
class AiRewardsScreen extends StatefulWidget {
  const AiRewardsScreen({super.key});

  @override
  State<AiRewardsScreen> createState() => _AiRewardsScreenState();
}

class _AiRewardsScreenState extends State<AiRewardsScreen> {
  final _service = AiAdsService();
  List<AiReward> _rewards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rewards = await _service.myRewards();
      if (mounted) setState(() => _rewards = rewards);
    } catch (_) {
      if (mounted) AiUi.toast(context, "Couldn't load your rewards.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm(AiReward r) async {
    try {
      await _service.confirmRewardReceived(r.id);
      if (mounted) AiUi.toast(context, 'Thanks — marked as received.');
      await _load();
    } on AiAdsException catch (e) {
      if (mounted) AiUi.toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiUi.bg,
      appBar: AiUi.appBar('My rewards'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AiUi.accent))
          : _rewards.isEmpty
          ? const Center(
              child: Text('No rewards yet — win a campaign to get one.',
                  style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: _rewards.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _card(_rewards[i]),
            ),
    );
  }

  Widget _card(AiReward r) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AiUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          if (r.campaignTitle.isNotEmpty)
            Text(r.campaignTitle, style: const TextStyle(color: AppColors.textFaint, fontSize: 11)),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.description, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
          if (r.value != null) ...[
            const SizedBox(height: 6),
            Text('${r.currency} ${r.value}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
          if (r.couponCode.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: r.couponCode));
                AiUi.toast(context, 'Code copied');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AiUi.accent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(r.couponCode, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                switch (r.status) {
                  'GRANTED' => 'The brand will send it to you',
                  'FULFILLED' => 'The brand says it was sent',
                  'RECEIVED' => 'Received ✓',
                  _ => 'Cancelled',
                },
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const Spacer(),
              if (r.canConfirm)
                TextButton(onPressed: () => _confirm(r), child: const Text('I got it')),
            ],
          ),
        ],
      ),
    );
  }
}
