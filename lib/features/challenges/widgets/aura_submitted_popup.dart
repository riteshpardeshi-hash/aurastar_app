import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/challenges_service.dart';
import '../../../core/services/auth_api_service.dart';
import 'achievement_card.dart';

class AuraSubmittedPopup extends StatefulWidget {
  final String submissionId;
  final String challengeTitle;
  final String challengeId;
  final Map<String, dynamic>? initialResult;

  const AuraSubmittedPopup({
    super.key,
    required this.submissionId,
    required this.challengeTitle,
    required this.challengeId,
    this.initialResult,
  });

  @override
  State<AuraSubmittedPopup> createState() => _AuraSubmittedPopupState();
}

const List<String> _kAuraSenseTrivia = [
  'When did the first modern fashion runway happen?',
  'The word "aura" comes from the Greek word for breeze.',
  'Confidence is the one accessory that never goes out of style.',
  'The first color photograph was taken in 1861.',
  'Your first impression forms in less than a second.',
  'Vintage denim can take up to a year to fade naturally.',
  'The catwalk got its name from a narrow backstage walkway.',
];

class _AuraSubmittedPopupState extends State<AuraSubmittedPopup>
    with TickerProviderStateMixin {
  String? _resultStatus;
  int _netAurasAwarded = 0;
  int _aiScore = 0;
  bool _isBestForChallenge = false;
  String _aiReason = '';
  String _approvedView = 'summary'; // 'summary' | 'explanation' | 'card'
  bool _timedOut = false;
  Timer? _timeoutTimer;
  Timer? _pollTimer;
  Timer? _triviaTimer;
  int _triviaIndex = 0;

  String _username = '';
  String _city = '';
  int? _cityRank;
  bool _isSharingCard = false;
  bool _isInstagramSharing = false;
  final _cardKey = GlobalKey();

  late AnimationController _enterCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _resultEnterCtrl;
  late AnimationController _countCtrl;
  late AnimationController _explanationCtrl;
  late AnimationController _percentCtrl;

  late Animation<double> _enterScale;
  late Animation<double> _enterFade;
  late Animation<double> _pulseAnim;
  late Animation<double> _resultScale;
  late Animation<double> _resultFade;
  late Animation<double> _explanationFade;
  late Animation<Offset> _explanationSlide;
  late Animation<double> _percentAnim;

  @override
  void initState() {
    super.initState();

    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _resultEnterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _countCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
    _explanationCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _percentCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 14));

    _enterScale = CurvedAnimation(parent: _enterCtrl, curve: Curves.elasticOut);
    _enterFade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeIn);
    _pulseAnim = Tween<double>(begin: 0.93, end: 1.07).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _resultScale = CurvedAnimation(parent: _resultEnterCtrl, curve: Curves.elasticOut);
    _resultFade = CurvedAnimation(parent: _resultEnterCtrl, curve: Curves.easeIn);
    _explanationFade = CurvedAnimation(parent: _explanationCtrl, curve: Curves.easeIn);
    _explanationSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _explanationCtrl, curve: Curves.easeOutCubic));
    _percentAnim = Tween<double>(begin: 0, end: 92)
        .animate(CurvedAnimation(parent: _percentCtrl, curve: Curves.easeOutCubic));

    _enterCtrl.forward();
    _percentCtrl.forward();
    _triviaTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _resultStatus != null) return;
      setState(() => _triviaIndex = (_triviaIndex + 1) % _kAuraSenseTrivia.length);
    });

    if (widget.initialResult != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final data = widget.initialResult!;
        final verdict = data['verdict'] as String? ?? '';
        final rawStatus = data['status'] as String? ?? 'pending';
        // If already scored, apply immediately; otherwise poll
        if (verdict == 'PASS' || verdict == 'FAIL' ||
            rawStatus == 'approved' || rawStatus == 'rejected' || rawStatus == 'ai_error') {
          _applyResult(data);
        } else {
          _startPolling();
        }
      });
      return;
    }

    _timeoutTimer = Timer(const Duration(seconds: 90), () {
      if (mounted && _resultStatus == null) setState(() => _timedOut = true);
    });

    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_resultStatus != null || !mounted) {
        _pollTimer?.cancel();
        return;
      }
      try {
        final data = await ChallengesService().fetchMySubmission(widget.challengeId);
        if (data == null || !mounted || _resultStatus != null) return;
        final verdict = data['verdict'] as String? ?? '';
        final rawStatus = data['status'] as String? ?? 'pending';
        if (verdict == 'PASS' || verdict == 'FAIL' ||
            rawStatus == 'approved' || rawStatus == 'rejected' || rawStatus == 'ai_error') {
          _pollTimer?.cancel();
          _applyResult(data);
        }
      } catch (_) {}
    });
  }

  void _applyResult(Map<String, dynamic> data) {
    if (!mounted || _resultStatus != null) return;
    final verdict = data['verdict'] as String? ?? '';
    final rawStatus = data['status'] as String? ?? '';
    final String status;
    if (verdict == 'PASS' || rawStatus == 'approved') {
      status = 'approved';
    } else if (verdict == 'FAIL' || rawStatus == 'rejected') {
      status = 'rejected';
    } else {
      status = 'ai_error';
    }
    final pts = (data['auraPoints'] as num?)?.toInt() ?? 0;
    final netAwarded = (data['netAurasAwarded'] as num?)?.toInt() ?? pts;
    final score = (data['aiScore'] as num?)?.toInt() ?? 0;
    final isBest = data['isBestForChallenge'] as bool? ?? false;
    final reason = data['aiReason'] as String? ?? '';
    final uname = data['username'] as String? ?? '';
    _timeoutTimer?.cancel();
    setState(() {
      _resultStatus = status;
      _netAurasAwarded = netAwarded;
      _aiScore = score;
      _isBestForChallenge = isBest;
      _aiReason = reason;
      if (uname.isNotEmpty) _username = uname;
      _approvedView = 'summary';
    });
    _resultEnterCtrl.forward();
    if (status == 'approved') {
      _countCtrl.forward();
      _explanationCtrl.forward();
      _fetchUserInfoForCard();
    } else if (status == 'ai_error') {
      Future.delayed(const Duration(seconds: 8), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  Future<void> _fetchUserInfoForCard() async {
    try {
      final profile = await AuthApiService().getProfile();
      if (!mounted || profile == null) return;
      final city =
          (profile['city'] as Map<String, dynamic>?)?['name'] as String? ??
              '';
      final name = profile['displayName'] as String? ??
          profile['profileName'] as String? ??
          profile['username'] as String? ?? '';
      setState(() {
        if (city.isNotEmpty) _city = city;
        if (name.isNotEmpty) _username = name;
      });
    } catch (_) {}
  }

  Future<void> _shareCard() async {
    if (_isSharingCard) return;
    setState(() => _isSharingCard = true);

    try {
      Uint8List? bytes;
      final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = byteData?.buffer.asUint8List();
      }

      final challengeLink = '$kChallengeBaseUrl/${widget.challengeId}';
      final message =
          'I just completed "${widget.challengeTitle}" on Aura and earned $_netAurasAwarded Aura Points! 🏆\n\n'
          'Think you can beat me? Now it\'s your turn! 💪\n\n'
          '👉 Join the challenge:\n$challengeLink';

      if (bytes != null) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'image/png', name: 'aura_achievement.png')],
          text: message,
        );
      } else {
        await Share.share(message);
      }
    } catch (_) {
      // share cancelled or failed — ignore
    } finally {
      if (mounted) setState(() => _isSharingCard = false);
    }
  }

  Future<void> _shareToInstagramStory() async {
    if (_isInstagramSharing) return;
    setState(() => _isInstagramSharing = true);
    try {
      Uint8List? bytes;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) {
        final image = await boundary.toImage(pixelRatio: 3.0);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.png);
        bytes = byteData?.buffer.asUint8List();
      }
      if (bytes != null) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, mimeType: 'image/png', name: 'aura_story.png')],
        );
      }
    } catch (_) {
      // share cancelled or failed — ignore
    } finally {
      if (mounted) setState(() => _isInstagramSharing = false);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _timeoutTimer?.cancel();
    _triviaTimer?.cancel();
    _enterCtrl.dispose();
    _pulseCtrl.dispose();
    _resultEnterCtrl.dispose();
    _countCtrl.dispose();
    _explanationCtrl.dispose();
    _percentCtrl.dispose();
    super.dispose();
  }

  // ── Reviewing phase: full-screen "Aura Sense" analysing experience ──────────

  Widget _buildAuraSenseScreen() {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ScaleTransition(
            scale: _pulseAnim,
            child: Image.asset(
              'assets/images/analysing/Asset 132.png',
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _enterFade,
                    child: Image.asset('assets/images/analysing/Asset 133.png', height: 32),
                  ),
                  const Spacer(flex: 5),
                  AnimatedBuilder(
                    animation: _percentAnim,
                    builder: (_, __) {
                      final pct = _percentAnim.value.round();
                      return ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.white, Color(0xFFC9A6FF)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ).createShader(bounds),
                        child: Text(
                          '$pct%',
                          style: const TextStyle(
                            fontFamily: 'ClashDisplay',
                            color: Colors.white,
                            fontSize: 64,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Image.asset('assets/images/analysing/Asset 135.png', height: 16),
                  const SizedBox(height: 18),
                  Image.asset('assets/images/analysing/Asset 136.png', height: 60),
                  const Spacer(flex: 6),
                  if (!_timedOut) ...[
                    Image.asset('assets/images/analysing/Asset 137.png', height: 22),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _kAuraSenseTrivia[_triviaIndex],
                        key: ValueKey(_triviaIndex),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ] else ...[
                    const Text('Taking longer than usual...',
                        style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            decoration: TextDecoration.none)),
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
                        child: const Text('Check My Account later',
                            style: TextStyle(
                                color: Color(0xFFD4A8FF),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Result phase ──────────────────────────────────────────────────────────────

  Widget _buildResultPhase() {
    return ScaleTransition(
      scale: _resultScale,
      child: FadeTransition(
        opacity: _resultFade,
        child: _buildErrorContent(),
      ),
    );
  }

  // ── Approved: full-screen "Aura Sense" earned experience ─────────────────────

  Widget _buildAuraSenseApprovedScreen() {
    final isSummary = _approvedView == 'summary';
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          isSummary
              ? ScaleTransition(
                  scale: _pulseAnim,
                  child: Image.asset(
                    'assets/images/aura earned/Asset 139.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                )
              : Opacity(
                  opacity: 0.55,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/images/aura earned/Asset 139.png',
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                      ),
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              Image.asset('assets/images/aura earned/Asset 140.png', height: 32),
                              const Spacer(),
                              Image.asset('assets/images/aura earned/Asset 144.png', height: 24),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          if (!isSummary) Container(color: Colors.black.withValues(alpha: 0.35)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                child: isSummary
                    ? _buildAuraEarnedSummary()
                    : Column(
                        key: ValueKey(_approvedView),
                        children: [
                          Expanded(
                            child: Center(
                              child: SingleChildScrollView(
                                child: Container(
                                  constraints: const BoxConstraints(maxWidth: 320),
                                  padding: const EdgeInsets.all(16),
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
                                  child: _approvedView == 'explanation' ? _buildExplanationView() : _buildCardView(),
                                ),
                              ),
                            ),
                          ),
                          if (_approvedView == 'explanation') ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildAuraEarnedIconButton(
                                  'assets/images/aura earned/Asset 146.png',
                                  onTap: () => setState(() => _approvedView = 'card'),
                                ),
                                const SizedBox(width: 20),
                                _buildAuraEarnedIconButton(
                                  'assets/images/aura earned/Asset 147.png',
                                  onTap: () => Navigator.of(context).pop(true),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuraEarnedSummary() {
    return Column(
      key: const ValueKey('summary'),
      children: [
        const SizedBox(height: 12),
        Image.asset('assets/images/aura earned/Asset 140.png', height: 32),
        const Spacer(flex: 4),
        Image.asset('assets/images/aura earned/Asset 141.png', height: 20),
        const SizedBox(height: 10),
        AnimatedBuilder(
          animation: _countCtrl,
          builder: (_, __) {
            final n = (_netAurasAwarded * Curves.easeOutCubic.transform(_countCtrl.value)).round();
            return Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.white, Color(0xFFC9A6FF)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(bounds),
                  child: Text(
                    '+$n',
                    style: const TextStyle(
                      fontFamily: 'ClashDisplay',
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Image.asset('assets/images/aura earned/Asset 143.png', width: 32, height: 32),
              ],
            );
          },
        ),
        const Spacer(flex: 5),
        Image.asset('assets/images/aura earned/Asset 144.png', height: 24),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAuraEarnedIconButton(
              'assets/images/aura earned/Asset 145.png',
              onTap: () => setState(() => _approvedView = 'explanation'),
            ),
            const SizedBox(width: 20),
            _buildAuraEarnedIconButton(
              'assets/images/aura earned/Asset 146.png',
              onTap: () => setState(() => _approvedView = 'card'),
            ),
            const SizedBox(width: 20),
            _buildAuraEarnedIconButton(
              'assets/images/aura earned/Asset 147.png',
              onTap: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildAuraEarnedIconButton(String asset, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Image.asset(asset, width: 56, height: 56),
    );
  }

  // ── Approved: score-breakdown / achievement-card sub-views ──────────────────

  static const _kScoreAnalysisDots = [
    'assets/images/score analysis/Asset 157.png', // green — strength
    'assets/images/score analysis/Asset 158.png', // yellow — area to improve
    'assets/images/score analysis/Asset 159.png', // pink — tip
  ];

  Widget _buildExplanationView() {
    final points = _feedbackSentences();
    return SlideTransition(
      position: _explanationSlide,
      child: FadeTransition(
        opacity: _explanationFade,
        child: Column(
          key: const ValueKey('explanation'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Score Analysis',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.none),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.2))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Transform.rotate(
                    angle: 0.785398,
                    child: Container(width: 8, height: 8, color: const Color(0xFF9B4DCA)),
                  ),
                ),
                Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.2))),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              widget.challengeTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFC978F0),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF9B4DCA).withValues(alpha: 0.6)),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none),
                  children: [
                    const TextSpan(text: 'AI Score : ', style: TextStyle(color: Colors.white)),
                    TextSpan(text: '$_aiScore', style: const TextStyle(color: Color(0xFFFF6EC7), fontWeight: FontWeight.w800)),
                    TextSpan(text: '/100', style: TextStyle(color: Colors.white.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: points.asMap().entries.map((entry) {
                final dot = _kScoreAnalysisDots[entry.key % _kScoreAnalysisDots.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.only(top: 3), child: Image.asset(dot, width: 12, height: 12)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(entry.value,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13.5,
                                height: 1.4,
                                decoration: TextDecoration.none)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardView() {
    return SingleChildScrollView(
      key: const ValueKey('card'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: AchievementCardView(
              challengeTitle: widget.challengeTitle,
              challengeId: widget.challengeId,
              auraPoints: _netAurasAwarded,
              username: _username,
              city: _city.isNotEmpty ? _city : null,
              cityRank: _cityRank,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isBestForChallenge
                  ? Colors.greenAccent.withValues(alpha: 0.12)
                  : Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isBestForChallenge
                    ? Colors.greenAccent.withValues(alpha: 0.35)
                    : Colors.orange.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              _isBestForChallenge
                  ? '✓  Your new best for this challenge'
                  : 'Not your best — archived (deletes in 7 days)',
              style: TextStyle(
                color: _isBestForChallenge ? Colors.greenAccent : Colors.orange,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildShareButton(),
              const SizedBox(width: 10),
              _buildContinueButton(),
            ],
          ),
          const SizedBox(height: 10),
          _buildInstagramStoryButton(),
        ],
      ),
    );
  }

  Widget _buildShareButton() {
    return GestureDetector(
      onTap: _isSharingCard ? null : _shareCard,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7B2CBF), Color(0xFF4B6EF6)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7B2CBF).withValues(alpha: 0.45),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: _isSharingCard
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.share_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Share Card',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white24),
        ),
        child: const Text(
          'Continue',
          style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none),
        ),
      ),
    );
  }

  Widget _buildInstagramStoryButton() {
    return GestureDetector(
      onTap: _isInstagramSharing ? null : _shareToInstagramStory,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: _isInstagramSharing
              ? const LinearGradient(
                  colors: [Color(0xFF4A1070), Color(0xFF1E2050)],
                )
              : const LinearGradient(
                  colors: [Color(0xFF833AB4), Color(0xFFFD1D1D), Color(0xFFFCAF45)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: _isInstagramSharing
            ? const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Share to Instagram Story',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Rejected: full-screen "Aura Sense" card ──────────────────────────────────

  List<String> _feedbackSentences({String fallback = 'No additional feedback for this submission.'}) {
    final raw = _aiReason.trim();
    if (raw.isEmpty) return [fallback];
    final sentences = raw
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return sentences.isEmpty ? [raw] : sentences;
  }

  Widget _buildAuraSenseRejectedScreen() {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.55,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/images/analysing/Asset 132.png', fit: BoxFit.cover, alignment: Alignment.center),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Image.asset('assets/images/analysing/Asset 133.png', height: 32),
                        const Spacer(),
                        Image.asset('assets/images/analysing/Asset 137.png', height: 22),
                        const SizedBox(height: 10),
                        Text(
                          _kAuraSenseTrivia[_triviaIndex],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                              decoration: TextDecoration.none),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.35)),
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _resultFade,
                child: ScaleTransition(
                  scale: _resultScale,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D0018), Color(0xFF1B0433), Color(0xFF0D0018)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        border: Border.all(color: const Color(0xFF7B2CBF).withValues(alpha: 0.7), width: 1.5),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFF7B2CBF).withValues(alpha: 0.35), blurRadius: 30, spreadRadius: 4),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset('assets/images/video rejected/Asset 123.png', width: 84, height: 84),
                          const SizedBox(height: 18),
                          Image.asset('assets/images/video rejected/Asset 124.png', height: 26),
                          const SizedBox(height: 6),
                          Text(
                            widget.challengeTitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFC978F0),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.none),
                          ),
                          const SizedBox(height: 18),
                          Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _feedbackSentences(
                              fallback: 'Your attempt did not meet the challenge requirements.',
                            ).map((reason) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 5),
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFA855F7)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        reason,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13.5,
                                            height: 1.4,
                                            decoration: TextDecoration.none),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(true),
                            child: Image.asset(
                              'assets/images/video rejected/Asset 131.png',
                              width: double.infinity,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── AI error ──────────────────────────────────────────────────────────────────

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
        const Text('Review Unavailable',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.none)),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'AI couldn\'t process your video right now. Check My Account — an admin will review it shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                height: 1.4,
                decoration: TextDecoration.none),
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
            child: const Text('OK',
                style: TextStyle(
                    color: Colors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none)),
          ),
        ),
      ],
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_resultStatus == null) {
      return _buildAuraSenseScreen();
    }
    if (_resultStatus == 'rejected') {
      return _buildAuraSenseRejectedScreen();
    }
    if (_resultStatus == 'approved') {
      return _buildAuraSenseApprovedScreen();
    }

    // Only 'ai_error' reaches this small dialog now.
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
                  width: 320,
                  height: 410,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 320,
                        height: 410,
                        padding: const EdgeInsets.all(16),
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
                        child: _buildResultPhase(),
                      ),
                      Positioned(
                        top: -14,
                        right: -14,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(true),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A0050),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF9B4DCA), width: 1.5),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF7B2CBF).withValues(alpha: 0.5), blurRadius: 8),
                              ],
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                          ),
                        ),
                      ),
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
