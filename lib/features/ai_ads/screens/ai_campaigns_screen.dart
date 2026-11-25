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

/// How the list is sorted (the approved campaign list, backend ADR 141, plus the
/// usual list sorts). "Joined" is a filter, separate from the sort.
enum _Sort {
  endingSoon('Ending soon'),
  endingLast('Ending last'),
  newest('Newest'),
  oldest('Oldest'),
  nameAz('Name A–Z'),
  nameZa('Name Z–A'),
  mostCredits('Most AI credits'),
  prize('Highest prize');

  const _Sort(this.label);
  final String label;
}

class _AiCampaignsScreenState extends State<AiCampaignsScreen> {
  final _service = AiAdsService();
  List<AiCampaignSummary> _campaigns = [];
  _Sort _sort = _Sort.endingSoon;
  bool _joinedOnly = false;
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// A campaign matches when every word typed (any case, any order) appears in its
  /// campaign name or brand name — only those two, as the client asked.
  bool _matches(AiCampaignSummary c) {
    final words = _search.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return true;
    final text = '${c.title} ${c.brand.name}'.toLowerCase();
    return words.every(text.contains);
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
        _error = e is AiAdsException ? e.message : "Couldn't load contests. Pull to retry.";
      });
    }
  }

  Future<void> _open(AiCampaignSummary c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AiCampaignScreen(campaignId: c.id)));
    if (mounted) _load();
  }

  List<AiCampaignSummary> get _shown {
    final far = DateTime(9999), past = DateTime(0);
    final list = _campaigns
        .where((c) => !_joinedOnly || AiCampaignBits.isJoined(c.myStatus))
        .where(_matches)
        .toList();
    int byName(AiCampaignSummary a, AiCampaignSummary b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    final Comparator<AiCampaignSummary> cmp = switch (_sort) {
      _Sort.endingSoon => (a, b) => (a.deadline ?? far).compareTo(b.deadline ?? far),
      _Sort.endingLast => (a, b) => (b.deadline ?? past).compareTo(a.deadline ?? past),
      _Sort.newest => (a, b) => (b.liveAt ?? past).compareTo(a.liveAt ?? past),
      _Sort.oldest => (a, b) => (a.liveAt ?? far).compareTo(b.liveAt ?? far),
      _Sort.nameAz => byName,
      _Sort.nameZa => (a, b) => byName(b, a),
      _Sort.mostCredits => (a, b) => (b.creditsPerCreator ?? -1).compareTo(a.creditsPerCreator ?? -1),
      _Sort.prize => (a, b) => (b.prize?.amount ?? -1).compareTo(a.prize?.amount ?? -1),
    };
    // Ties keep a stable, predictable order: by name.
    list.sort((a, b) {
      final r = cmp(a, b);
      return r != 0 ? r : byName(a, b);
    });
    return list;
  }

  Widget _searchBar() {
    return TextField(
      key: const Key('ai-campaigns-search'),
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _search = v.trim()),
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: AiUi.accent,
      decoration: InputDecoration(
        hintText: 'Search by contest or brand name',
        hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 13.5),
        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 20),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
              ),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF14141F),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AiUi.accent, width: 1),
        ),
      ),
    );
  }

  Future<void> _pickSort() async {
    final options = [for (final o in _Sort.values) if (o != _Sort.prize || AiCampaignBits.showPrizes) o];
    final picked = await showModalBottomSheet<_Sort>(
      context: context,
      backgroundColor: const Color(0xFF14141F),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort by', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            for (final o in options)
              ListTile(
                title: Text(o.label,
                    style: TextStyle(
                      color: o == _sort ? Colors.white : AppColors.textMuted,
                      fontWeight: o == _sort ? FontWeight.w700 : FontWeight.w500,
                    )),
                trailing: o == _sort ? const Icon(Icons.check_rounded, color: AiUi.accent) : null,
                onTap: () => Navigator.pop(context, o),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Widget _chip({Key? key, required String label, required bool selected, IconData? icon, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AiUi.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? AiUi.accent : Colors.white12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: AppColors.textMuted), const SizedBox(width: 4)],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppColors.textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _filters() {
    final joined = _campaigns.where((c) => AiCampaignBits.isJoined(c.myStatus)).length;
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(
            key: const Key('ai-campaigns-sort'),
            label: _sort.label,
            icon: Icons.swap_vert_rounded,
            selected: false,
            onTap: _pickSort,
          ),
          _chip(label: 'All', selected: !_joinedOnly, onTap: () => setState(() => _joinedOnly = false)),
          _chip(
            label: joined == 0 ? 'Joined' : 'Joined · $joined',
            selected: _joinedOnly,
            onTap: () => setState(() => _joinedOnly = true),
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
        widget.brandName == null ? 'Ai Ad Contests' : '${widget.brandName} · AI ads',
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
                        'No Ai Ad Contests right now.\nYou\'ll get a notification when a brand invites you.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textFaint, fontSize: 13, height: 1.5),
                      ),
                    )
                  else ...[
                    _searchBar(),
                    const SizedBox(height: 10),
                    _filters(),
                    const SizedBox(height: 12),
                    if (_shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Text(
                            _search.isNotEmpty
                                ? 'No contests match "$_search".'
                                : _joinedOnly
                                    ? "You haven't joined a contest yet."
                                    : 'No contests to show.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textFaint, fontSize: 13)),
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
    // A full campaign the creator isn't part of can't be joined — don't offer it.
    final full = status == null && c.seatsLeft != null && c.seatsLeft! <= 0;
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
                            if (status == 'ACTIVE' || status == 'SUBMITTED')
                              "You're in"
                            else
                              AiCampaignBits.seatsLabel(c.seatsLeft, c.creatorCap, inviteOnly: c.participationMode == 'INVITE_ONLY'),
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
                          null when full => 'Full',
                          null => 'Join ›',
                          _ => 'View ›',
                        },
                        style: TextStyle(
                          color: switch (status) {
                            'ACTIVE' => AiCampaignBits.joinedColor,
                            'REQUESTED' => AiCampaignBits.timeColor,
                            null when full => AppColors.textFaint,
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
