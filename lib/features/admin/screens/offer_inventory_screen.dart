import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Offer type helpers (mirrors admin_offers_screen.dart)
enum _OType { percent, fixed, freebie }
extension _OTypeX on _OType {
  String get key   => name;
  Color  get color => switch (this) {
    _OType.percent  => const Color(0xFF06B6D4),
    _OType.fixed    => const Color(0xFF22C55E),
    _OType.freebie  => const Color(0xFFD4A8FF),
  };
  IconData get icon => switch (this) {
    _OType.percent  => Icons.percent_rounded,
    _OType.fixed    => Icons.currency_rupee_rounded,
    _OType.freebie  => Icons.card_giftcard_rounded,
  };
  static _OType from(String? k) => switch (k) {
    'percent' => _OType.percent,
    'fixed'   => _OType.fixed,
    _         => _OType.freebie,
  };
}

// ── Main screen ───────────────────────────────────────────────────────────────

class OfferInventoryScreen extends StatefulWidget {
  final String offerId;
  const OfferInventoryScreen({super.key, required this.offerId});

  @override
  State<OfferInventoryScreen> createState() => _OfferInventoryScreenState();
}

class _OfferInventoryScreenState extends State<OfferInventoryScreen> {
  static const _bg   = Color(0xFF080810);
  static const _card = Color(0xFF100A20);

  bool _showAllAvailable = false;
  bool _showAllClaimed   = false;
  int  _tab              = 0; // 0 = Available, 1 = Claimed

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('offers')
          .doc(widget.offerId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return Scaffold(
            backgroundColor: _bg,
            appBar: AppBar(backgroundColor: _bg, foregroundColor: Colors.white),
            body: const Center(
                child:
                    CircularProgressIndicator(color: Color(0xFF7B2CBF))),
          );
        }

        final d           = snap.data!.data() as Map<String, dynamic>;
        final title       = d['title']       as String? ?? 'Offer';
        final brand       = d['brand']       as String? ?? '';
        final description = d['description'] as String? ?? '';
        final type        = _OTypeX.from(d['type'] as String?);
        final value       = (d['value']      as num?)?.toInt() ?? 0;
        final status      = d['status']      as String? ?? 'active';
        final expiresAt   = d['expiresAt']   as Timestamp?;
        final totalCodes  = (d['totalCodes'] as num?)?.toInt() ?? 0;

        final available = List<String>.from(
            (d['codesPool'] as List?)?.map((e) => e.toString()) ?? []);
        final claimedRaw = (d['claimedCodes'] as List?) ?? [];
        final claimed = claimedRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        final claimedCount  = claimed.length;
        final isExpired     = status == 'expired' ||
            (expiresAt != null &&
                expiresAt.toDate().isBefore(DateTime.now()));

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            foregroundColor: Colors.white,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800,
                        fontFamily: 'ClashDisplay')),
                if (brand.isNotEmpty)
                  Text(brand,
                      style: TextStyle(
                          color: type.color.withValues(alpha: 0.80),
                          fontSize: 11,
                          fontWeight: FontWeight.w500)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit offer',
                onPressed: () => _showEditSheet(context, d),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Stats row ────────────────────────────────────────────────
                _StatsRow(
                  available: available.length,
                  claimed:   claimedCount,
                  total:     totalCodes,
                  type:      type,
                  value:     value,
                ),
                const SizedBox(height: 16),

                // ── Status management ────────────────────────────────────────
                _StatusCard(
                  offerId: widget.offerId,
                  status:  status,
                  isExpired: isExpired,
                  onChanged: _snack,
                ),
                const SizedBox(height: 14),

                // ── Expiry management ────────────────────────────────────────
                _ExpiryCard(
                  offerId:   widget.offerId,
                  expiresAt: expiresAt,
                  onChanged: _snack,
                ),
                const SizedBox(height: 14),

                // ── Description ──────────────────────────────────────────────
                if (description.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    child: Text(description,
                        style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            height: 1.45)),
                  ),
                  const SizedBox(height: 14),
                ],

                // ── Tab toggle ───────────────────────────────────────────────
                _TabToggle(
                  selected: _tab,
                  labels:   ['Available (${available.length})',
                              'Claimed ($claimedCount)'],
                  onTap:    (i) => setState(() {
                    _tab = i;
                    _showAllAvailable = false;
                    _showAllClaimed   = false;
                  }),
                ),
                const SizedBox(height: 14),

                // ── Code lists ───────────────────────────────────────────────
                if (_tab == 0)
                  _AvailableCodesSection(
                    offerId:   widget.offerId,
                    codes:     available,
                    showAll:   _showAllAvailable,
                    onShowAll: () =>
                        setState(() => _showAllAvailable = true),
                    onSnack:   _snack,
                  )
                else
                  _ClaimedCodesSection(
                    claimed:  claimed,
                    showAll:  _showAllClaimed,
                    onShowAll: () =>
                        setState(() => _showAllClaimed = true),
                  ),

                const SizedBox(height: 28),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),

                // ── Danger zone ──────────────────────────────────────────────
                _DangerZone(
                  offerId:    widget.offerId,
                  available:  available.length,
                  isExpired:  isExpired,
                  onSnack:    _snack,
                  onDeleted:  () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
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

  void _showEditSheet(BuildContext context, Map<String, dynamic> d) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) =>
          _EditOfferSheet(offerId: widget.offerId, data: d),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int    available;
  final int    claimed;
  final int    total;
  final _OType type;
  final int    value;

  const _StatsRow({
    required this.available,
    required this.claimed,
    required this.total,
    required this.type,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? available / total : 0.0;
    final typeDisplay = switch (type) {
      _OType.percent => '$value% off',
      _OType.fixed   => '₹$value off',
      _OType.freebie => 'Free gift',
    };

    return Column(
      children: [
        Row(
          children: [
            _StatChip('Available', '$available',
                type.color, Icons.confirmation_number_outlined),
            const SizedBox(width: 10),
            _StatChip('Claimed', '$claimed',
                Colors.amber, Icons.check_circle_outline_rounded),
            const SizedBox(width: 10),
            _StatChip('Total', '$total',
                Colors.white38, Icons.inventory_2_outlined),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOut,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 7,
              backgroundColor: Colors.white.withValues(alpha: 0.07),
              valueColor: AlwaysStoppedAnimation(
                available == 0
                    ? Colors.red.shade400
                    : available < total * 0.2
                        ? Colors.amber
                        : type.color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$available of $total codes remaining',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
            Row(children: [
              Icon(type.icon, color: type.color, size: 12),
              const SizedBox(width: 4),
              Text(typeDisplay,
                  style: TextStyle(
                      color: type.color.withValues(alpha: 0.80),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String   label;
  final String   value;
  final Color    color;
  final IconData icon;
  const _StatChip(this.label, this.value, this.color, this.icon);

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF100A20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(height: 4),
              Text(value,
                  style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      );
}

// ── Status card ───────────────────────────────────────────────────────────────

class _StatusCard extends StatefulWidget {
  final String   offerId;
  final String   status;
  final bool     isExpired;
  final void Function(String, {bool error}) onChanged;

  const _StatusCard({
    required this.offerId,
    required this.status,
    required this.isExpired,
    required this.onChanged,
  });

  @override
  State<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends State<_StatusCard> {
  bool _loading = false;

  Future<void> _set(String newStatus) async {
    if (newStatus == 'expired') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A0A2E),
          title: const Text('Mark as Expired?',
              style: TextStyle(color: Colors.white)),
          content: const Text(
              'This will prevent new redemptions. Remaining codes stay in the pool.',
              style: TextStyle(color: Colors.white54)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white38))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Expire',
                    style: TextStyle(color: Colors.red.shade400))),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance
          .collection('offers')
          .doc(widget.offerId)
          .update({'status': newStatus});
      widget.onChanged('Status → $newStatus');
    } catch (e) {
      widget.onChanged('Failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const states = [
      ('active',  'Active',  Color(0xFF22C55E)),
      ('paused',  'Paused',  Color(0xFFF59E0B)),
      ('expired', 'Expired', Color(0xFFEF4444)),
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF100A20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Status',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4)),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
                child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                        color: Color(0xFF7B2CBF), strokeWidth: 2)))
          else
            Row(
              children: states.map((s) {
                final key   = s.$1;
                final label = s.$2;
                final color = s.$3;
                final isCurrent = widget.status == key ||
                    (key == 'expired' && widget.isExpired);

                return Expanded(
                  child: GestureDetector(
                    onTap: isCurrent ? null : () => _set(key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(
                          right: key != 'expired' ? 8 : 0),
                      padding:
                          const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? color.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent
                              ? color.withValues(alpha: 0.60)
                              : Colors.white.withValues(alpha: 0.08),
                          width: isCurrent ? 1.5 : 1,
                        ),
                      ),
                      child: Text(label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color:
                                  isCurrent ? color : Colors.white24,
                              fontSize: 12,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

// ── Expiry card ───────────────────────────────────────────────────────────────

class _ExpiryCard extends StatefulWidget {
  final String     offerId;
  final Timestamp? expiresAt;
  final void Function(String, {bool error}) onChanged;

  const _ExpiryCard({
    required this.offerId,
    required this.expiresAt,
    required this.onChanged,
  });

  @override
  State<_ExpiryCard> createState() => _ExpiryCardState();
}

class _ExpiryCardState extends State<_ExpiryCard> {
  static const _accent = Color(0xFF7B2CBF);

  String get _expiryDisplay {
    final ts = widget.expiresAt;
    if (ts == null) return 'No expiry set';
    final d = ts.toDate();
    final days = d.difference(DateTime.now()).inDays;
    if (days < 0) return 'Expired ${-days}d ago';
    if (days == 0) return 'Expires today';
    return '${d.day}/${d.month}/${d.year}  ($days day${days == 1 ? '' : 's'} left)';
  }

  Color get _expiryColor {
    final ts = widget.expiresAt;
    if (ts == null) return Colors.white38;
    final days = ts.toDate().difference(DateTime.now()).inDays;
    if (days < 0) return Colors.red.shade400;
    if (days <= 7) return Colors.amber;
    return Colors.white70;
  }

  Future<void> _changeExpiry() async {
    final now = DateTime.now();
    final initial = widget.expiresAt != null
        ? widget.expiresAt!.toDate()
        : now.add(const Duration(days: 30));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? initial : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _accent,
            onPrimary: Colors.white,
            surface: Color(0xFF1A0A2E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('offers')
          .doc(widget.offerId)
          .update({'expiresAt': Timestamp.fromDate(picked)});
      widget.onChanged('Expiry updated');
    } catch (e) {
      widget.onChanged('Failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF100A20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: _expiryColor, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Expiry',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_expiryDisplay,
                    style: TextStyle(
                        color: _expiryColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          GestureDetector(
            onTap: _changeExpiry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: _accent.withValues(alpha: 0.35)),
              ),
              child: const Text('Change',
                  style: TextStyle(
                      color: Color(0xFFD4A8FF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tab toggle ────────────────────────────────────────────────────────────────

class _TabToggle extends StatelessWidget {
  final int            selected;
  final List<String>   labels;
  final ValueChanged<int> onTap;

  const _TabToggle({
    required this.selected,
    required this.labels,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final sel = selected == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: sel
                      ? const Color(0xFF7B2CBF).withValues(alpha: 0.35)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(
                  child: Text(labels[i],
                      style: TextStyle(
                          color: sel ? Colors.white : Colors.white38,
                          fontSize: 12,
                          fontWeight: sel
                              ? FontWeight.w700
                              : FontWeight.w400)),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Available codes section ───────────────────────────────────────────────────

class _AvailableCodesSection extends StatelessWidget {
  final String       offerId;
  final List<String> codes;
  final bool         showAll;
  final VoidCallback onShowAll;
  final void Function(String, {bool error}) onSnack;

  const _AvailableCodesSection({
    required this.offerId,
    required this.codes,
    required this.showAll,
    required this.onShowAll,
    required this.onSnack,
  });

  static const _limit = 40;

  Future<void> _revoke(BuildContext context, String code) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A2E),
        title: const Text('Revoke Code?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(code,
            style: const TextStyle(
                color: Color(0xFF06B6D4),
                fontSize: 13,
                fontFamily: 'monospace')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Revoke',
                  style: TextStyle(color: Colors.red.shade400))),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('offers')
          .doc(offerId)
          .update({'codesPool': FieldValue.arrayRemove([code])});
      onSnack('Code revoked');
    } catch (e) {
      onSnack('Failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (codes.isEmpty) {
      return _emptySection(
        icon: Icons.confirmation_number_outlined,
        label: 'No available codes',
        sub: 'All codes have been claimed or revoked.',
      );
    }

    final visible = showAll ? codes : codes.take(_limit).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: visible.map((code) => _CodeChip(
            code:     code,
            onRevoke: () => _revoke(context, code),
          )).toList(),
        ),
        if (!showAll && codes.length > _limit) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onShowAll,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Text(
                'Show all ${codes.length} codes',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String       code;
  final VoidCallback onRevoke;
  const _CodeChip({required this.code, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
      decoration: BoxDecoration(
        color: const Color(0xFF06B6D4).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF06B6D4).withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onLongPress: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied $code'),
                  backgroundColor: const Color(0xFF1A0A2E),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Text(code,
                style: const TextStyle(
                    color: Color(0xFF06B6D4),
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRevoke,
            child: const Icon(Icons.close_rounded,
                color: Colors.white24, size: 13),
          ),
        ],
      ),
    );
  }
}

// ── Claimed codes section ─────────────────────────────────────────────────────

class _ClaimedCodesSection extends StatelessWidget {
  final List<Map<String, dynamic>> claimed;
  final bool         showAll;
  final VoidCallback onShowAll;

  const _ClaimedCodesSection({
    required this.claimed,
    required this.showAll,
    required this.onShowAll,
  });

  static const _limit = 30;

  @override
  Widget build(BuildContext context) {
    if (claimed.isEmpty) {
      return _emptySection(
        icon: Icons.check_circle_outline_rounded,
        label: 'No claimed codes yet',
        sub: 'Codes will appear here when users redeem them.',
      );
    }

    final visible = showAll ? claimed : claimed.take(_limit).toList();

    return Column(
      children: [
        ...visible.map((r) {
          final code      = r['code']       as String? ?? '—';
          final userId    = r['userId']     as String? ?? '';
          final claimedAt = r['claimedAt']  as Timestamp?;

          String timeLabel = '—';
          if (claimedAt != null) {
            final diff = DateTime.now().difference(claimedAt.toDate());
            if (diff.inDays > 0) {
              timeLabel = '${diff.inDays}d ago';
            } else if (diff.inHours > 0) {
              timeLabel = '${diff.inHours}h ago';
            } else {
              timeLabel = '${diff.inMinutes}m ago';
            }
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF100A20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF22C55E), size: 14),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(code,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600)),
                ),
                if (userId.isNotEmpty) ...[
                  Text(
                    '@${userId.length > 8 ? userId.substring(0, 8) : userId}…',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 11)),
                  const SizedBox(width: 10),
                ],
                Text(timeLabel,
                    style: const TextStyle(
                        color: Colors.white24, fontSize: 11)),
              ],
            ),
          );
        }),
        if (!showAll && claimed.length > _limit) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onShowAll,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Text(
                'Show all ${claimed.length} claimed codes',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Danger zone ───────────────────────────────────────────────────────────────

class _DangerZone extends StatefulWidget {
  final String    offerId;
  final int       available;
  final bool      isExpired;
  final void Function(String, {bool error}) onSnack;
  final VoidCallback onDeleted;

  const _DangerZone({
    required this.offerId,
    required this.available,
    required this.isExpired,
    required this.onSnack,
    required this.onDeleted,
  });

  @override
  State<_DangerZone> createState() => _DangerZoneState();
}

class _DangerZoneState extends State<_DangerZone> {
  bool _loading = false;

  Future<void> _expireAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A2E),
        title: const Text('Expire All Codes?',
            style: TextStyle(color: Colors.white)),
        content: Text(
            'This will clear all ${widget.available} remaining codes and mark the offer expired. This cannot be undone.',
            style: const TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Expire All',
                  style: TextStyle(color: Colors.red.shade400))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance
          .collection('offers')
          .doc(widget.offerId)
          .update({'codesPool': [], 'status': 'expired'});
      widget.onSnack('All codes expired');
    } catch (e) {
      widget.onSnack('Failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0A2E),
        title: const Text('Delete Offer?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'This permanently deletes the offer and all its codes. Active redemptions are unaffected.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete',
                  style: TextStyle(color: Colors.red.shade400))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await FirebaseFirestore.instance
          .collection('offers')
          .doc(widget.offerId)
          .delete();
      widget.onDeleted();
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        widget.onSnack('Failed: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Danger Zone',
            style: TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        const SizedBox(height: 10),
        if (_loading)
          const Center(
              child: SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                      color: Colors.redAccent, strokeWidth: 2)))
        else
          Row(
            children: [
              if (!widget.isExpired && widget.available > 0)
                Expanded(
                  child: _DangerBtn(
                    label: 'Expire All Codes',
                    icon:  Icons.block_rounded,
                    color: Colors.amber,
                    onTap: _expireAll,
                  ),
                ),
              if (!widget.isExpired && widget.available > 0)
                const SizedBox(width: 10),
              Expanded(
                child: _DangerBtn(
                  label: 'Delete Offer',
                  icon:  Icons.delete_outline_rounded,
                  color: Colors.red.shade400,
                  onTap: _delete,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _DangerBtn extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final Color        color;
  final VoidCallback onTap;
  const _DangerBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

// ── Edit offer sheet ──────────────────────────────────────────────────────────

class _EditOfferSheet extends StatefulWidget {
  final String                offerId;
  final Map<String, dynamic>  data;
  const _EditOfferSheet({required this.offerId, required this.data});

  @override
  State<_EditOfferSheet> createState() => _EditOfferSheetState();
}

class _EditOfferSheetState extends State<_EditOfferSheet> {
  static const _accent = Color(0xFF7B2CBF);

  late final TextEditingController _titleCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _valueCtrl;
  late _OType    _type;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(
        text: widget.data['title'] as String? ?? '');
    _brandCtrl = TextEditingController(
        text: widget.data['brand'] as String? ?? '');
    _descCtrl  = TextEditingController(
        text: widget.data['description'] as String? ?? '');
    _valueCtrl = TextEditingController(
        text: '${(widget.data['value'] as num?)?.toInt() ?? 0}');
    _type      = _OTypeX.from(widget.data['type'] as String?);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _brandCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final brand = _brandCtrl.text.trim();
    if (title.isEmpty || brand.isEmpty) {
      _snack('Title and Brand are required', error: true);
      return;
    }

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
          .collection('offers')
          .doc(widget.offerId)
          .update({
        'title':       title,
        'brand':       brand,
        'description': _descCtrl.text.trim(),
        'type':        _type.key,
        'value':       int.tryParse(_valueCtrl.text.trim()) ?? 0,
        'updatedAt':   Timestamp.now(),
        'updatedBy':   uid,
      });
      if (!mounted) return;
      _snack('Offer updated');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Failed: $e', error: true);
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
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 18),
            const Text('Edit Offer',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay')),
            const SizedBox(height: 18),

            // Type selector
            Row(
              children: _OType.values.map((t) {
                final sel = _type == t;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(
                          right: t != _OType.freebie ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: sel
                            ? t.color.withValues(alpha: 0.18)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: sel
                              ? t.color.withValues(alpha: 0.60)
                              : Colors.white.withValues(alpha: 0.08),
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        switch (t) {
                          _OType.percent => '% Discount',
                          _OType.fixed   => 'Flat Amount',
                          _OType.freebie => 'Freebie',
                        },
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: sel ? t.color : Colors.white24,
                            fontSize: 11,
                            fontWeight: sel
                                ? FontWeight.w700
                                : FontWeight.w400)),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),
            _lbl('Title'),
            const SizedBox(height: 6),
            _fld(_titleCtrl, 'Offer title'),
            const SizedBox(height: 14),
            _lbl('Brand'),
            const SizedBox(height: 6),
            _fld(_brandCtrl, 'Brand name'),
            const SizedBox(height: 14),
            _lbl('Description'),
            const SizedBox(height: 6),
            _fld(_descCtrl, 'Short description…', maxLines: 2),

            if (_type != _OType.freebie) ...[
              const SizedBox(height: 14),
              _lbl(_type == _OType.percent
                  ? 'Discount %'
                  : 'Flat Amount (₹)'),
              const SizedBox(height: 6),
              _fld(_valueCtrl, '0',
                  keyboardType: TextInputType.number),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor:
                      Colors.white.withValues(alpha: 0.06),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700));

  Widget _fld(
    TextEditingController c,
    String hint, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText:  hint,
          hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
          filled:    true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accent, width: 1.5)),
        ),
      );
}

// ── Shared empty state ────────────────────────────────────────────────────────

Widget _emptySection({
  required IconData icon,
  required String   label,
  required String   sub,
}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white24, size: 40),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 4),
            Text(sub,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white24, fontSize: 11)),
          ],
        ),
      ),
    );
