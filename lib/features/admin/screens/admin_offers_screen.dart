import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'offer_inventory_screen.dart';

// ── Data model helpers ────────────────────────────────────────────────────────

enum _OfferType { percent, fixed, freebie }

extension _OfferTypeExt on _OfferType {
  String get label => switch (this) {
    _OfferType.percent  => '% Discount',
    _OfferType.fixed    => 'Flat Amount',
    _OfferType.freebie  => 'Freebie',
  };
  String get key => switch (this) {
    _OfferType.percent  => 'percent',
    _OfferType.fixed    => 'fixed',
    _OfferType.freebie  => 'freebie',
  };
  Color get color => switch (this) {
    _OfferType.percent  => const Color(0xFF06B6D4),
    _OfferType.fixed    => const Color(0xFF22C55E),
    _OfferType.freebie  => const Color(0xFFD4A8FF),
  };
  static _OfferType fromKey(String? k) => switch (k) {
    'percent'  => _OfferType.percent,
    'fixed'    => _OfferType.fixed,
    _          => _OfferType.freebie,
  };
}

// ── Main screen ───────────────────────────────────────────────────────────────

class AdminOffersScreen extends StatelessWidget {
  const AdminOffersScreen({super.key});

  static const _bg     = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Offer',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('offers')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF7B2CBF)));
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return _emptyState();
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d  = docs[i].data() as Map<String, dynamic>;
              final id = docs[i].id;
              return _OfferCard(id: id, data: d);
            },
          );
        },
      ),
    );
  }

  static Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_offer_outlined,
                color: Colors.white24, size: 52),
            const SizedBox(height: 12),
            const Text('No offers yet',
                style: TextStyle(color: Colors.white38, fontSize: 15)),
            const SizedBox(height: 4),
            const Text('Tap + to create the first coupon batch',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );

  static void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _CreateOfferSheet(),
    );
  }
}

// ── Offer card ────────────────────────────────────────────────────────────────

class _OfferCard extends StatelessWidget {
  final String                id;
  final Map<String, dynamic>  data;

  const _OfferCard({required this.id, required this.data});

  static const _accent = Color(0xFF7B2CBF);

  @override
  Widget build(BuildContext context) {
    final title       = data['title']       as String? ?? 'Offer';
    final brand       = data['brand']       as String? ?? '';
    final description = data['description'] as String? ?? '';
    final type        = _OfferTypeExt.fromKey(data['type'] as String?);
    final value       = (data['value'] as num?)?.toInt() ?? 0;
    final totalCodes  = (data['totalCodes']  as num?)?.toInt() ?? 0;
    final codesPool   = (data['codesPool']   as List?)?.length ?? 0;
    final status      = data['status'] as String? ?? 'active';
    final expiresAt   = data['expiresAt'] as Timestamp?;

    final remaining    = codesPool;
    final progress     = totalCodes > 0 ? remaining / totalCodes : 0.0;
    final isPaused     = status == 'paused';
    final isExpired    = status == 'expired' ||
        (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now()));

    Color statusColor;
    String statusLabel;
    if (isExpired) {
      statusColor = Colors.red.shade400;
      statusLabel = 'EXPIRED';
    } else if (isPaused) {
      statusColor = Colors.amber;
      statusLabel = 'PAUSED';
    } else {
      statusColor = const Color(0xFF22C55E);
      statusLabel = 'ACTIVE';
    }

    String typeDisplay = switch (type) {
      _OfferType.percent  => '$value% off',
      _OfferType.fixed    => '₹$value off',
      _OfferType.freebie  => 'Free gift',
    };

    String? expiryLabel;
    Color expiryColor = Colors.white38;
    if (expiresAt != null) {
      final daysLeft = expiresAt.toDate().difference(DateTime.now()).inDays;
      if (daysLeft < 0) {
        expiryLabel = 'Expired';
        expiryColor = Colors.red.shade400;
      } else if (daysLeft == 0) {
        expiryLabel = 'Expires today';
        expiryColor = Colors.red.shade400;
      } else if (daysLeft <= 7) {
        expiryLabel = '$daysLeft day${daysLeft == 1 ? '' : 's'} left';
        expiryColor = Colors.amber;
      } else {
        final d = expiresAt.toDate();
        expiryLabel = '${d.day}/${d.month}/${d.year}';
        expiryColor = Colors.white38;
      }
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => OfferInventoryScreen(offerId: id)),
      ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF100A20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpired
              ? Colors.red.withValues(alpha: 0.20)
              : isPaused
                  ? Colors.amber.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Type icon
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: type.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  type == _OfferType.percent
                      ? Icons.percent_rounded
                      : type == _OfferType.fixed
                          ? Icons.currency_rupee_rounded
                          : Icons.card_giftcard_rounded,
                  color: type.color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (brand.isNotEmpty) ...[
                          Text(brand,
                              style: TextStyle(
                                  color: type.color.withValues(alpha: 0.80),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const Text('  ·  ',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 11)),
                        ],
                        Text(typeDisplay,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: statusColor.withValues(alpha: 0.40)),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white38, fontSize: 12, height: 1.4)),
          ],

          const SizedBox(height: 14),

          // ── Codes progress ────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Codes remaining',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11)),
              Text('$remaining / $totalCodes',
                  style: TextStyle(
                      color: remaining == 0
                          ? Colors.red.shade400
                          : Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOut,
              builder: (_, v, __) => LinearProgressIndicator(
                value: v,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor: AlwaysStoppedAnimation<Color>(
                  remaining == 0
                      ? Colors.red.shade400
                      : remaining < totalCodes * 0.2
                          ? Colors.amber
                          : _accent,
                ),
                minHeight: 5,
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Footer row ────────────────────────────────────────────────
          Row(
            children: [
              if (expiryLabel != null) ...[
                Icon(Icons.schedule_rounded, color: expiryColor, size: 12),
                const SizedBox(width: 4),
                Text(expiryLabel,
                    style: TextStyle(
                        color: expiryColor, fontSize: 11)),
              ],
              const Spacer(),
              // Add codes
              _ActionBtn(
                icon: Icons.add_rounded,
                label: 'Add Codes',
                color: Colors.white38,
                onTap: () => _showAddCodesSheet(context),
              ),
              const SizedBox(width: 8),
              // Pause / Resume
              if (!isExpired)
                _ActionBtn(
                  icon: isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: isPaused ? 'Resume' : 'Pause',
                  color: isPaused ? const Color(0xFF22C55E) : Colors.amber,
                  onTap: () => _toggleStatus(isPaused),
                ),
            ],
          ),
        ],
      ),
      ), // GestureDetector
    );
  }

  Future<void> _toggleStatus(bool currentlyPaused) async {
    await FirebaseFirestore.instance
        .collection('offers')
        .doc(id)
        .update({'status': currentlyPaused ? 'active' : 'paused'});
  }

  void _showAddCodesSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _AddCodesSheet(offerId: id),
    );
  }
}

// ── Action button helper ──────────────────────────────────────────────────────

class _ActionBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 12),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

// ── Create offer sheet ────────────────────────────────────────────────────────

class _CreateOfferSheet extends StatefulWidget {
  const _CreateOfferSheet();

  @override
  State<_CreateOfferSheet> createState() => _CreateOfferSheetState();
}

class _CreateOfferSheetState extends State<_CreateOfferSheet> {
  static const _accent = Color(0xFF7B2CBF);

  final _titleCtrl  = TextEditingController();
  final _brandCtrl  = TextEditingController();
  final _descCtrl   = TextEditingController();
  final _valueCtrl  = TextEditingController(text: '0');
  final _codesCtrl  = TextEditingController();

  _OfferType _type       = _OfferType.percent;
  DateTime?  _expiresAt;
  bool       _saving     = false;
  bool       _advanced   = false;

  // Advanced
  final _challengeCtrl = TextEditingController();
  final _minAuraCtrl   = TextEditingController(text: '0');

  @override
  void dispose() {
    _titleCtrl.dispose();
    _brandCtrl.dispose();
    _descCtrl.dispose();
    _valueCtrl.dispose();
    _codesCtrl.dispose();
    _challengeCtrl.dispose();
    _minAuraCtrl.dispose();
    super.dispose();
  }

  List<String> get _parsedCodes => _codesCtrl.text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
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
    if (picked != null) setState(() => _expiresAt = picked);
  }

  Future<void> _save() async {
    final title  = _titleCtrl.text.trim();
    final brand  = _brandCtrl.text.trim();
    final codes  = _parsedCodes;

    if (title.isEmpty) { _snack('Title required', error: true); return; }
    if (brand.isEmpty) { _snack('Brand required', error: true); return; }
    if (codes.isEmpty) { _snack('Paste at least one code', error: true); return; }
    if (_expiresAt == null) { _snack('Set an expiry date', error: true); return; }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('users').doc(uid).get();
    if (userDoc.data()?['isAdmin'] != true) {
      _snack('Admin access required', error: true);
      return;
    }

    final value = int.tryParse(_valueCtrl.text.trim()) ?? 0;

    setState(() => _saving = true);
    try {
      final doc = <String, dynamic>{
        'title':       title,
        'brand':       brand,
        'description': _descCtrl.text.trim(),
        'type':        _type.key,
        'value':       value,
        'status':      'active',
        'codesPool':   codes,
        'totalCodes':  codes.length,
        'expiresAt':   Timestamp.fromDate(_expiresAt!),
        'createdAt':   Timestamp.now(),
        'createdBy':   uid,
      };

      // Advanced fields
      final challengeId  = _challengeCtrl.text.trim();
      final minAura      = int.tryParse(_minAuraCtrl.text.trim()) ?? 0;
      if (challengeId.isNotEmpty) doc['challengeId'] = challengeId;
      if (minAura > 0)            doc['minAuraScore'] = minAura;

      await FirebaseFirestore.instance.collection('offers').add(doc);
      if (!mounted) return;
      _snack('Offer created with ${codes.length} codes');
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
            // Handle
            Center(
              child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 18),

            const Text('Create Offer',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay')),
            const SizedBox(height: 20),

            // ── Type selector ────────────────────────────────────────
            Row(
              children: _OfferType.values.map((t) {
                final sel = _type == t;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _type = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: EdgeInsets.only(
                          right: t != _OfferType.freebie ? 8 : 0),
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
                      child: Text(t.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: sel ? t.color : Colors.white24,
                              fontSize: 11,
                              fontWeight:
                                  sel ? FontWeight.w700 : FontWeight.w400)),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 18),

            // ── Title + Brand ────────────────────────────────────────
            _label('Offer Title'),
            const SizedBox(height: 6),
            _field(_titleCtrl, 'e.g. 20% off Premium Membership'),
            const SizedBox(height: 14),

            _label('Brand Name'),
            const SizedBox(height: 6),
            _field(_brandCtrl, 'e.g. Nike, Zomato, Amazon'),
            const SizedBox(height: 14),

            _label('Description (optional)'),
            const SizedBox(height: 6),
            _field(_descCtrl, 'Short description visible to users…',
                maxLines: 2),
            const SizedBox(height: 14),

            // ── Value ────────────────────────────────────────────────
            if (_type != _OfferType.freebie) ...[
              _label(_type == _OfferType.percent
                  ? 'Discount Percentage'
                  : 'Flat Amount (₹)'),
              const SizedBox(height: 6),
              _field(_valueCtrl,
                  _type == _OfferType.percent ? 'e.g. 20' : 'e.g. 500',
                  keyboardType: TextInputType.number),
              const SizedBox(height: 14),
            ],

            // ── Codes ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _label('Coupon Codes'),
                ValueListenableBuilder(
                  valueListenable: _codesCtrl,
                  builder: (_, __, ___) {
                    final n = _parsedCodes.length;
                    return Text('$n code${n == 1 ? '' : 's'}',
                        style: TextStyle(
                            color: n > 0
                                ? const Color(0xFF22C55E)
                                : Colors.white24,
                            fontSize: 11,
                            fontWeight: FontWeight.w600));
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _codesCtrl,
              maxLines:   7,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'monospace'),
              decoration: _decor('Paste codes here — one per line:\nNIKE123\nNIKE456\n…'),
            ),

            const SizedBox(height: 14),

            // ── Expiry ───────────────────────────────────────────────
            _label('Expiry Date'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickExpiry,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_rounded,
                        color: _expiresAt != null
                            ? const Color(0xFFD4A8FF)
                            : Colors.white24,
                        size: 16),
                    const SizedBox(width: 10),
                    Text(
                      _expiresAt != null
                          ? '${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}'
                          : 'Pick expiry date',
                      style: TextStyle(
                          color: _expiresAt != null
                              ? Colors.white
                              : Colors.white38,
                          fontSize: 14),
                    ),
                    const Spacer(),
                    if (_expiresAt != null)
                      GestureDetector(
                        onTap: () => setState(() => _expiresAt = null),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 16),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Advanced toggle ──────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _advanced = !_advanced),
              child: Row(
                children: [
                  const Text('Advanced',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Icon(
                    _advanced
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38,
                    size: 18),
                ],
              ),
            ),

            if (_advanced) ...[
              const SizedBox(height: 14),
              _label('Challenge ID (optional)'),
              const SizedBox(height: 6),
              _field(_challengeCtrl,
                  'Link to a challenge doc ID — enables offer unlock (#27)'),
              const SizedBox(height: 14),
              _label('Min Aura Score to Unlock'),
              const SizedBox(height: 6),
              _field(_minAuraCtrl, 'e.g. 75',
                  keyboardType: TextInputType.number),
            ],

            const SizedBox(height: 28),

            // ── Save ─────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  disabledBackgroundColor:
                      Colors.white.withValues(alpha: 0.06),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Create Offer'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700));

  Widget _field(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) =>
      TextField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: _decor(hint),
      );

  InputDecoration _decor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
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
            borderSide: const BorderSide(
                color: Color(0xFF7B2CBF), width: 1.5)),
      );
}

// ── Add codes sheet ───────────────────────────────────────────────────────────

class _AddCodesSheet extends StatefulWidget {
  final String offerId;
  const _AddCodesSheet({required this.offerId});

  @override
  State<_AddCodesSheet> createState() => _AddCodesSheetState();
}

class _AddCodesSheetState extends State<_AddCodesSheet> {
  static const _accent = Color(0xFF7B2CBF);
  final _codesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _codesCtrl.dispose();
    super.dispose();
  }

  List<String> get _parsedCodes => _codesCtrl.text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _save() async {
    final codes = _parsedCodes;
    if (codes.isEmpty) {
      _snack('Paste at least one code', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final db  = FirebaseFirestore.instance;
      final ref = db.collection('offers').doc(widget.offerId);
      await db.runTransaction((txn) async {
        final snap = await txn.get(ref);
        final existing =
            List<String>.from((snap.data()?['codesPool'] as List?) ?? []);
        final prev  = (snap.data()?['totalCodes'] as num?)?.toInt() ?? existing.length;
        final merged = {...existing, ...codes}.toList();
        txn.update(ref, {
          'codesPool':  merged,
          'totalCodes': prev + codes.length,
        });
      });
      if (!mounted) return;
      _snack('Added ${codes.length} codes');
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
      child: Padding(
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
            const Text('Add Coupon Codes',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'ClashDisplay')),
            const SizedBox(height: 6),
            const Text('Paste new codes — one per line. Duplicates are ignored.',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 16),
            ValueListenableBuilder(
              valueListenable: _codesCtrl,
              builder: (_, __, ___) {
                final n = _parsedCodes.length;
                return TextField(
                  controller: _codesCtrl,
                  maxLines:   8,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText:  'CODE001\nCODE002\n…',
                    hintStyle: const TextStyle(
                        color: Colors.white24, fontSize: 12),
                    filled:    true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    contentPadding: const EdgeInsets.all(14),
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
                        borderSide: const BorderSide(
                            color: _accent, width: 1.5)),
                    suffixText: n > 0 ? '$n codes' : null,
                    suffixStyle: const TextStyle(
                        color: Color(0xFF22C55E),
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
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
                    : const Text('Add Codes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
