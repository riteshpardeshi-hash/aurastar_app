import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuraSubmittedPopup extends StatefulWidget {
  final String submissionId;
  const AuraSubmittedPopup({super.key, required this.submissionId});

  @override
  State<AuraSubmittedPopup> createState() => _AuraSubmittedPopupState();
}

class _AuraSubmittedPopupState extends State<AuraSubmittedPopup>
    with TickerProviderStateMixin {
  String? _resultStatus;
  int _netAurasAwarded = 0;
  bool _isCountedForDailyAuras = false;
  String _aiReason = '';
  bool _timedOut = false;
  Timer? _timeoutTimer;
  StreamSubscription<DocumentSnapshot>? _sub;

  late AnimationController _enterCtrl;
  late AnimationController _scanCtrl;
  late AnimationController _radarCtrl;
  late AnimationController _dotsCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _resultEnterCtrl;
  late AnimationController _countCtrl;
  late AnimationController _particleCtrl;

  late Animation<double> _enterScale;
  late Animation<double> _enterFade;
  late Animation<double> _scanPos;
  late Animation<double> _pulseAnim;
  late Animation<double> _resultScale;
  late Animation<double> _resultFade;
  late Animation<double> _countAnim;

  @override
  void initState() {
    super.initState();

    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scanCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _radarCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _dotsCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _resultEnterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _countCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _particleCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));

    _enterScale = CurvedAnimation(parent: _enterCtrl, curve: Curves.elasticOut);
    _enterFade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeIn);
    _scanPos = CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _resultScale = CurvedAnimation(parent: _resultEnterCtrl, curve: Curves.elasticOut);
    _resultFade = CurvedAnimation(parent: _resultEnterCtrl, curve: Curves.easeIn);
    _countAnim = CurvedAnimation(parent: _countCtrl, curve: Curves.easeOut);

    _enterCtrl.forward();

    _timeoutTimer = Timer(const Duration(seconds: 90), () {
      if (mounted && _resultStatus == null) setState(() => _timedOut = true);
    });

    _sub = FirebaseFirestore.instance
        .collection('submissions')
        .doc(widget.submissionId)
        .snapshots()
        .listen((snap) {
      if (!mounted || _resultStatus != null) return;
      final data = snap.data();
      if (data == null) return;
      final status = data['status'] as String? ?? 'pending';
      if (status == 'approved' || status == 'rejected' || status == 'ai_error') {
        final pts = (data['auraPoints'] as num?)?.toInt() ?? 0;
        final netAwarded = (data['netAurasAwarded'] as num?)?.toInt() ?? pts;
        final counted = data['isCountedForDailyAuras'] as bool? ?? false;
        final reason = data['aiReason'] as String? ?? '';
        _timeoutTimer?.cancel();
        setState(() {
          _resultStatus = status;
          _netAurasAwarded = netAwarded;
          _isCountedForDailyAuras = counted;
          _aiReason = reason;
        });
        _resultEnterCtrl.forward();
        if (status == 'approved') {
          _countCtrl.forward();
          _particleCtrl.forward();
        }
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeoutTimer?.cancel();
    _enterCtrl.dispose();
    _scanCtrl.dispose();
    _radarCtrl.dispose();
    _dotsCtrl.dispose();
    _pulseCtrl.dispose();
    _resultEnterCtrl.dispose();
    _countCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  List<Widget> _buildParticles() {
    const particles = <List<double>>[
      [18.0, 60.0, 14.0],
      [255.0, 45.0, 10.0],
      [4.0, 160.0, 12.0],
      [268.0, 170.0, 9.0],
      [95.0, 12.0, 16.0],
      [182.0, 18.0, 10.0],
      [145.0, 350.0, 12.0],
      [48.0, 320.0, 8.0],
      [238.0, 305.0, 14.0],
      [125.0, 370.0, 10.0],
      [28.0, 260.0, 8.0],
      [262.0, 230.0, 11.0],
    ];
    return particles.asMap().entries.map((entry) {
      final idx = entry.key;
      final p = entry.value;
      return AnimatedBuilder(
        animation: _particleCtrl,
        builder: (_, __) {
          final stagger = (idx * 0.07).clamp(0.0, 0.55);
          final localT = ((_particleCtrl.value - stagger) / (1 - stagger)).clamp(0.0, 1.0);
          final opacity = localT < 0.25
              ? localT / 0.25
              : localT > 0.65
                  ? (1 - localT) / 0.35
                  : 1.0;
          final dy = p[1] - localT * 90;
          return Positioned(
            left: p[0],
            top: dy,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Text(
                idx % 3 == 0 ? '✦' : idx % 3 == 1 ? '★' : '✸',
                style: TextStyle(
                  color: idx % 2 == 0 ? const Color(0xFFD4A8FF) : const Color(0xFFFFD700),
                  fontSize: p[2],
                ),
              ),
            ),
          );
        },
      );
    }).toList();
  }

  Widget _buildReviewingPhase() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 150,
          height: 150,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ...List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _radarCtrl,
                  builder: (_, __) {
                    final t = (_radarCtrl.value + i / 3.0) % 1.0;
                    final scale = 0.35 + t * 0.65;
                    final opacity = (1 - t).clamp(0.0, 1.0);
                    return Opacity(
                      opacity: opacity,
                      child: Container(
                        width: 140 * scale,
                        height: 140 * scale,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF9B4DCA), width: 1.5),
                        ),
                      ),
                    );
                  },
                );
              }),
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(colors: [Color(0xFFBB66FF), Color(0xFF4A1080)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF7B2CBF).withValues(alpha: 0.85), blurRadius: 22, spreadRadius: 4)],
                  ),
                  child: ClipOval(
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Image.asset('assets/images/aura star logo.png'),
                        ),
                        AnimatedBuilder(
                          animation: _scanPos,
                          builder: (_, __) {
                            return Positioned(
                              top: _scanPos.value * 96,
                              left: 0,
                              right: 0,
                              child: Container(
                                height: 2.5,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.transparent, Color(0xFFCC77FF), Colors.transparent],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'AI is reviewing\nyour video...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, height: 1.35),
        ),
        const SizedBox(height: 14),
        if (!_timedOut)
          AnimatedBuilder(
            animation: _dotsCtrl,
            builder: (_, __) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final t = (_dotsCtrl.value + i * 0.33) % 1.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Transform.scale(
                      scale: 0.5 + t * 0.5,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(const Color(0xFF7B2CBF), const Color(0xFFD4A8FF), t),
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          )
        else ...[
          const Text('Taking longer than usual...', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF7B2CBF).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF9B4DCA).withValues(alpha: 0.5)),
              ),
              child: const Text('Check My Account later', style: TextStyle(color: Color(0xFFD4A8FF), fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildResultPhase() {
    return ScaleTransition(
      scale: _resultScale,
      child: FadeTransition(
        opacity: _resultFade,
        child: _resultStatus == 'approved'
            ? _buildApprovedContent()
            : _resultStatus == 'rejected'
                ? _buildRejectedContent()
                : _buildErrorContent(),
      ),
    );
  }

  Widget _buildApprovedContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFE066), Color(0xFFFF9500)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: const Color(0xFFFFD700).withValues(alpha: 0.65), blurRadius: 28, spreadRadius: 6),
            ],
          ),
          child: const Icon(Icons.star_rounded, color: Colors.white, size: 58),
        ),
        const SizedBox(height: 14),
        const Text('Video Approved!', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: _countAnim,
          builder: (_, __) {
            final displayed = (_netAurasAwarded * _countAnim.value).round();
            return Text(
              '+$displayed',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 60,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            );
          },
        ),
        const Text(
          'AURA POINTS',
          style: TextStyle(color: Color(0xFFD4A8FF), fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 2.5),
        ),
        if (_aiReason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              _aiReason,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _isCountedForDailyAuras
                ? Colors.greenAccent.withValues(alpha: 0.12)
                : Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _isCountedForDailyAuras
                  ? Colors.greenAccent.withValues(alpha: 0.35)
                  : Colors.orange.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            _isCountedForDailyAuras
                ? '✓  Counted in your top scores today'
                : "Flex score — didn't enter your top scores today",
            style: TextStyle(
              color: _isCountedForDailyAuras ? Colors.greenAccent : Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A1000),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.6), width: 2),
            boxShadow: [BoxShadow(color: Colors.orange.withValues(alpha: 0.25), blurRadius: 24, spreadRadius: 4)],
          ),
          child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 52),
        ),
        const SizedBox(height: 18),
        const Text('Review Unavailable', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'AI couldn\'t process your video right now. Check My Account — an admin will review it shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: const Text('OK', style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _buildRejectedContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF1A0000),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6), width: 2),
            boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.3), blurRadius: 24, spreadRadius: 4)],
          ),
          child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 56),
        ),
        const SizedBox(height: 18),
        const Text('Video Rejected', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _aiReason.isNotEmpty ? _aiReason : 'This video didn\'t meet the challenge criteria.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 14, height: 1.4),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
          ),
          child: const Text(
            'Try again with a better video',
            style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(true),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {},
          child: FadeTransition(
            opacity: _enterFade,
            child: ScaleTransition(
              scale: _enterScale,
              child: Material(
                color: Colors.transparent,
                child: SizedBox(
                  width: 300,
                  height: 410,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 300,
                        height: 410,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0D0020), Color(0xFF3D1277), Color(0xFF150030)],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          border: Border.all(color: const Color(0xFF9B4DCA), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7B2CBF).withValues(alpha: 0.7),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          switchInCurve: Curves.easeIn,
                          switchOutCurve: Curves.easeOut,
                          child: _resultStatus != null
                              ? _buildResultPhase()
                              : _buildReviewingPhase(),
                        ),
                      ),
                      if (_resultStatus == 'approved') ..._buildParticles(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
