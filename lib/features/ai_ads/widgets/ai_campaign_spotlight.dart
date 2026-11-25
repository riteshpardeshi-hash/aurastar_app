import 'package:flutter/material.dart';

import '../../../core/services/ai_ads_service.dart';
import '../../../core/services/analytics_service.dart';
import '../../creator/screens/create_creator_profile_screen.dart';
import '../screens/ai_campaign_screen.dart';
import '../screens/ai_campaigns_screen.dart';
import '../screens/create_ai_videos_screen.dart';
import 'ai_campaign_bits.dart';
import 'ai_dialogs.dart';
import 'package:aura_app/shared/theme/app_text_styles.dart';
import 'package:aura_app/shared/widgets/see_all_link.dart';

/// The top of a creator's home screen: open AI ad campaigns as big swipeable cards (the
/// client-approved "campaign spotlight", backend ADR 141).
///
/// The list comes from `GET /creator/ai-campaigns`, which only ever holds live, open campaigns
/// before their deadline (never invite-only) plus the ones this creator is already in. Each
/// card shows the brand, cover, time left, seats, prize and the creator's next step: Join,
/// Pending, Create video.
///
/// Every signed-in user sees it (client, 24 Nov). For someone who isn't a creator
/// ([isCreator] false), any tap asks them to become one and, if they agree, opens the creator
/// application.
///
/// When there are no campaigns (or they can't be loaded), [fallback] is shown instead — the
/// home's usual Featured carousel — so the top of the home is never empty.
class AiCampaignSpotlight extends StatefulWidget {
  final Widget fallback;

  /// For tests: replaces the network call.
  final Future<List<AiCampaignSummary>> Function()? loader;

  /// False for a player: taps lead to the become-a-creator prompt instead of the campaign.
  final bool isCreator;

  const AiCampaignSpotlight({super.key, required this.fallback, this.loader, this.isCreator = true});

  @override
  State<AiCampaignSpotlight> createState() => _AiCampaignSpotlightState();
}

class _AiCampaignSpotlightState extends State<AiCampaignSpotlight> {
  static const _accent = Color(0xFF7B2CBF);

  final _pageController = PageController();
  List<AiCampaignSummary> _campaigns = const [];
  bool _loaded = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<AiCampaignSummary> campaigns;
    try {
      campaigns = await (widget.loader ?? () => AiAdsService().listCampaigns())();
    } catch (_) {
      campaigns = const [];
    }
    if (!mounted) return;
    final ordered = _order(campaigns);
    // Coming back from a campaign reloads the list: stay on the card the creator was on (the
    // PageView keeps its page), only stepping back when the list got shorter — so the dots
    // and the card shown never disagree.
    final keep = ordered.isEmpty ? 0 : _index.clamp(0, ordered.length - 1);
    setState(() {
      _campaigns = ordered;
      _loaded = true;
      _index = keep;
    });
    if (_pageController.hasClients && (_pageController.page?.round() ?? 0) != keep) {
      _pageController.jumpToPage(keep);
    }
  }

  /// Campaigns the creator is in come first (their next step), then open ones by deadline.
  /// Full campaigns they aren't part of can't be joined, so they're left out.
  static List<AiCampaignSummary> _order(List<AiCampaignSummary> all) {
    final mine = all.where((c) => c.myStatus != null).toList();
    final open = all.where((c) => c.myStatus == null && (c.seatsLeft == null || c.seatsLeft! > 0)).toList();
    int byDeadline(AiCampaignSummary a, AiCampaignSummary b) =>
        (a.deadline ?? DateTime(9999)).compareTo(b.deadline ?? DateTime(9999));
    mine.sort(byDeadline);
    open.sort(byDeadline);
    return [...mine, ...open];
  }

  /// Runs [action] for a creator; anyone else is asked to become a creator first.
  Future<void> _asCreator(Future<void> Function() action) async {
    if (widget.isCreator) return action();
    if (!await showBecomeCreatorDialog(context) || !mounted) return;
    AnalyticsService().logAuraCreatorJoinClick('ai_campaign_banner');
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateCreatorProfileScreen()));
  }

  Future<void> _openCampaign(AiCampaignSummary c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AiCampaignScreen(campaignId: c.id)));
    if (mounted) _load();
  }

  Future<void> _primary(AiCampaignSummary c) async {
    if (c.myStatus == 'ACTIVE') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateAiVideosScreen(campaignId: c.id)));
      if (mounted) _load();
      return;
    }
    // Join (the application form with the terms), the invite, or the request's status all
    // live on the campaign screen.
    await _openCampaign(c);
  }

  Future<void> _seeAll() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AiCampaignsScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox(height: 8);
    if (_campaigns.isEmpty) return widget.fallback;

    return Column(
      key: const Key('ai-campaign-spotlight'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'AI Ad Contests',
                  style: AppTextStyles.sectionHeader,
                ),
              ),
              SeeAllLink(
                onTap: () => _asCreator(_seeAll),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 316,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _campaigns.length,
            onPageChanged: (i) => setState(() => _index = i),
            physics: _campaigns.length > 1 ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: _SpotlightCard(
                campaign: _campaigns[i],
                onTap: () => _asCreator(() => _openCampaign(_campaigns[i])),
                onPrimary: () => _asCreator(() => _primary(_campaigns[i])),
              ),
            ),
          ),
        ),
        if (_campaigns.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_campaigns.length, (i) {
                final on = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: on ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: on ? _accent : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          )
        else
          const SizedBox(height: 16),
      ],
    );
  }
}

class _SpotlightCard extends StatelessWidget {
  final AiCampaignSummary campaign;
  final VoidCallback onTap;
  final VoidCallback onPrimary;

  const _SpotlightCard({required this.campaign, required this.onTap, required this.onPrimary});

  @override
  Widget build(BuildContext context) {
    final c = campaign;
    final status = c.myStatus;
    final taken = AiCampaignBits.seatsTaken(c.seatsLeft, c.creatorCap);
    final prize = AiCampaignBits.showPrizes ? c.prize?.short : null;
    final subtitle = [
      '${c.format.label} AI video',
      if (c.product.isNotEmpty) c.product,
    ].join(' · ');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF9D4EDD).withValues(alpha: 0.65), width: 1.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(19),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AiCoverBackground(url: c.coverImage),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        AiStandingChip(status: status),
                        AiTimeChip(deadline: c.deadline, prefix: status == 'ACTIVE' ? 'Due' : null),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        AiBrandAvatar(brand: c.brand),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            c.brand.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'ClashDisplay',
                        shadows: [Shadow(color: Colors.black54, blurRadius: 12)],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  if (status == 'ACTIVE' || status == 'SUBMITTED' || status == 'WINNER')
                                    c.creditsPerCreator == null ? 'You\'re in' : '${c.creditsPerCreator} AI credits'
                                  else
                                    AiCampaignBits.seatsLabel(
                                      c.seatsLeft,
                                      c.creatorCap,
                                      inviteOnly: c.participationMode == 'INVITE_ONLY',
                                    ),
                                  if (prize != null && prize.isNotEmpty) '$prize prize',
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 11.5),
                              ),
                              if (taken != null && status == null) ...[
                                const SizedBox(height: 6),
                                AiSeatsBar(value: taken),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _PrimaryButton(status: status, onPressed: onPrimary),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card's one action, by where the creator stands.
class _PrimaryButton extends StatelessWidget {
  final String? status;
  final VoidCallback onPressed;

  const _PrimaryButton({required this.status, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, border) = switch (status) {
      'ACTIVE' => ('Create video →', const Color(0xFF16A34A), Colors.white, null),
      'REQUESTED' => (
          'Pending',
          AiCampaignBits.timeColor.withValues(alpha: 0.15),
          AiCampaignBits.timeColor,
          AiCampaignBits.timeColor.withValues(alpha: 0.5),
        ),
      'INVITED' => ('See invite →', const Color(0xFF7B2CBF), Colors.white, null),
      'SUBMITTED' => ('View', Colors.white.withValues(alpha: 0.1), Colors.white, Colors.white24),
      'WINNER' => ('See your win →', AiCampaignBits.timeColor.withValues(alpha: 0.15), AiCampaignBits.timeColor, AiCampaignBits.timeColor.withValues(alpha: 0.5)),
      // Only someone not in the campaign is offered Join; any other standing opens it.
      null => ('Join →', const Color(0xFF7B2CBF), Colors.white, null),
      _ => ('View', Colors.white.withValues(alpha: 0.1), Colors.white, Colors.white24),
    };
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: border == null ? null : Border.all(color: border),
        ),
        child: Text(label, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
