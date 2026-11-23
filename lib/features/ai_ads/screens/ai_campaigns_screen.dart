import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_campaign_bits.dart';
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

/// How the list is sorted / filtered (the approved campaign list, backend ADR 141).
enum _Sort { endingSoon, newest, prize, joined }

class _AiCampaignsScreenState extends State<AiCampaignsScreen> {
  final _service = AiAdsService();
  List<AiCampaignSummary> _campaigns = [];
  _Sort _sort = _Sort.endingSoon;
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

  List<AiCampaignSummary> get _shown {
    final far = DateTime(9999);
    final list = _sort == _Sort.joined
        ? _campaigns.where((c) => c.myStatus != null).toList()
        : [..._campaigns];
    switch (_sort) {
      case _Sort.endingSoon:
      case _Sort.joined:
        list.sort((a, b) => (a.deadline ?? far).compareTo(b.deadline ?? far));
      case _Sort.newest:
        list.sort((a, b) => (b.liveAt ?? DateTime(0)).compareTo(a.liveAt ?? DateTime(0)));
      case _Sort.prize:
        list.sort((a, b) => (b.prize?.amount ?? -1).compareTo(a.prize?.amount ?? -1));
    }
    return list;
  }

  Widget _filters() {
    final joined = _campaigns.where((c) => c.myStatus != null).length;
    final options = [
      (_Sort.endingSoon, 'Ending soon'),
      (_Sort.newest, 'New'),
      if (AiCampaignBits.showPrizes) (_Sort.prize, 'Highest prize'),
      (_Sort.joined, joined == 0 ? 'Joined' : 'Joined · $joined'),
    ];
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (sort, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _sort = sort),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _sort == sort ? AiUi.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _sort == sort ? AiUi.accent : Colors.white12),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _sort == sort ? Colors.white : AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: _sort == sort ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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
                  else ...[
                    _filters(),
                    const SizedBox(height: 12),
                    if (_shown.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Text("You haven't joined a campaign yet.",
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
                      ),
                    for (final c in _shown) ...[_card(c), const SizedBox(height: 10)],
                  ],
                ],
              ),
      ),
    );
  }

  Widget _card(AiCampaignSummary c) {
    final prize = AiCampaignBits.showPrizes ? c.prize?.short : null;
    final status = c.myStatus;
    return GestureDetector(
      onTap: () => _open(c),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: AiUi.cardDecoration(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 74, height: 96, child: AiCoverBackground(url: c.coverImage, bottomShade: 0.2)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (status != null) AiStandingChip(status: status),
                    AiTimeChip(deadline: c.deadline, prefix: status == 'ACTIVE' ? 'Due' : null),
                    if (c.participationMode == 'INVITE_ONLY') const AiChip(label: 'Invite only', color: AppColors.textMuted),
                  ]),
                  const SizedBox(height: 6),
                  Text(c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25)),
                  const SizedBox(height: 3),
                  Text(
                    [if (c.brand.name.isNotEmpty) c.brand.name, c.format.label].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            if (prize != null && prize.isNotEmpty) prize,
                            AiCampaignBits.seatsLabel(c.seatsLeft, c.creatorCap),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textFaint, fontSize: 11.5),
                        ),
                      ),
                      Text(
                        switch (status) {
                          'ACTIVE' => 'Create ›',
                          'REQUESTED' => 'Pending',
                          'INVITED' => 'See invite ›',
                          null => 'Join ›',
                          _ => 'View ›',
                        },
                        style: TextStyle(
                          color: switch (status) {
                            'ACTIVE' => AiCampaignBits.joinedColor,
                            'REQUESTED' => AiCampaignBits.timeColor,
                            _ => AiCampaignBits.lilac,
                          },
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
