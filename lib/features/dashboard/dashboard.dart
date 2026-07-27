import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/services/api_client.dart';
import '../../core/services/auth_api_service.dart';
import '../../core/services/challenges_service.dart';
import '../../core/services/creator_page_service.dart';
import '../../core/services/home_service.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../core/models/aura_tier.dart';
import '../../core/utils/streak_date.dart';
import '../../shared/widgets/video_thumbnail_widget.dart' show videoThumbnailCache;
import '../../shared/widgets/level_up_sheet.dart';
import '../../shared/widgets/avatar_widget.dart';
import '../../shared/widgets/wallet_screen.dart';
import '../challenges/screens/all_general_challenges_screen.dart';
import '../challenges/screens/challenge_detail.dart';
import '../challenges/screens/trending_screen.dart';
import '../explore/screens/creator_videos_screen.dart';
import '../../shared/widgets/aura_action_sheet.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../account/screens/my_account_screen.dart';
import '../creator/screens/create_creator_profile_screen.dart';
import '../creator/screens/become_creator_screen.dart';
import '../admin/screens/admin_screen.dart';
import '../video/screens/preview_screen.dart';
import '../../core/services/upload_queue_service.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  String? _lastKnownTier;
  bool _atRiskAlertShown = false;

  // Shared across the Hero/Brand Videos/Trending/Banners sections so they
  // don't each fire their own REST call (and re-fetch on every rebuild).
  late final Future<List<Map<String, dynamic>>> _challengesFuture =
      ChallengesService()
          .fetchChallenges(limit: 20)
          .then((raw) => raw.map(normaliseChallenge).toList());

  // Creator-page-tagged pages for the "Creator Videos" shelf.
  late final Future<List<Map<String, dynamic>>> _trendingCreatorsFuture =
      HomeService().fetchTrendingCreators(limit: 10);

  String? _profileUserId;
  Future<Map<String, dynamic>>? _profileFuture;
  Timer? _profilePollTimer;
  // Cold-start network hiccups (e.g. connectivity not fully up yet right as
  // the app launches) can make the very first profile fetch fail with no
  // underlying persistent problem. Retry once automatically so that doesn't
  // strand the user on an error screen — reset whenever a new user session
  // starts so each login gets its own single free retry.
  bool _autoRetriedProfile = false;

  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  @override
  void initState() {
    super.initState();
    // There's no REST equivalent of Firestore's live `users/{uid}` stream,
    // so poll periodically to keep points/level-up detection reasonably
    // fresh (e.g. after a challenge is scored while this screen is open).
    _profilePollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final uid = _profileUserId;
      if (uid != null) _loadProfile(uid);
    });
  }

  @override
  void dispose() {
    _profilePollTimer?.cancel();
    super.dispose();
  }

  void _loadProfile(String userId) {
    if (!mounted) return;
    setState(() {
      _profileUserId = userId;
      _profileFuture = _fetchDashboardProfile(userId);
    });
  }

  Future<Map<String, dynamic>> _fetchDashboardProfile(String userId) async {
    final results = await Future.wait([
      AuthApiService().getProfile(),
      AuthApiService().fetchStreak(),
      CreatorPageService().fetchOwnPage(),
    ]);
    final profile = results[0];
    if (profile == null) throw Exception('Failed to load profile');
    final streak = results[1];
    final hasCreatorPage = results[2] != null;

    final displayName =
        (profile['displayName'] as String?)?.trim().isNotEmpty == true
            ? profile['displayName'] as String
            : (profile['profileName'] as String? ??
                profile['username'] as String? ??
                profile['name'] as String? ??
                'User');
    final photoUrl = (profile['avatar'] as String? ?? '').isNotEmpty
        ? profile['avatar'] as String
        : profile['profileImageUrl'] as String? ?? '';
    final points = (profile['auraPoints'] as num?)?.toInt() ??
        (profile['totalRewards'] as num?)?.toInt() ??
        0;
    // Server-computed and authoritative — do not recompute level/tier from
    // `points` locally (see aura_tier.dart's auraTierForName).
    final level = (profile['level'] as num?)?.toInt() ?? 1;
    final tierName = profile['tier'] as String?;
    final streakDay = (streak?['currentStreak'] as num?)?.toInt() ?? 0;
    final lastStreakDate = deriveLastStreakDate(streak);

    return {
      'points': points,
      'level': level,
      'tierName': tierName,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'hasCreatorPage': hasCreatorPage,
      'streakDay': streakDay,
      'lastStreakDate': lastStreakDate,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: ApiClient().userId,
      builder: (context, uidSnap) {
        final userId = uidSnap.data;
        if (!uidSnap.hasData || userId == null || userId.isEmpty) {
          return _buildScaffold(context,
              points: 0,
              tierName: null,
              isAdmin: false,
              isBrand: false,
              isCreator: false,
              userId: '',
              displayName: 'Guest',
              photoUrl: '',
              streakDay: 0,
              lastStreakDate: '');
        }
        if (_profileUserId != userId) {
          _autoRetriedProfile = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _loadProfile(userId);
          });
        }
        return _buildProfileLoader(context, userId);
      },
    );
  }

  Widget _buildProfileLoader(BuildContext context, String userId) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snap) {
        if (snap.hasError) {
          if (!_autoRetriedProfile) {
            _autoRetriedProfile = true;
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) _loadProfile(userId);
            });
          }
          return Scaffold(
            backgroundColor: _bg,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.white38, size: 40),
                    const SizedBox(height: 16),
                    const Text('Failed to load profile.',
                        style: TextStyle(color: Colors.white54)),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => _loadProfile(userId),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: _accent),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(
            backgroundColor: _bg,
            body: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }

        final data = snap.data!;
        final points = data['points'] as int;
        // No REST admin-role signal exists yet — admin UI stays hidden until
        // the backend exposes one (the admin panel itself is still Firestore-
        // only and out of scope for this pass).
        const isAdmin = false;
        final hasCreatorPage = data['hasCreatorPage'] as bool;
        final isBrand = hasCreatorPage;
        final isCreator = hasCreatorPage;
        final displayName = data['displayName'] as String;
        final photoUrl = data['photoUrl'] as String;
        final streakDay = data['streakDay'] as int;
        final lastStreakDate = data['lastStreakDate'] as String;
        final level = data['level'] as int;
        final tierName = data['tierName'] as String?;
        final newTier = auraTierForName(tierName);

        // Compare the server's own tier string across fetches (not a
        // locally-guessed level threshold) — a real tier upgrade is exactly
        // when this string moves later in the tiers list.
        if (_lastKnownTier != null && _lastKnownTier != tierName) {
          final oldTier = auraTierForName(_lastKnownTier);
          if (auraTiers.indexOf(newTier) > auraTiers.indexOf(oldTier)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showLevelUpModal(context, level, newTier);
            });
          }
        }
        _lastKnownTier = tierName;

        // At-risk streak alert: show once per session after 7 pm
        if (!_atRiskAlertShown && streakDay > 0 && DateTime.now().hour >= 19) {
          final now = DateTime.now();
          final todayStr =
              '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
          if (lastStreakDate != todayStr) {
            _atRiskAlertShown = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Text('⚠️', style: TextStyle(fontSize: 18)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your streak ends at midnight — play now to save it!',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: const Color(0xFF2D1800),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    duration: const Duration(seconds: 5),
                    action: SnackBarAction(
                      label: 'Play',
                      textColor: Colors.amber,
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const AllGeneralChallengesScreen())),
                    ),
                  ),
                );
            });
          }
        }

        return _buildScaffold(
          context,
          points: points,
          tierName: tierName,
          isAdmin: isAdmin,
          isBrand: isBrand,
          isCreator: isCreator,
          userId: userId,
          displayName: displayName,
          photoUrl: photoUrl,
          streakDay: streakDay,
          lastStreakDate: lastStreakDate,
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required int points,
    required String? tierName,
    required bool isAdmin,
    required bool isBrand,
    required bool isCreator,
    required String userId,
    required String displayName,
    required String photoUrl,
    required int streakDay,
    required String lastStreakDate,
  }) {
    final tier = auraTierForName(tierName);

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: _buildHeader(
                        context, points, tier, displayName, userId),
                  ),
                ),
                SliverToBoxAdapter(
                    child: _buildStreakBanner(streakDay, lastStreakDate)),
                const SliverToBoxAdapter(child: _PendingUploadBanner()),
                SliverToBoxAdapter(child: _buildHeroSection(context)),
                SliverToBoxAdapter(child: _buildBrandVideosSection(context)),
                SliverToBoxAdapter(child: _buildCreatorVideosSection(context)),
                SliverToBoxAdapter(child: _buildBannersSection(context)),
                SliverToBoxAdapter(child: _buildTrendingSection(context)),
                if (!isCreator && !isBrand && !isAdmin)
                  SliverToBoxAdapter(
                      child:
                          _buildBecomeCreatorBanner(context, userId, points)),
                if (!isCreator && !isBrand && !isAdmin)
                  SliverToBoxAdapter(child: _buildBecomeCreatorButton(context)),
                if (isAdmin)
                  SliverToBoxAdapter(child: _buildAdminButton(context)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          _buildBottomNav(context, displayName: displayName, photoUrl: photoUrl),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, int points, AuraTier tier,
      String displayName, String userId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Logo text ─────────────────────────────────
          SizedBox(
            height: 20,
            width: 110,
            child: Image.asset(
              'assets/images/Aura arena.png',
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
            ),
          ),

          const Spacer(),

          // ── Name + Points ─────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'SpaceGrotesk',
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WalletScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0A2E),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: _accent.withValues(alpha: 0.6)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/homescreen/separate elements/coin icon.png',
                        height: 13,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$points',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 10),

          // ── Avatar ────────────────────────────────────
          GestureDetector(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MyAccountScreen())),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4B6EF6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: _accent, width: 1.5),
              ),
              child: Center(
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Streak Banner ──────────────────────────────────────────────────────────
  Widget _buildStreakBanner(int streakDay, String lastStreakDate) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

    final qualifiedToday    = lastStreakDate == todayStr;
    final qualifiedYesterday = lastStreakDate == yesterdayStr;
    final bonusJustCredited = streakDay == 0 && qualifiedToday;

    // Broken: had an active streak but missed at least one full day
    final broken = streakDay > 0 &&
        !qualifiedToday &&
        !qualifiedYesterday &&
        lastStreakDate.isNotEmpty;

    // At risk: after 7 pm, streak active, haven't played today yet
    final atRisk = !broken && streakDay > 0 && !qualifiedToday && now.hour >= 19;

    if (streakDay == 0 && !bonusJustCredited) return const SizedBox.shrink();

    final displayDay = bonusJustCredited ? 7 : streakDay;
    const streakColor = Color(0xFFFF6B35);

    // State-driven appearance
    late Color borderColor;
    late Color labelColor;
    late String emoji;
    late String label;

    if (broken) {
      borderColor = const Color(0xFFFF4444).withValues(alpha: 0.45);
      labelColor  = const Color(0xFFFF6B6B);
      emoji       = '💔';
      label       = 'Streak broken — play today to start a new one!';
    } else if (bonusJustCredited) {
      borderColor = streakColor.withValues(alpha: 0.50);
      labelColor  = streakColor;
      emoji       = '🎉';
      label       = '7-Day Streak complete! +50 Auras awarded';
    } else if (atRisk) {
      borderColor = Colors.amber.withValues(alpha: 0.65);
      labelColor  = Colors.amber;
      emoji       = '⚠️';
      label       = 'Streak ends at midnight — play now to save it!';
    } else if (qualifiedToday) {
      borderColor = streakColor.withValues(alpha: 0.40);
      labelColor  = streakColor;
      emoji       = '🔥';
      label       = 'Day $displayDay/7 — keep it up!';
    } else {
      borderColor = streakColor.withValues(alpha: 0.20);
      labelColor  = Colors.white54;
      emoji       = '🔥';
      label       = 'Day $displayDay/7 — play a challenge to continue';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0820),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Day dot tracker ──────────────────────────────────────
                Row(
                  children: List.generate(7, (i) {
                    final dayNum = i + 1;
                    final isCompleted = broken
                        ? false
                        : (dayNum < displayDay ||
                            (dayNum == displayDay && (qualifiedToday || bonusJustCredited)));
                    final isCurrent =
                        !broken && !bonusJustCredited && dayNum == displayDay && !qualifiedToday;
                    final isPast = broken && dayNum <= displayDay;

                    Color dotBg;
                    Border? dotBorder;
                    Widget dotChild;

                    if (isPast) {
                      dotBg = const Color(0xFFFF4444).withValues(alpha: 0.18);
                      dotChild = const Icon(Icons.close_rounded,
                          color: Color(0xFFFF6B6B), size: 11);
                    } else if (isCompleted) {
                      dotBg = streakColor;
                      dotChild = const Icon(Icons.local_fire_department_rounded,
                          color: Colors.white, size: 12);
                    } else if (isCurrent) {
                      dotBg     = Colors.transparent;
                      dotBorder = Border.all(
                          color: atRisk ? Colors.amber : streakColor, width: 1.5);
                      dotChild  = Text(
                        '$dayNum',
                        style: TextStyle(
                          color: atRisk ? Colors.amber : streakColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    } else {
                      dotBg    = Colors.white.withValues(alpha: 0.06);
                      dotChild = Text(
                        '$dayNum',
                        style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 9,
                            fontWeight: FontWeight.w600),
                      );
                    }

                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i < 6 ? 4 : 0),
                        height: 28,
                        decoration: BoxDecoration(
                          color: dotBg,
                          shape: BoxShape.circle,
                          border: dotBorder,
                        ),
                        child: Center(child: dotChild),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SpaceGrotesk',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Section ───────────────────────────────────────────────────────────
  Widget _buildHeroSection(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _challengesFuture,
      builder: (context, snap) {
        final list = snap.data ?? [];
        final hero = list.isEmpty
            ? null
            : list.firstWhere((c) => c['creatorId'] == 'system',
                orElse: () => list.first);

        String title = 'Bollywood Walk';
        int auraPoints = 150;
        String videoUrl = '';
        String thumbnailUrl = '';
        String instructions = '';
        String challengeId = '';

        if (hero != null) {
          title = hero['title'] as String? ?? title;
          auraPoints = hero['starsCount'] as int? ?? auraPoints;
          videoUrl = hero['videoUrl'] as String? ?? '';
          thumbnailUrl = hero['thumbnailUrl'] as String? ?? '';
          instructions = hero['instructions'] as String? ?? '';
          challengeId = hero['id'] as String? ?? '';
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          child: Container(
            height: 320,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF4B3EAA), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(19),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _VideoThumbnailWidget(
                    videoUrl: videoUrl,
                    thumbnailUrl: thumbnailUrl,
                  ),
                  // Bottom-to-top dark gradient for text readability
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0.2, 1.0],
                        colors: [Colors.transparent, Colors.black],
                      ),
                    ),
                  ),
                  // Content — bottom-left
                  Positioned(
                    left: 16,
                    bottom: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Aura points row
                        Row(
                          children: [
                            const Icon(Icons.diamond_rounded,
                                color: Color(0xFFD4A8FF), size: 22),
                            const SizedBox(width: 6),
                            Text(
                              '$auraPoints',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                fontFamily: 'ClashDisplay',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Challenge title
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'ClashDisplay',
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Take this Challenge button
                        GestureDetector(
                          onTap: challengeId.isNotEmpty
                              ? () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ChallengeDetail(
                                        title: title,
                                        instructions: instructions,
                                        videoUrl: videoUrl,
                                        challengeId: challengeId,
                                      ),
                                    ),
                                  )
                              : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6B2FD9), Color(0xFF9B4DFF)],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Text(
                              'Take this Challenge',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'SpaceGrotesk',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Diamond pagination indicators
                        Row(
                          children: const [
                            Icon(Icons.diamond_outlined,
                                color: Colors.white54, size: 14),
                            SizedBox(width: 6),
                            Icon(Icons.diamond_outlined,
                                color: Colors.white54, size: 14),
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
      },
    );
  }

  // ── Brand Videos ──────────────────────────────────────────────────────────
  Widget _buildBrandVideosSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Brand Videos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'ClashDisplay')),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AllGeneralChallengesScreen())),
                child: const Text('See All >',
                    style: TextStyle(
                        color: Color(0xFF9B4DCA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _challengesFuture,
          builder: (context, snap) {
            final docs = snap.data ?? [];
            if (docs.isEmpty) return const SizedBox.shrink();

            return Column(
              children: [
                // Top row: 3 square thumbnails
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: List.generate(docs.length.clamp(0, 3), (i) {
                      final data = docs[i];
                      final title = data['title'] as String? ?? '';
                      final videoUrl = data['videoUrl'] as String? ?? '';
                      final thumbnailUrl = data['thumbnailUrl'] as String? ?? '';
                      final challengeId = data['id'] as String? ?? '';
                      final instructions = data['instructions'] as String? ?? '';
                      const brandLogoUrl = '';

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                          child: GestureDetector(
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ChallengeDetail(
                                  title: title,
                                  instructions: instructions,
                                  videoUrl: videoUrl,
                                  challengeId: challengeId,
                                ))),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 122,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    _VideoThumbnailWidget(
                                        videoUrl: videoUrl,
                                        thumbnailUrl: thumbnailUrl),
                                    if (brandLogoUrl.isNotEmpty)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: ClipOval(
                                          child: Image.network(brandLogoUrl,
                                              width: 22,
                                              height: 22,
                                              fit: BoxFit.cover),
                                        ),
                                      ),
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.fromLTRB(6, 18, 6, 7),
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [Colors.transparent, Colors.black87],
                                          ),
                                        ),
                                        child: Text(title,
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              fontFamily: 'SpaceGrotesk',
                                              height: 1.3,
                                            )),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                // Bottom row: 2 feature cards
                if (docs.length > 3) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: List.generate(
                          (docs.length - 3).clamp(0, 2), (i) {
                        final data = docs[3 + i];
                        final title = data['title'] as String? ?? '';
                        final description = data['instructions'] as String? ?? '';
                        final auraPoints = data['starsCount'] as int? ?? 0;
                        final videoUrl = data['videoUrl'] as String? ?? '';
                        final thumbnailUrl = data['thumbnailUrl'] as String? ?? '';
                        const brandLogoUrl = '';
                        final challengeId = data['id'] as String? ?? '';

                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: i == 0 ? 0 : 8),
                            child: GestureDetector(
                              onTap: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => ChallengeDetail(
                                    title: title,
                                    instructions: description,
                                    videoUrl: videoUrl,
                                    challengeId: challengeId,
                                  ))),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox(
                                  height: 132,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      _VideoThumbnailWidget(
                                          videoUrl: videoUrl,
                                          thumbnailUrl: thumbnailUrl),
                                      Container(color: Colors.black.withValues(alpha: 0.45)),
                                      if (brandLogoUrl.isNotEmpty)
                                        Positioned(
                                          top: 8,
                                          right: 8,
                                          child: ClipOval(
                                            child: Image.network(brandLogoUrl,
                                                width: 26,
                                                height: 26,
                                                fit: BoxFit.cover),
                                          ),
                                        ),
                                      Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            Text(title.toUpperCase(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.3,
                                                  fontFamily: 'ClashDisplay',
                                                )),
                                            const SizedBox(height: 3),
                                            Text(description,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white60,
                                                  fontSize: 9,
                                                  height: 1.35,
                                                  fontFamily: 'SpaceGrotesk',
                                                )),
                                            const SizedBox(height: 6),
                                            Row(children: [
                                              const Icon(Icons.diamond_rounded,
                                                  color: Color(0xFFD4A8FF), size: 13),
                                              const SizedBox(width: 3),
                                              Text('$auraPoints',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'SpaceGrotesk',
                                                  )),
                                            ]),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Trending ───────────────────────────────────────────────────────────────
  Widget _buildTrendingSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Trending videos',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'ClashDisplay')),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TrendingScreen())),
                child: const Text('See All >',
                    style: TextStyle(
                        color: Color(0xFF9B4DCA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _challengesFuture,
          builder: (context, snap) {
            final docs = snap.data ?? [];
            if (docs.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: List.generate(docs.length.clamp(0, 3), (i) {
                  final data = docs[i];
                  final title = data['title'] as String? ?? '';
                  final videoUrl = data['videoUrl'] as String? ?? '';
                  final thumbnailUrl = data['thumbnailUrl'] as String? ?? '';
                  final challengeId = data['id'] as String? ?? '';
                  final instructions = data['instructions'] as String? ?? '';
                  const brandLogoUrl = '';

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                      child: GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ChallengeDetail(
                              title: title,
                              instructions: instructions,
                              videoUrl: videoUrl,
                              challengeId: challengeId,
                            ))),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 122,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _VideoThumbnailWidget(
                                    videoUrl: videoUrl,
                                    thumbnailUrl: thumbnailUrl),
                                if (brandLogoUrl.isNotEmpty)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: ClipOval(
                                      child: Image.network(brandLogoUrl,
                                          width: 22,
                                          height: 22,
                                          fit: BoxFit.cover),
                                    ),
                                  ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(6, 18, 6, 7),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.transparent, Colors.black87],
                                      ),
                                    ),
                                    child: Text(title,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          fontFamily: 'SpaceGrotesk',
                                          height: 1.3,
                                        )),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Creator Videos ────────────────────────────────────────────────────────
  Widget _buildCreatorVideosSection(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _trendingCreatorsFuture,
      builder: (context, snap) {
        final docs = snap.data ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Creator Videos',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'ClashDisplay')),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CreatorVideosScreen())),
                    child: const Text('See All ›',
                        style: TextStyle(color: Color(0xFF9B4DCA), fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 148,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data     = docs[i];
                  final pageName = data['pageName'] as String? ??
                      data['displayName'] as String? ??
                      data['name'] as String? ??
                      'Creator';
                  final imgUrl   = data['profileImageUrl'] as String? ??
                      data['avatar'] as String? ??
                      data['profileImage'] as String? ??
                      '';

                  return GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const CreatorVideosScreen())),
                    child: Container(
                      width: 90,
                      margin: const EdgeInsets.only(right: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 74, height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(color: _accent.withValues(alpha: 0.6), width: 2),
                            ),
                            child: imgUrl.isNotEmpty
                                ? ClipOval(child: Image.network(imgUrl, fit: BoxFit.cover))
                                : Center(
                                    child: Text(
                                      pageName.isNotEmpty ? pageName[0].toUpperCase() : 'C',
                                      style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          Text(pageName, maxLines: 1, overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600,
                                  fontFamily: 'SpaceGrotesk')),
                          const SizedBox(height: 8),
                          Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: _accent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Center(
                              child: Text('Follow',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'SpaceGrotesk',
                                  )),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  // ── Banners ────────────────────────────────────────────────────────────────
  Widget _buildBannersSection(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _challengesFuture,
      builder: (context, snap) {
        final docs = snap.data ?? [];
        if (!snap.hasData) return const SizedBox.shrink();

        // If no backend data yet, show a static placeholder banner
        final count = docs.isEmpty ? 1 : docs.length.clamp(0, 3);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('Banners',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'ClashDisplay')),
            ),
            SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: count,
                itemBuilder: (_, i) {
                  final hasDoc = i < docs.length;
                  final data = hasDoc ? docs[i] : null;
                  final title = data?['title'] as String? ?? 'Featured Challenge';
                  final description = data?['instructions'] as String? ?? 'Complete this challenge to earn Aura points.';
                  final auraPoints = data?['starsCount'] as int? ?? 150;
                  final videoUrl = data?['videoUrl'] as String? ?? '';
                  final thumbnailUrl = data?['thumbnailUrl'] as String? ?? '';
                  final challengeId = data?['id'] as String? ?? '';

                  return GestureDetector(
                    onTap: challengeId.isNotEmpty
                        ? () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => ChallengeDetail(
                              title: title,
                              instructions: description,
                              videoUrl: videoUrl,
                              challengeId: challengeId,
                            )))
                        : null,
                    child: Container(
                      width: MediaQuery.of(context).size.width - 24,
                      margin: EdgeInsets.only(right: i < count - 1 ? 12 : 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _VideoThumbnailWidget(
                                videoUrl: videoUrl,
                                thumbnailUrl: thumbnailUrl),
                            // left-to-right dark gradient
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  stops: [0.0, 0.55, 0.80],
                                  colors: [
                                    Color(0xEE000000),
                                    Color(0xBB000000),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(title.toUpperCase(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w900,
                                        height: 1.1,
                                        fontFamily: 'ClashDisplay',
                                      )),
                                  const SizedBox(height: 6),
                                  Text(description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 11,
                                        height: 1.4,
                                        fontFamily: 'SpaceGrotesk',
                                      )),
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    const Icon(Icons.diamond_rounded,
                                        color: Color(0xFFD4A8FF), size: 16),
                                    const SizedBox(width: 4),
                                    Text('$auraPoints+',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          fontFamily: 'SpaceGrotesk',
                                        )),
                                  ]),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  // ── Become Creator banner (regular users only) ─────────────────────────────
  Widget _buildBecomeCreatorBanner(
      BuildContext context, String userId, int points) {
    return GestureDetector(
      onTap: () {
        if (points < 500) {
          _showCreatorGateSheet(context, points);
          return;
        }
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const CreateCreatorProfileScreen()),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A0A30), Color(0xFF0A1630)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: _accent.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_rounded,
                  color: Color(0xFFD4A8FF), size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Become a Creator',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'ClashDisplay',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    points >= 500
                        ? 'You qualify! Launch challenges & grow your brand'
                        : '${500 - points} Aura to unlock — keep playing!',
                    style: TextStyle(
                      color: points >= 500
                          ? const Color(0xFFD4A8FF)
                          : Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              points >= 500
                  ? Icons.arrow_forward_ios_rounded
                  : Icons.lock_outline_rounded,
              color: points >= 500 ? Colors.white54 : Colors.white24,
              size: 15,
            ),
          ],
        ),
      ),
    );
  }

  // ── Become Creator button (standalone entry point) ─────────────────────────
  Widget _buildBecomeCreatorButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BecomeCreatorScreen()),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: _accent.withValues(alpha: 0.5)),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: const Icon(Icons.diamond_rounded,
              color: Color(0xFFD4A8FF), size: 18),
          label: const Text(
            'Become a Creator',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: 'SpaceGrotesk'),
          ),
        ),
      ),
    );
  }

  // ── Creator gate modal ─────────────────────────────────────────────────────
  void _showCreatorGateSheet(BuildContext context, int currentPoints) {
    const required = 500;
    final progress = (currentPoints / required).clamp(0.0, 1.0);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF100A20),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3)),
            ),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border:
                    Border.all(color: _accent.withValues(alpha: 0.40), width: 1.5),
              ),
              child:
                  const Icon(Icons.lock_outline_rounded, color: _accent, size: 30),
            ),
            const SizedBox(height: 18),
            const Text(
              '500 Aura Required',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'ClashDisplay'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Earn 500 Aura points by completing challenges\nto unlock Creator status.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: Colors.white54, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 24),
            // Progress bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$currentPoints Aura',
                  style: const TextStyle(
                      color: Color(0xFFD4A8FF),
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  '${required - currentPoints.clamp(0, required)} to go',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: v,
                  minHeight: 10,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF7B2CBF)),
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: const Text('Keep Playing'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFB91C1C),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Admin Panel',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'SpaceGrotesk')),
        ),
      ),
    );
  }

  // ── Level-up modal ─────────────────────────────────────────────────────────
  void _showLevelUpModal(BuildContext context, int level, AuraTier tier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LevelUpSheet(level: level, tier: tier),
    );
  }

  // ── Bottom Nav ─────────────────────────────────────────────────────────────
  Widget _buildBottomNav(BuildContext context, {required String displayName, required String photoUrl}) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: SizedBox(
          height: 74,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // Pill-shaped nav bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 62,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _navItem(
                        icon: Icons.emoji_events_rounded,
                        label: 'Challenges',
                        active: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const AllGeneralChallengesScreen()),
                        ),
                      ),
                      _navItem(
                        icon: Icons.storefront_rounded,
                        label: 'Brand',
                        // Brands section isn't built yet; stay on Dashboard for now.
                        onTap: () =>
                            Navigator.popUntil(context, (route) => route.isFirst),
                      ),
                      const SizedBox(width: 58),
                      _navItem(
                        icon: Icons.leaderboard_rounded,
                        label: 'Leaderboard',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LeaderboardScreen()),
                        ),
                      ),
                      _profileNavItem(
                        context,
                        displayName: displayName,
                        photoUrl: photoUrl,
                      ),
                    ],
                  ),
                ),
              ),
              // Floating centre button
              Positioned(
                top: 0,
                child: GestureDetector(
                  onTap: () => showAuraActionSheet(context),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0D0020),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.7),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.5),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(13),
                      child: Image.asset(
                        'assets/images/Aura Arena Mono.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileNavItem(BuildContext context, {required String displayName, required String photoUrl}) {
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyAccountScreen()),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarWidget(
              photoUrl: photoUrl,
              fallbackText: initial,
              radius: 13,
              backgroundColor: _accent.withValues(alpha: 0.30),
              textStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 3),
            const Text(
              'Profile',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                fontSize: 9,
                fontFamily: 'SpaceGrotesk',
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? _accent : Colors.white54, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? _accent : Colors.white38,
                fontSize: 9,
                fontFamily: 'SpaceGrotesk',
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ── Video Thumbnail Widget ─────────────────────────────────────────────────
class _VideoThumbnailWidget extends StatefulWidget {
  final String videoUrl;
  final String? thumbnailUrl; // direct image URL from backend

  const _VideoThumbnailWidget({
    required this.videoUrl,
    this.thumbnailUrl,
  });

  @override
  State<_VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<_VideoThumbnailWidget> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_VideoThumbnailWidget old) {
    super.didUpdateWidget(old);
    if (old.videoUrl != widget.videoUrl || old.thumbnailUrl != widget.thumbnailUrl) {
      setState(() => _thumb = null);
      _load();
    }
  }

  Future<void> _load() async {
    // If backend provides a direct image URL, no video decode needed
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) return;
    if (widget.videoUrl.isEmpty) return;
    if (videoThumbnailCache.containsKey(widget.videoUrl)) {
      if (mounted) setState(() => _thumb = videoThumbnailCache[widget.videoUrl]);
      return;
    }
    // HLS manifests (.m3u8) can't be frame-extracted by video_thumbnail —
    // skip straight to the placeholder instead of a wasted 12s timeout.
    if (widget.videoUrl.toLowerCase().contains('.m3u8')) return;
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: widget.videoUrl,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 480,
        quality: 75,
      ).timeout(const Duration(seconds: 12));
      debugPrint('[VideoThumbnail] ${widget.videoUrl} -> ${bytes == null ? "null (no frame extracted)" : "${bytes.length} bytes"}');
      if (bytes != null) videoThumbnailCache[widget.videoUrl] = bytes;
      if (mounted) setState(() => _thumb = bytes);
    } catch (e, st) {
      debugPrint('[VideoThumbnail] FAILED for ${widget.videoUrl}: $e');
      debugPrint('$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final thumbUrl = widget.thumbnailUrl;
    if (thumbUrl != null && thumbUrl.isNotEmpty) {
      return Image.network(
        thumbUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (_thumb != null) {
      return Image.memory(
        _thumb!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF0F0F1A),
        child: const Center(
          child: Icon(Icons.play_circle_outline_rounded,
              color: Colors.white12, size: 40),
        ),
      );
}

// ── Pending upload recovery banner ────────────────────────────────────────────

class _PendingUploadBanner extends StatefulWidget {
  const _PendingUploadBanner();

  @override
  State<_PendingUploadBanner> createState() => _PendingUploadBannerState();
}

class _PendingUploadBannerState extends State<_PendingUploadBanner> {
  PendingUpload? _pending;
  bool _dismissed = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final p = await UploadQueueService.getPending();
    if (mounted) setState(() { _pending = p; _checked = true; });
  }

  Future<void> _retry() async {
    final p = _pending;
    if (p == null) return;
    setState(() => _dismissed = true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          videoPath:      p.videoPath,
          challengeId:    p.challengeId,
          challengeTitle: p.challengeTitle,
        ),
      ),
    );
  }

  // The "X" looks like a routine dismiss-this-notification action, but it
  // was wired to UploadQueueService.clear() — permanently discarding the
  // only reference to the recorded video (and any Aura points it would have
  // earned) with no way back. Confirm first so closing the banner can't be
  // mistaken for a harmless "hide this" tap.
  Future<void> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF15122A),
        title: const Text('Discard this video?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'This video hasn\'t been uploaded yet. Discarding it means it '
          'won\'t be submitted and you won\'t earn any Aura points for it.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it',
                style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await UploadQueueService.clear();
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || _pending == null || _dismissed) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.upload_outlined, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upload pending',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _pending!.challengeTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: _retry,
            child: const Text(
              'Retry',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
            onPressed: _confirmDiscard,
          ),
        ],
      ),
    );
  }
}
