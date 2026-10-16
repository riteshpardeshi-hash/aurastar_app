import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_job_status_badge.dart';
import '../widgets/ai_ui.dart';
import 'ai_campaign_screen.dart';
import 'ai_rewards_screen.dart';
import '../../../core/services/app_config_service.dart';

/// Live AI ad campaigns a creator can take part in — one brand's (from its
/// profile) or all of them — plus the campaigns they're already in.
class AiCampaignsScreen extends StatefulWidget {
  final String? brandId;
  final String? brandName;

  const AiCampaignsScreen({super.key, this.brandId, this.brandName});

  @override
  State<AiCampaignsScreen> createState() => _AiCampaignsScreenState();
}

class _AiCampaignsScreenState extends State<AiCampaignsScreen> {
  final _service = AiAdsService();
  List<AiCampaignSummary> _campaigns = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final campaigns = await _service.listCampaigns(brandId: widget.brandId);
      if (!mounted) return;
      setState(() {
        _campaigns = campaigns;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AiAdsException ? e.message : "Couldn't load campaigns. Pull to retry.";
      });
    }
  }

  Future<void> _open(AiCampaignSummary c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AiCampaignScreen(campaignId: c.id)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AiUi.bg,
      appBar: AiUi.appBar(
        widget.brandName == null ? 'AI ad campaigns' : '${widget.brandName} · AI ads',
        actions: [
          // Prizes follow the coupons switch (ADR 119): no rewards entry while it's off.
          ValueListenableBuilder<bool>(
            valueListenable: AppConfigService.instance.couponsEnabled,
            builder: (context, on, _) => on
                ? IconButton(
                    tooltip: 'My rewards',
                    icon: const Icon(Icons.card_giftcard_rounded),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiRewardsScreen())),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AiUi.accent,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AiUi.accent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_error != null)
                    Padding(padding: const EdgeInsets.only(top: 40), child: AiWarningText(_error!))
                  else if (_campaigns.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 60),
                      child: Text(
                        'No AI ad campaigns right now.\nYou\'ll get a notification when a brand invites you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textFaint, fontSize: 13, height: 1.5),
                      ),
                    )
                  else
                    for (final c in _campaigns) ...[_card(c), const SizedBox(height: 10)],
                ],
              ),
      ),
    );
  }

  Widget _card(AiCampaignSummary c) {
    final deadline = c.deadline;
    return GestureDetector(
      onTap: () => _open(c),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AiUi.cardDecoration(),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (c.myStatus != null) ...[AiStatusBadge.participation(c.myStatus!), const SizedBox(height: 8)],
                  Text(c.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  if (c.product.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(c.product, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (deadline != null) 'Ends ${deadline.day}/${deadline.month}',
                      if (c.seatsLeft != null) '${c.seatsLeft} spots left',
                      if (c.participationMode == 'INVITE_ONLY') 'Invite only',
                    ].join(' · '),
                    style: const TextStyle(color: AppColors.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
