import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/api_client.dart';
import '../../core/services/auth_api_service.dart';
import '../../core/services/connectivity_probe.dart';
import '../../core/services/challenges_service.dart';
import '../../core/services/home_service.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/models/aura_tier.dart';
import '../../core/utils/streak_date.dart';
import '../../shared/widgets/video_thumbnail_widget.dart';
import '../../shared/widgets/category_icon_badge.dart';
import '../../shared/widgets/level_up_sheet.dart';
import '../../shared/widgets/wallet_screen.dart';
import '../challenges/screens/all_general_challenges_screen.dart';
import '../challenges/screens/challenge_detail.dart';
import '../challenges/screens/trending_screen.dart';
import '../explore/screens/brands_list_screen.dart';
import '../explore/screens/creator_profile_screen.dart';
import '../explore/screens/creator_videos_screen.dart';
import '../../shared/widgets/notification_bell_button.dart';
import '../admin/screens/admin_screen.dart';
import '../video/screens/preview_screen.dart';
import '../../core/services/upload_queue_service.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../shared/theme/app_colors.dart';
import '../../core/utils/error_message.dart';
import '../../shared/widgets/app_bottom_nav.dart';

// Exponential backoff for Dashboard's profile-load auto-retry: 8s, 16s,
// 32s, 60s (capped), for attempt numbers 1, 2, 3, 4+. Extracted as a top-
// level function so the schedule itself is directly unit-testable without
// having to drive a full widget test through real (fake-clock) Timers and
// a rejecting Future, which is exactly the kind of test that's fragile in
// this codebase's Flutter-test harness.
int profileAutoRetryDelaySeconds(int attemptNumber) {
  return (8 * (1 << (attemptNumber - 1))).clamp(0, 60);
}

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

  late final Future<Map<String, String>> _categoryNamesFuture =
      ChallengesService().fetchCategoryNameMap();

  // Creator-page-tagged pages for the "Creator Videos" shelf.
  late final Future<List<Map<String, dynamic>>> _trendingCreatorsFuture =
      HomeService().fetchTrendingCreators(limit: 10);

  String? _profileUserId;
  Future<Map<String, dynamic>>? _profileFuture;
  Timer? _profilePollTimer;
  // Cold-start network hiccups (e.g. connectivity not fully up yet right as
  // the app launches) can make the very first profile fetch fail with no
  // underlying persistent problem. Retry automatically so that doesn't
  // strand the user on an error screen.
  //
  // This used to be a single fixed 2s retry — fine for a one-off blip, but
  // on a connection that's persistently bad (confirmed: users see this even
  // on strong wifi, not just flaky mobile data) it meant the error screen
  // flashed away and back every ~2s, on top of the unrelated 20s freshness
  // poll below also re-triggering a fetch — making the app feel like it was
  // "constantly popping up" this screen rather than quietly waiting out a
  // bad stretch. Exponential backoff (8s, 16s, 32s, capped at 60s) capped at
  // a handful of automatic attempts is far less naggy; past that, the user's
  // own Retry tap takes over. Reset whenever a new user session starts or a
  // load actually succeeds, so a later transient failure gets the full
  // budget again instead of starting already-maxed-out.
  int _autoRetryCount = 0;
  static const _maxAutoRetries = 4;
  Timer? _autoRetryTimer;

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
      // Skip while an error-driven backoff retry is already scheduled —
      // firing both would double up two retries on the same failing
      // request instead of the one, gentler cadence backoff is meant to be.
      if (uid != null && _autoRetryTimer == null) _loadProfile(uid);
    });
    // Fire-and-forget: requests OS push permission and registers/refreshes
    // the device token with the backend. Dashboard is only ever reached
    // once authenticated, so this doubles as "run once per session start"
    // for both a cold-start already-logged-in user and a fresh login.
    PushNotificationService().initialize();
  }

  @override
  void dispose() {
    _profilePollTimer?.cancel();
    _autoRetryTimer?.cancel();
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
    try {
      return await _fetchDashboardProfileOnce(userId);
    } catch (e) {
      // A single failed request isn't reliable evidence the backend is
      // actually unreachable — see ConnectivityProbe's doc comment. Only
      // commit to the "couldn't reach servers" error once repeated pings
      // confirm it; a false alarm gets one immediate silent retry instead
      // of ever surfacing that screen for what was really just a blip.
      if (isNetworkError(e) && !(await ConnectivityProbe.confirmUnreachable())) {
        return _fetchDashboardProfileOnce(userId);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _fetchDashboardProfileOnce(
      String userId) async {
    // fetchStreak() still swallows its own failures to null (streak is
    // decorative — default to day 0 rather than fail the whole screen over
    // it). The profile leg uses getProfileOrThrow() so a real failure
    // reason survives to the error screen below instead of collapsing into
    // a generic "no internet" message regardless of cause.
    final results = await Future.wait([
      AuthApiService().getProfileOrThrow(),
      AuthApiService().fetchStreak(),
    ]);
    final profile = results[0]!;
    final streak = results[1];
    final role = profile['role'] as String?;

    final displayName =
        (profile['displayName'] as String?)?.trim().isNotEmpty == true
            ? profile['displayName'] as String
            : (profile['profileName'] as String? ??
                profile['username'] as String? ??
                profile['name'] as String? ??
                'User');
    final username =
        profile['profileName'] as String? ??
        profile['username'] as String? ??
        '';
    final photoUrl =
        (profile['avatar'] as String? ?? '').isNotEmpty
            ? profile['avatar'] as String
            : profile['profileImageUrl'] as String? ?? '';
    final points =
        (profile['auraPoints'] as num?)?.toInt() ??
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
      'username': username,
      'photoUrl': photoUrl,
      'role': role,
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
          return _buildScaffold(
            context,
            points: 0,
            tierName: null,
            isAdmin: false,
            isBrand: false,
            isCreator: false,
            userId: '',
            displayName: 'Guest',
            username: '',
            photoUrl: '',
            streakDay: 0,
            lastStreakDate: '',
          );
        }
        if (_profileUserId != userId) {
          _autoRetryCount = 0;
          _autoRetryTimer?.cancel();
          _autoRetryTimer = null;
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
          if (_autoRetryTimer == null && _autoRetryCount < _maxAutoRetries) {
            _autoRetryCount++;
            final delay =
                Duration(seconds: profileAutoRetryDelaySeconds(_autoRetryCount));
            _autoRetryTimer = Timer(delay, () {
              _autoRetryTimer = null;
              if (mounted) _loadProfile(userId);
            });
          }
          final error = snap.error!;
          final networkIssue = isNetworkError(error);
          return Scaffold(
            backgroundColor: _bg,
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      networkIssue
                          ? Icons.wifi_off_rounded
                          : Icons.error_outline_rounded,
                      color: Colors.white38,
                      size: 40,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      // Only the connectivity-flavored exceptions get the
                      // generic "couldn't reach servers" copy — anything
                      // else (a real backend error, a bad response shape,
                      // etc.) shows its actual reason instead of being
                      // misreported as a connection problem.
                      networkIssue
                          ? humanizeError(error)
                          : 'Failed to load profile: ${humanizeError(error)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => _loadProfile(userId),
                      style: ElevatedButton.styleFrom(backgroundColor: _accent),
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

        // A load just succeeded — give a future transient failure the full
        // retry budget again instead of picking up already-maxed-out.
        _autoRetryCount = 0;

        final data = snap.data!;
        final points = data['points'] as int;
        // `role` is the backend's source of truth (player/brand/admin/creator)
        // — an admin can promote a user straight to `creator` via RBAC without
        // a `/creator/page` record ever existing, so gate on this, not on
        // whether a creator page was ever created.
        final role = data['role'] as String?;
        final isAdmin = role == 'admin';
        final isBrand = role == 'brand' || role == 'creator' || isAdmin;
        final isCreator = isBrand;
        final displayName = data['displayName'] as String;
        final username = data['username'] as String;
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
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: const Color(0xFF2D1800),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 5),
                    action: SnackBarAction(
                      label: 'Play',
                      textColor: Colors.amber,
                      onPressed:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => const AllGeneralChallengesScreen(),
                            ),
                          ),
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
          username: username,
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
    required String username,
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
                      context,
                      points,
                      tier,
                      displayName,
                      username,
                      userId,
                      photoUrl,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _buildStreakBanner(streakDay, lastStreakDate),
                ),
                const SliverToBoxAdapter(child: _PendingUploadBanner()),
                SliverToBoxAdapter(child: _buildHeroSection(context)),
                SliverToBoxAdapter(child: _buildBrandVideosSection(context)),
                SliverToBoxAdapter(child: _buildCreatorVideosSection(context)),
                SliverToBoxAdapter(child: _buildBannersSection(context)),
                SliverToBoxAdapter(child: _buildTrendingSection(context)),
                if (isAdmin)
                  SliverToBoxAdapter(child: _buildAdminButton(context)),
                SliverToBoxAdapter(child: _buildEndlessChallengesHeader(context)),
                _buildEndlessChallengesGrid(context),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
          const AppBottomNav(activeTab: AppNavTab.home),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────
  Widget _buildHeader(
    BuildContext context,
    int points,
    AuraTier tier,
    String displayName,
    String username,
    String userId,
    String photoUrl,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Logo text ─────────────────────────────────
          SizedBox(
            height: 26,
            width: 140,
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
                username.isNotEmpty ? '@$username' : displayName,
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
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const WalletScreen()),
                    ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0A2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _accent.withValues(alpha: 0.6)),
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

          const NotificationBellButton(),
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

    final qualifiedToday = lastStreakDate == todayStr;
    final qualifiedYesterday = lastStreakDate == yesterdayStr;
    final bonusJustCredited = streakDay == 0 && qualifiedToday;

    // Broken: had an active streak but missed at least one full day
    final broken =
        streakDay > 0 &&
        !qualifiedToday &&
        !qualifiedYesterday &&
        lastStreakDate.isNotEmpty;

    // At risk: after 7 pm, streak active, haven't played today yet
    final atRisk =
        !broken && streakDay > 0 && !qualifiedToday && now.hour >= 19;

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
      labelColor = const Color(0xFFFF6B6B);
      emoji = '💔';
      label = 'Streak broken — play today to start a new one!';
    } else if (bonusJustCredited) {
      borderColor = streakColor.withValues(alpha: 0.50);
      labelColor = streakColor;
      emoji = '🎉';
      label = '7-Day Streak complete! +50 Auras awarded';
    } else if (atRisk) {
      borderColor = Colors.amber.withValues(alpha: 0.65);
      labelColor = Colors.amber;
      emoji = '⚠️';
      label = 'Streak ends at midnight — play now to save it!';
    } else if (qualifiedToday) {
      borderColor = streakColor.withValues(alpha: 0.40);
      labelColor = streakColor;
      emoji = '🔥';
      label = 'Day $displayDay/7 — keep it up!';
    } else {
      borderColor = streakColor.withValues(alpha: 0.20);
      labelColor = AppColors.textMuted;
      emoji = '🔥';
      label = 'Day $displayDay/7 — play a challenge to continue';
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
                    final isCompleted =
                        broken
                            ? false
                            : (dayNum < displayDay ||
                                (dayNum == displayDay &&
                                    (qualifiedToday || bonusJustCredited)));
                    final isCurrent =
                        !broken &&
                        !bonusJustCredited &&
                        dayNum == displayDay &&
                        !qualifiedToday;
                    final isPast = broken && dayNum <= displayDay;

                    Color dotBg;
                    Border? dotBorder;
                    Widget dotChild;

                    if (isPast) {
                      dotBg = const Color(0xFFFF4444).withValues(alpha: 0.18);
                      dotChild = const Icon(
                        Icons.close_rounded,
                        color: Color(0xFFFF6B6B),
                        size: 11,
                      );
                    } else if (isCompleted) {
                      dotBg = streakColor;
                      dotChild = const Icon(
                        Icons.local_fire_department_rounded,
                        color: Colors.white,
                        size: 12,
                      );
                    } else if (isCurrent) {
                      dotBg = Colors.transparent;
                      dotBorder = Border.all(
                        color: atRisk ? Colors.amber : streakColor,
                        width: 1.5,
                      );
                      dotChild = Text(
                        '$dayNum',
                        style: TextStyle(
                          color: atRisk ? Colors.amber : streakColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    } else {
                      dotBg = Colors.white.withValues(alpha: 0.06);
                      dotChild = Text(
                        '$dayNum',
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
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
        final hero =
            list.isEmpty
                ? null
                : list.firstWhere(
                  (c) => c['creatorId'] == 'system',
                  orElse: () => list.first,
                );

        String title = 'Bollywood Walk';
        String videoUrl = '';
        String thumbnailUrl = '';
        String instructions = '';
        String challengeId = '';
        String categoryId = '';

        if (hero != null) {
          title = hero['title'] as String? ?? title;
          videoUrl = hero['videoUrl'] as String? ?? '';
          thumbnailUrl = hero['thumbnailUrl'] as String? ?? '';
          instructions = hero['instructions'] as String? ?? '';
          challengeId = hero['id'] as String? ?? '';
          categoryId = hero['category'] as String? ?? '';
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          child: GestureDetector(
            onTap:
                challengeId.isNotEmpty
                    ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => ChallengeDetail(
                              title: title,
                              instructions: instructions,
                              videoUrl: videoUrl,
                              challengeId: challengeId,
                            ),
                      ),
                    )
                    : null,
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
                    VideoThumbnailWidget(
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
                    // Featured tag
                    Positioned(
                      left: 16,
                      top: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              color: Color(0xFFD4A8FF),
                              size: 14,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Featured',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'SpaceGrotesk',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Category icon — top-right (Featured tag owns top-left)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: FutureBuilder<Map<String, String>>(
                        future: _categoryNamesFuture,
                        builder: (context, catSnap) {
                          final categoryNames = catSnap.data ?? const {};
                          return CategoryIconBadge(
                            categoryName: categoryNames[categoryId],
                          );
                        },
                      ),
                    ),
                  ],
                ),
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
              const Text('Brand Videos', style: AppTextStyles.sectionHeader),
              GestureDetector(
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const BrandsListScreen(),
                      ),
                    ),
                child: const Text(
                  'See All >',
                  style: TextStyle(
                    color: Color(0xFF9B4DCA),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _challengesFuture,
          builder: (context, snap) {
            final docs = snap.data ?? [];
            if (docs.isEmpty) return const SizedBox.shrink();

            return FutureBuilder<Map<String, String>>(
              future: _categoryNamesFuture,
              builder: (context, catSnap) {
                final categoryNames = catSnap.data ?? const {};

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
                          final thumbnailUrl =
                              data['thumbnailUrl'] as String? ?? '';
                          final challengeId = data['id'] as String? ?? '';
                          final categoryId = data['category'] as String? ?? '';
                          final instructions =
                              data['instructions'] as String? ?? '';
                          const brandLogoUrl = '';

                          return Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                              child: GestureDetector(
                                onTap:
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => ChallengeDetail(
                                              title: title,
                                              instructions: instructions,
                                              videoUrl: videoUrl,
                                              challengeId: challengeId,
                                            ),
                                      ),
                                    ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    height: 122,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        VideoThumbnailWidget(
                                          videoUrl: videoUrl,
                                          thumbnailUrl: thumbnailUrl,
                                        ),
                                        Positioned(
                                          top: 6,
                                          left: 6,
                                          child: CategoryIconBadge(
                                            categoryName:
                                                categoryNames[categoryId],
                                          ),
                                        ),
                                        if (brandLogoUrl.isNotEmpty)
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: ClipOval(
                                              child: Image.network(
                                                brandLogoUrl,
                                                width: 22,
                                                height: 22,
                                                fit: BoxFit.cover,
                                              ),
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
                            (docs.length - 3).clamp(0, 2),
                            (i) {
                              final data = docs[3 + i];
                              final title = data['title'] as String? ?? '';
                              final description =
                                  data['instructions'] as String? ?? '';
                              final videoUrl =
                                  data['videoUrl'] as String? ?? '';
                              final thumbnailUrl =
                                  data['thumbnailUrl'] as String? ?? '';
                              final categoryId =
                                  data['category'] as String? ?? '';
                              const brandLogoUrl = '';
                              final challengeId = data['id'] as String? ?? '';

                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    left: i == 0 ? 0 : 8,
                                  ),
                                  child: GestureDetector(
                                    onTap:
                                        () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) => ChallengeDetail(
                                                  title: title,
                                                  instructions: description,
                                                  videoUrl: videoUrl,
                                                  challengeId: challengeId,
                                                ),
                                          ),
                                        ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: SizedBox(
                                        height: 132,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            VideoThumbnailWidget(
                                              videoUrl: videoUrl,
                                              thumbnailUrl: thumbnailUrl,
                                            ),
                                            Container(
                                              color: Colors.black.withValues(
                                                alpha: 0.45,
                                              ),
                                            ),
                                            Positioned(
                                              top: 8,
                                              left: 8,
                                              child: CategoryIconBadge(
                                                categoryName:
                                                    categoryNames[categoryId],
                                              ),
                                            ),
                                            if (brandLogoUrl.isNotEmpty)
                                              Positioned(
                                                top: 8,
                                                right: 8,
                                                child: ClipOval(
                                                  child: Image.network(
                                                    brandLogoUrl,
                                                    width: 26,
                                                    height: 26,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
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
              const Text('Trending videos', style: AppTextStyles.sectionHeader),
              GestureDetector(
                onTap:
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TrendingScreen()),
                    ),
                child: const Text(
                  'See All >',
                  style: TextStyle(
                    color: Color(0xFF9B4DCA),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _challengesFuture,
          builder: (context, snap) {
            final docs = snap.data ?? [];
            if (docs.isEmpty) return const SizedBox.shrink();

            return FutureBuilder<Map<String, String>>(
              future: _categoryNamesFuture,
              builder: (context, catSnap) {
                final categoryNames = catSnap.data ?? const {};

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: List.generate(docs.length.clamp(0, 3), (i) {
                      final data = docs[i];
                      final title = data['title'] as String? ?? '';
                      final videoUrl = data['videoUrl'] as String? ?? '';
                      final thumbnailUrl =
                          data['thumbnailUrl'] as String? ?? '';
                      final challengeId = data['id'] as String? ?? '';
                      final categoryId = data['category'] as String? ?? '';
                      final instructions =
                          data['instructions'] as String? ?? '';
                      const brandLogoUrl = '';

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                          child: GestureDetector(
                            onTap:
                                () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder:
                                        (_) => ChallengeDetail(
                                          title: title,
                                          instructions: instructions,
                                          videoUrl: videoUrl,
                                          challengeId: challengeId,
                                        ),
                                  ),
                                ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                height: 122,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    VideoThumbnailWidget(
                                      videoUrl: videoUrl,
                                      thumbnailUrl: thumbnailUrl,
                                    ),
                                    Positioned(
                                      top: 6,
                                      left: 6,
                                      child: CategoryIconBadge(
                                        categoryName: categoryNames[categoryId],
                                      ),
                                    ),
                                    if (brandLogoUrl.isNotEmpty)
                                      Positioned(
                                        top: 6,
                                        right: 6,
                                        child: ClipOval(
                                          child: Image.network(
                                            brandLogoUrl,
                                            width: 22,
                                            height: 22,
                                            fit: BoxFit.cover,
                                          ),
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
            );
          },
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Endless challenges grid ───────────────────────────────────────────────
  // Loops the same 20 challenges already fetched for the sections above
  // (no extra network calls — this is not pagination) indefinitely via
  // modulo indexing, purely so the dashboard's scroll has real depth
  // instead of stopping dead right after Trending Videos.
  Widget _buildEndlessChallengesHeader(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text('More Challenges', style: AppTextStyles.sectionHeader),
    );
  }

  Widget _buildEndlessChallengesGrid(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _challengesFuture,
      builder: (context, snap) {
        final docs = snap.data ?? [];
        if (docs.isEmpty) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        return FutureBuilder<Map<String, String>>(
          future: _categoryNamesFuture,
          builder: (context, catSnap) {
            final categoryNames = catSnap.data ?? const {};
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.75,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final data = docs[i % docs.length];
                    return _EndlessChallengeCard(
                      data: data,
                      categoryName:
                          categoryNames[data['category'] as String? ?? ''],
                    );
                  },
                  // Far more than anyone will ever actually scroll through —
                  // not truly infinite (Sliver delegates need a concrete
                  // count), just large enough that the grid never visibly
                  // ends.
                  childCount: 9000,
                ),
              ),
            );
          },
        );
      },
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
                  const Text(
                    'Creator Profiles',
                    style: AppTextStyles.sectionHeader,
                  ),
                  GestureDetector(
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreatorVideosScreen(),
                          ),
                        ),
                    child: const Text(
                      'See All ›',
                      style: TextStyle(
                        color: Color(0xFF9B4DCA),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 110,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final data = docs[i];
                  final creatorId =
                      data['_id'] as String? ?? data['id'] as String? ?? '';
                  final pageName =
                      data['pageName'] as String? ??
                      data['displayName'] as String? ??
                      data['name'] as String? ??
                      'Creator';
                  final imgUrl =
                      data['profileImageUrl'] as String? ??
                      data['avatar'] as String? ??
                      data['profileImage'] as String? ??
                      '';

                  return GestureDetector(
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder:
                                (_) =>
                                    creatorId.isNotEmpty
                                        ? CreatorProfileScreen(
                                          creatorId: creatorId,
                                        )
                                        : const CreatorVideosScreen(),
                          ),
                        ),
                    child: Container(
                      width: 90,
                      margin: const EdgeInsets.only(right: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7B2FF7), Color(0xFFF107A3)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              border: Border.all(
                                color: _accent.withValues(alpha: 0.6),
                                width: 2,
                              ),
                            ),
                            child:
                                imgUrl.isNotEmpty
                                    ? ClipOval(
                                      child: Image.network(
                                        imgUrl,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                    : Center(
                                      child: Text(
                                        pageName.isNotEmpty
                                            ? pageName[0].toUpperCase()
                                            : 'C',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            pageName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'SpaceGrotesk',
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
  // Static promo banner (decorative, no tap action) — was previously faking
  // a "banner" by rendering the challenges list with a diamond/aura-points
  // overlay, which showed a challenge card instead of an actual banner.
  Widget _buildBannersSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                'assets/images/homescreen/dashboard banner.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildAdminButton(BuildContext context) {
    return GestureDetector(
      onTap:
          () => Navigator.push(
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
          child: Text(
            'Admin Panel',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
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

}

// ── Video Thumbnail Widget ─────────────────────────────────────────────────
// ── Endless challenges grid card ─────────────────────────────────────────────
class _EndlessChallengeCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final String? categoryName;

  const _EndlessChallengeCard({required this.data, required this.categoryName});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    final thumbnailUrl = data['thumbnailUrl'] as String? ?? '';
    final challengeId = data['id'] as String? ?? '';
    final instructions = data['instructions'] as String? ?? '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            title: title,
            instructions: instructions,
            videoUrl: videoUrl,
            challengeId: challengeId,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoThumbnailWidget(videoUrl: videoUrl, thumbnailUrl: thumbnailUrl),
            Positioned(
              top: 6,
              left: 6,
              child: CategoryIconBadge(categoryName: categoryName),
            ),
          ],
        ),
      ),
    );
  }
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
    if (mounted)
      setState(() {
        _pending = p;
        _checked = true;
      });
  }

  Future<void> _retry() async {
    final p = _pending;
    if (p == null) return;
    setState(() => _dismissed = true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => PreviewScreen(
              videoPath: p.videoPath,
              challengeId: p.challengeId,
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
      builder:
          (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF15122A),
            title: const Text(
              'Discard this video?',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'This video hasn\'t been uploaded yet. Discarding it means it '
              'won\'t be submitted and you won\'t earn any Aura points for it.',
              style: TextStyle(color: AppColors.textMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Keep it',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Discard',
                  style: TextStyle(color: Colors.redAccent),
                ),
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
    if (!_checked || _pending == null || _dismissed)
      return const SizedBox.shrink();
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
