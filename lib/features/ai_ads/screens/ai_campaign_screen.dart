import 'package:flutter/material.dart';
import '../../../core/services/ai_ads_service.dart';
import '../../../shared/theme/app_colors.dart';
import '../widgets/ai_dialogs.dart';
import '../widgets/ai_job_status_badge.dart';
import '../widgets/ai_ui.dart';
import 'ai_brand_assets_row.dart';
import 'ai_rewards_screen.dart';
import 'create_ai_videos_screen.dart';
import '../../../core/services/app_config_service.dart';

/// One campaign: the brief, the brand's assets, and the creator's standing —
/// join (with the ownership terms), answer an invite, wait for approval, or
/// open the workspace once in.
class AiCampaignScreen extends StatefulWidget {
  final String campaignId;

  const AiCampaignScreen({super.key, required this.campaignId});

  @override
  State<AiCampaignScreen> createState() => _AiCampaignScreenState();
}

class _AiCampaignScreenState extends State<AiCampaignScreen> {
  final _service = AiAdsService();
  AiCampaign? _campaign;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _service.fetchCampaign(widget.campaignId);
      if (!mounted) return;
      setState(() {
        _campaign = c;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AiAdsException ? e.message : "Couldn't load this campaign.";
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) AiUi.toast(context, done);
      await _load();
    } on AiAdsException catch (e) {
      if (mounted) AiUi.toast(context, e.message);
    } catch (_) {
      if (mounted) AiUi.toast(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(AiCampaign c) async {
    if (!await showAiTermsDialog(context, campaignTitle: c.title)) return;
    await _run(() => _service.requestToJoin(c.id), 'Request sent — the brand will review it.');
  }

  Future<void> _acceptInvite(AiCampaign c) async {
    if (!await showAiTermsDialog(context, campaignTitle: c.title)) return;
    await _run(() => _service.respondToInvite(c.myParticipation!.id, accept: true), "You're in!");
  }

  Future<void> _openWorkspace(AiCampaign c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateAiVideosScreen(campaignId: c.id)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = _campaign;
    return Scaffold(
      backgroundColor: AiUi.bg,
      appBar: AiUi.appBar(c?.title ?? 'AI ad campaign'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AiUi.accent))
          : c == null
          ? Center(child: Text(_error ?? 'Campaign not found', style: const TextStyle(color: AppColors.textMuted)))
          : RefreshIndicator(
              onRefresh: _load,
              color: AiUi.accent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (c.myParticipation != null) AiStatusBadge.participation(c.myParticipation!.status),
                  const AiSectionTitle('Brand brief'),
                  _briefCard(c),
                  const AiSectionTitle('Brand assets'),
                  AiBrandAssetsRow(assets: c.assets),
                  const SizedBox(height: 24),
                  _action(c),
                ],
              ),
            ),
    );
  }

  Widget _briefCard(AiCampaign c) {
    final b = c.brief;
    Widget list(String title, List<String> items) => items.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('$title\n${items.map((i) => '• $i').join('\n')}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.45)),
          );
    final deadline = c.deadline;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AiUi.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(b.summary, style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.45)),
          list('Do', b.dos),
          list("Don't", b.donts),
          list('Never claim', b.forbiddenClaims),
          const SizedBox(height: 10),
          Text(
            [
              '${c.format.aspectRatio} · ${c.format.minDurationSeconds}–${c.format.maxDurationSeconds}s · ${c.format.language}',
              if (deadline != null) 'Deadline ${deadline.day}/${deadline.month}/${deadline.year}',
            ].join('\n'),
            style: const TextStyle(color: AppColors.textFaint, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _action(AiCampaign c) {
    final p = c.myParticipation;
    final status = p?.status;
    if (status == null || status == 'DECLINED' || status == 'REVOKED' || status == 'WITHDRAWN') {
      if (c.participationMode == 'INVITE_ONLY') {
        return const Text('This campaign is invite-only.',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted));
      }
      if (!c.isLive || (c.seatsLeft != null && c.seatsLeft! <= 0)) {
        return const Text("This campaign isn't taking creators right now.",
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted));
      }
      return AiPrimaryButton(label: 'Ask to join', onPressed: () => _join(c), busy: _busy);
    }
    return switch (status) {
      'INVITED' => Column(children: [
          AiPrimaryButton(label: 'Accept invite', onPressed: () => _acceptInvite(c), busy: _busy),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _busy ? null : () => _run(() => _service.respondToInvite(p!.id, accept: false), 'Invite declined.'),
            child: const Text('Decline', style: TextStyle(color: AppColors.textMuted)),
          ),
        ]),
      'REQUESTED' => Column(children: [
          const Text('Waiting for the brand to approve you.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
          TextButton(
            onPressed: _busy ? null : () => _run(() => _service.withdraw(c.id), 'Request withdrawn.'),
            child: const Text('Withdraw request', style: TextStyle(color: AppColors.textMuted)),
          ),
        ]),
      'ACTIVE' || 'SUBMITTED' => Column(children: [
          if (c.hasEnded)
            Text(
              c.status == 'CANCELLED'
                  ? 'This campaign was cancelled.'
                  : 'This campaign has ended — the brand is picking the winners.',
              key: const Key('ai-campaign-ended'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            )
          else ...[
            Text('${p!.creditsLeft} credits to make your ad',
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            if (c.isPaused) ...[
              const SizedBox(height: 6),
              const Text('The brand has paused this campaign for now — you can look, but not create.',
                  key: Key('ai-campaign-paused'),
                  textAlign: TextAlign.center, style: TextStyle(color: AiUi.warning, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            AiPrimaryButton(label: 'Open my workspace', onPressed: () => _openWorkspace(c)),
          ],
          if (status == 'SUBMITTED' && p!.finalScore != null) ...[
            const SizedBox(height: 10),
            Text('Your final ad is submitted · AI score ${p.finalScore}',
                textAlign: TextAlign.center, style: const TextStyle(color: AiUi.success, fontSize: 12)),
          ],
        ]),
      'WINNER' => Column(children: [
          const Text('Your ad won! 🏆', style: TextStyle(color: AiUi.warning, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          // Prizes follow the coupons switch (ADR 119): no rewards entry while it's off.
          if (AppConfigService.instance.couponsEnabled.value)
            AiSecondaryButton(
              label: 'See my rewards',
              icon: Icons.card_giftcard_rounded,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AiRewardsScreen())),
            ),
        ]),
      _ => Text(
          switch (status) {
            'NOT_SELECTED' => "The campaign has finished — your ad wasn't picked this time.",
            'REJECTED' => "The brand didn't accept your request.",
            'REMOVED' => 'You were removed from this campaign.',
            _ => status,
          },
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted),
        ),
    };
  }
}
