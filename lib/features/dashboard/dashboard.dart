import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/api_client.dart';
import '../../core/services/auth_api_service.dart';
import '../../core/services/connectivity_probe.dart';
import '../../core/services/challenges_service.dart';
import '../../core/services/home_service.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/services/videos_service.dart';
import '../../core/models/aura_tier.dart';
import '../../core/utils/streak_date.dart';
import '../../shared/widgets/video_thumbnail_widget.dart';
import '../../shared/widgets/thumbnail_stats_badge.dart';
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
import '../../shared/widgets/screen_skeleton.dart';

int profileAutoRetryDelaySeconds(int attemptNumber) {
  return (8 * (1 << (attemptNumber - 1))).clamp(0, 60);
}

class Dashboard extends StatefulWidget {
  final bool embeddedInShell;

  const Dashboard({super.key, this.embeddedInShell = false});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  String? _lastKnownTier;
  bool _atRiskAlertShown = false;

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

  int _autoRetryCount = 0;
  static const _maxAutoRetries = 4;
  Timer? _autoRetryTimer;

  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  @override
  void initState() {
    super.initState();
    _profilePollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      final uid = _profileUserId;
      if (uid != null && _autoRetryTimer == null) _loadProfile(uid);
    });
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
      if (isNetworkError(e) && !(await ConnectivityProbe.confirmUnreachable())) {
        return _fetchDashboardProfileOnce(userId);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _fetchDashboardProfileOnce(
      String userId) async {
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
    final serverPoints =
        (profile['auraPoints'] as num?)?.toInt() ??
        (profile['totalRewards'] as num?)?.toInt() ??
        0;
    await VideosService.hydrate();
    final points = VideosService.adjustBalanceForDeletedVideos(serverPoints);
    // Server-computed and authoritative — do not recompute level/tier from
    // `points` locally (see aura_tier.dart's auraTierForName).
    final level = (profile['level'] as num?)?.toInt() ?? 1;
    final tierName = profile['tier'] as String?;
    final streakDay = (streak?['currentStreak'] as num?)?.toInt() ?? 0;
    final lastStreakDate = deriveLastStreakDate(streak);
    AnalyticsService()
      ..setUserProperty('user_level', '$level')
      ..setUserProperty('account_type', role ?? 'player');

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
            level: 1,
            tierName: null,
            isAdmin: false,
            isBrand: false,
            isCreator: false,
            userId: '',
            displayName: 'Guest',
            username: '',
            photoUrl: '',
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
            body: ScreenSkeleton(),
          );
        }

        _autoRetryCount = 0;

        final data = snap.data!;
        final points = data['points'] as int;
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
          level: level,
          tierName: tierName,
          isAdmin: isAdmin,
          isBrand: isBrand,
          isCreator: isCreator,
          userId: userId,
          displayName: displayName,
          username: username,
          photoUrl: photoUrl,
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context, {
    required int points,
    required int level,
    required String? tierName,
    required bool isAdmin,
    required bool isBrand,
    required bool isCreator,
    required String userId,
    required String displayName,
    required String username,
    required String photoUrl,
  }) {
    final tier = auraTierForName(tierName, level: level);

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
          // Inside MainShell the shell owns the one shared bottom nav.
          if (!widget.embeddedInShell)
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

          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    username.isNotEmpty ? '@$username' : displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'SpaceGrotesk',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WalletScreen()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
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
                          height: 11,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$points',
                          // Clamp accessibility text scaling for this chip so
                          // a large system font can't blow the header out.
                          textScaler: MediaQuery.textScalerOf(context)
                              .clamp(maxScaleFactor: 1.2),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'SpaceGrotesk',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const NotificationBellButton(
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                  alignment: Alignment.centerRight,
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
        int participants = 0;

        if (hero != null) {
          title = hero['title'] as String? ?? title;
          videoUrl = hero['videoUrl'] as String? ?? '';
          thumbnailUrl = hero['thumbnailUrl'] as String? ?? '';
          instructions = hero['instructions'] as String? ?? '';
          challengeId = hero['id'] as String? ?? '';
          participants = hero['submissionsCount'] as int? ?? 0;
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
                              source: 'home',
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
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 4,
                      child: ThumbnailStatsBadge(participants: participants),
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
                onTap: () {
                  AnalyticsService().logExploreBrandsClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BrandsListScreen(),
                    ),
                  );
                },
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
                          final instructions =
                              data['instructions'] as String? ?? '';
                          final participants =
                              data['submissionsCount'] as int? ?? 0;
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
                                              source: 'home',
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
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: ThumbnailStatsBadge(
                                            participants: participants,
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
                              final participants =
                                  data['submissionsCount'] as int? ?? 0;
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
                                                  source: 'home',
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
                                              left: 0,
                                              right: 0,
                                              bottom: 0,
                                              child: ThumbnailStatsBadge(
                                                participants: participants,
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
                      final instructions =
                          data['instructions'] as String? ?? '';
                      final participants =
                          data['submissionsCount'] as int? ?? 0;
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
                                          source: 'home',
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
                                      left: 0,
                                      right: 0,
                                      bottom: 0,
                                      child: ThumbnailStatsBadge(
                                        participants: participants,
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
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ── Endless challenges grid ───────────────────────────────────────────────
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
                return _EndlessChallengeCard(data: data);
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
                                          source: 'home',
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

  const _EndlessChallengeCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final title = data['title'] as String? ?? '';
    final videoUrl = data['videoUrl'] as String? ?? '';
    final thumbnailUrl = data['thumbnailUrl'] as String? ?? '';
    final challengeId = data['id'] as String? ?? '';
    final instructions = data['instructions'] as String? ?? '';
    final participants = data['submissionsCount'] as int? ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallengeDetail(
            source: 'home',
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
            VideoThumbnailWidget(
              videoUrl: videoUrl,
              thumbnailUrl: thumbnailUrl,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ThumbnailStatsBadge(participants: participants),
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
              mirrored: p.mirrored,
            ),
      ),
    );
  }

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
