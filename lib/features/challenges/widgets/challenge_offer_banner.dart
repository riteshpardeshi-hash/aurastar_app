import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ── Public banner widget — drop into any challenge detail screen ──────────────

class ChallengeOfferBanner extends StatelessWidget {
  final String challengeId;
  const ChallengeOfferBanner({super.key, required this.challengeId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || challengeId.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<_OfferContext>(
      future: _loadContext(uid),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final ctx = snap.data!;
        if (ctx.offer == null) return const SizedBox.shrink();
        return _OfferBannerCard(
          offer:       ctx.offer!,
          offerId:     ctx.offerId!,
          bestScore:   ctx.bestScore,
          existingCode: ctx.existingCode,
          uid:         uid,
        );
      },
    );
  }

  Future<_OfferContext> _loadContext(String uid) async {
    final db = FirebaseFirestore.instance;

    // 1. Find active offer for this challenge
    final offerSnap = await db
        .collection('offers')
        .where('challengeId', isEqualTo: challengeId)
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();

    if (offerSnap.docs.isEmpty) return const _OfferContext();

    final offerDoc = offerSnap.docs.first;
    final offerId  = offerDoc.id;
    final offer    = offerDoc.data();

    // Check expiry
    final expiresAt = offer['expiresAt'] as Timestamp?;
    if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
      return const _OfferContext();
    }

    // 2. Load in parallel: user's best score + existing claim
    final results = await Future.wait([
      db.collection('userChallengeProgress')
          .doc('${uid}_$challengeId')
          .get(),
      db.collection('users').doc(uid)
          .collection('offerClaims').doc(offerId)
          .get(),
    ]);

    final progressSnap = results[0];
    final claimSnap    = results[1];

    final progressData = progressSnap.exists ? progressSnap.data() : null;
    final bestScore =
        (progressData?['bestScore'] as num?)?.toInt() ?? 0;

    final claimData    = claimSnap.exists ? claimSnap.data() : null;
    final existingCode = claimData?['code'] as String?;

    return _OfferContext(
      offer:        offer,
      offerId:      offerId,
      bestScore:    bestScore,
      existingCode: existingCode,
    );
  }
}

class _OfferContext {
  final Map<String, dynamic>? offer;
  final String?               offerId;
  final int                   bestScore;
  final String?               existingCode;

  const _OfferContext({
    this.offer,
    this.offerId,
    this.bestScore = 0,
    this.existingCode,
  });
}

// ── Banner card ───────────────────────────────────────────────────────────────

class _OfferBannerCard extends StatelessWidget {
  final Map<String, dynamic> offer;
  final String               offerId;
  final int                  bestScore;
  final String?              existingCode;
  final String               uid;

  const _OfferBannerCard({
    required this.offer,
    required this.offerId,
    required this.bestScore,
    required this.existingCode,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    final title      = offer['title']    as String? ?? 'Exclusive Offer';
    final brand      = offer['brand']    as String? ?? '';
    final type       = offer['type']     as String? ?? 'percent';
    final value      = (offer['value']   as num?)?.toInt() ?? 0;
    final minScore   = (offer['minAuraScore'] as num?)?.toInt() ?? 0;
    final codesLeft  = (offer['codesPool'] as List?)?.length ?? 0;

    final typeDisplay = switch (type) {
      'percent' => '$value% off',
      'fixed'   => '₹$value off',
      _         => 'Free gift',
    };
    final typeColor = switch (type) {
      'percent' => const Color(0xFF06B6D4),
      'fixed'   => const Color(0xFF22C55E),
      _         => const Color(0xFFD4A8FF),
    };

    final alreadyClaimed = existingCode != null;
    final eligible       = bestScore >= minScore;
    final noCodesLeft    = codesLeft == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: GestureDetector(
        onTap: noCodesLeft && !alreadyClaimed
            ? null
            : () => _showClaimSheet(context, title, brand, typeDisplay,
                typeColor, minScore, eligible, alreadyClaimed),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: alreadyClaimed
                  ? [
                      const Color(0xFF22C55E).withValues(alpha: 0.12),
                      const Color(0xFF16A34A).withValues(alpha: 0.06),
                    ]
                  : [
                      const Color(0xFFF59E0B).withValues(alpha: 0.12),
                      const Color(0xFFD97706).withValues(alpha: 0.06),
                    ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: alreadyClaimed
                  ? const Color(0xFF22C55E).withValues(alpha: 0.35)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.40),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ────────────────────────────────────────────
              Row(
                children: [
                  // Brand avatar
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        brand.isNotEmpty ? brand[0].toUpperCase() : '★',
                        style: TextStyle(
                            color: typeColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: alreadyClaimed
                                    ? const Color(0xFF22C55E)
                                        .withValues(alpha: 0.15)
                                    : const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                alreadyClaimed ? '✓ CLAIMED' : 'BRAND OFFER',
                                style: TextStyle(
                                    color: alreadyClaimed
                                        ? const Color(0xFF22C55E)
                                        : const Color(0xFFF59E0B),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5),
                              ),
                            ),
                            if (brand.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(brand,
                                  style: TextStyle(
                                      color: typeColor
                                          .withValues(alpha: 0.80),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Value badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: typeColor.withValues(alpha: 0.45)),
                    ),
                    child: Text(typeDisplay,
                        style: TextStyle(
                            color: typeColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // ── Status bar ────────────────────────────────────────────
              if (alreadyClaimed)
                _ClaimedCodeRow(code: existingCode!)
              else if (noCodesLeft)
                _StatusRow(
                  icon:  Icons.inventory_2_outlined,
                  text:  'All codes claimed — check back later',
                  color: Colors.white38,
                )
              else if (!eligible)
                _StatusRow(
                  icon:  Icons.lock_outline_rounded,
                  text:  'Score $minScore+ to unlock  •  '
                         'Your best: $bestScore',
                  color: Colors.white54,
                )
              else
                _ClaimButton(
                  codesLeft: codesLeft,
                  onTap: () => _showClaimSheet(context, title, brand,
                      typeDisplay, typeColor, minScore, eligible,
                      alreadyClaimed),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showClaimSheet(
    BuildContext context,
    String title,
    String brand,
    String typeDisplay,
    Color typeColor,
    int minScore,
    bool eligible,
    bool alreadyClaimed,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ClaimSheet(
        offer:         offer,
        offerId:       offerId,
        uid:           uid,
        bestScore:     bestScore,
        minScore:      minScore,
        eligible:      eligible,
        existingCode:  existingCode,
        typeDisplay:   typeDisplay,
        typeColor:     typeColor,
      ),
    );
  }
}

// ── Small status widgets ──────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  final Color    color;
  const _StatusRow({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 12)),
          ),
        ],
      );
}

class _ClaimedCodeRow extends StatelessWidget {
  final String code;
  const _ClaimedCodeRow({required this.code});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Code "$code" copied!'),
              backgroundColor: const Color(0xFF1A0A2E),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        },
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF22C55E).withValues(alpha: 0.40)),
          ),
          child: Row(
            children: [
              const Icon(Icons.confirmation_number_rounded,
                  color: Color(0xFF22C55E), size: 15),
              const SizedBox(width: 8),
              Text(code,
                  style: const TextStyle(
                      color: Color(0xFF22C55E),
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0)),
              const Spacer(),
              const Icon(Icons.copy_rounded,
                  color: Colors.white38, size: 14),
              const SizedBox(width: 2),
              const Text('Tap to copy',
                  style: TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          ),
        ),
      );
}

class _ClaimButton extends StatelessWidget {
  final int        codesLeft;
  final VoidCallback onTap;
  const _ClaimButton({required this.codesLeft, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_open_rounded,
                  color: Colors.white, size: 15),
              const SizedBox(width: 6),
              const Text('Claim Your Code',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('($codesLeft left)',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      );
}

// ── Claim bottom sheet ────────────────────────────────────────────────────────

class _ClaimSheet extends StatefulWidget {
  final Map<String, dynamic> offer;
  final String               offerId;
  final String               uid;
  final int                  bestScore;
  final int                  minScore;
  final bool                 eligible;
  final String?              existingCode;
  final String               typeDisplay;
  final Color                typeColor;

  const _ClaimSheet({
    required this.offer,
    required this.offerId,
    required this.uid,
    required this.bestScore,
    required this.minScore,
    required this.eligible,
    required this.existingCode,
    required this.typeDisplay,
    required this.typeColor,
  });

  @override
  State<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends State<_ClaimSheet> {
  String? _claimedCode;
  bool    _claiming = false;

  @override
  void initState() {
    super.initState();
    _claimedCode = widget.existingCode;
  }

  Future<void> _claim() async {
    setState(() => _claiming = true);
    final db       = FirebaseFirestore.instance;
    final offerRef = db.collection('offers').doc(widget.offerId);
    final claimRef = db.collection('users').doc(widget.uid)
        .collection('offerClaims').doc(widget.offerId);

    try {
      String? code;

      await db.runTransaction((txn) async {
        final offerSnap = await txn.get(offerRef);
        if (!offerSnap.exists) throw Exception('offer_not_found');

        final data = offerSnap.data()!;
        final pool = List<String>.from(
            (data['codesPool'] as List?)?.map((e) => e.toString()) ?? []);
        if (pool.isEmpty) throw Exception('no_codes');

        code = pool.removeAt(0);

        final existing = List.from(
            (data['claimedCodes'] as List?) ?? []);
        existing.add({
          'code':      code,
          'userId':    widget.uid,
          'claimedAt': Timestamp.now(),
        });

        txn.update(offerRef, {
          'codesPool':    pool,
          'claimedCodes': existing,
        });
        txn.set(claimRef, {
          'code':       code,
          'offerId':    widget.offerId,
          'offerTitle': data['title'] ?? '',
          'brand':      data['brand'] ?? '',
          'type':       data['type'] ?? '',
          'value':      data['value'] ?? 0,
          'claimedAt':  Timestamp.now(),
        });
      });

      if (!mounted) return;
      setState(() {
        _claimedCode = code;
        _claiming    = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _claiming = false);
      final msg = e.toString().contains('no_codes')
          ? 'Sorry, all codes have been taken!'
          : 'Claim failed — please try again';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  void _copyCode() {
    if (_claimedCode == null) return;
    Clipboard.setData(ClipboardData(text: _claimedCode!));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Code "$_claimedCode" copied!'),
      backgroundColor: const Color(0xFF1A0A2E),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final title    = widget.offer['title']    as String? ?? 'Exclusive Offer';
    final brand    = widget.offer['brand']    as String? ?? '';
    final codesLeft = (widget.offer['codesPool'] as List?)?.length ?? 0;

    final alreadyClaimed = _claimedCode != null;
    final canClaim = widget.eligible && !alreadyClaimed && codesLeft > 0;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),

            // ── Brand avatar + title ─────────────────────────────────
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: widget.typeColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  brand.isNotEmpty ? brand[0].toUpperCase() : '★',
                  style: TextStyle(
                      color: widget.typeColor,
                      fontSize: 28,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay')),
            if (brand.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(brand,
                    style: TextStyle(
                        color: widget.typeColor.withValues(alpha: 0.80),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 6),
            // Value pill
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: widget.typeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: widget.typeColor.withValues(alpha: 0.40)),
              ),
              child: Text(widget.typeDisplay,
                  style: TextStyle(
                      color: widget.typeColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ),

            const SizedBox(height: 24),
            const Divider(color: Colors.white10),
            const SizedBox(height: 20),

            // ── Eligibility status ───────────────────────────────────
            if (alreadyClaimed) ...[
              const Text('Your Code',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _copyCode,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                            const Color(0xFF22C55E).withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.confirmation_number_rounded,
                          color: Color(0xFF22C55E), size: 20),
                      const SizedBox(width: 10),
                      Text(_claimedCode!,
                          style: const TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 20,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.0)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _copyCode,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color:
                            const Color(0xFF22C55E).withValues(alpha: 0.40)),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.copy_rounded,
                          color: Color(0xFF22C55E), size: 16),
                      SizedBox(width: 8),
                      Text('Copy Code',
                          style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Score requirement card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.eligible
                          ? Icons.verified_rounded
                          : Icons.lock_outline_rounded,
                      color: widget.eligible
                          ? const Color(0xFF22C55E)
                          : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: widget.eligible
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('You qualify!',
                                    style: TextStyle(
                                        color: Color(0xFF22C55E),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                                Text(
                                    'Your best: ${widget.bestScore} '
                                    '(required: ${widget.minScore}+)',
                                    style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11)),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Score ${widget.minScore}+ to unlock',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    'Your best: ${widget.bestScore} — '
                                    '${widget.minScore - widget.bestScore} more to go',
                                    style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11)),
                              ],
                            ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (canClaim)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _claiming ? null : _claim,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.06),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    child: _claiming
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.lock_open_rounded,
                                  size: 18),
                              const SizedBox(width: 8),
                              const Text('Claim Code'),
                              const SizedBox(width: 8),
                              Text('($codesLeft left)',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white70)),
                            ],
                          ),
                  ),
                )
              else if (!widget.eligible)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFF7B2CBF).withValues(alpha: 0.25),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      textStyle: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('Keep Practising'),
                  ),
                ),

              if (codesLeft == 0 && !widget.eligible)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'All codes claimed',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.red.shade400, fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
