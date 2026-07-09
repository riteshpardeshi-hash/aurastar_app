import 'package:flutter/material.dart';
import '../../../core/services/creator_account_service.dart';
import '../../../core/services/creators_service.dart';
import '../../explore/screens/creator_profile_screen.dart';

enum FollowListMode { followers, following }

/// The `PaginatedFollowList` API only returns bare ids
/// (`followerId`/`followingId`/`followingType`) — no display name or avatar.
/// This screen best-effort enriches each entry via `CreatorsService` when
/// `followingType` is `creator`; brand follows and non-creator followers
/// fall back to a generic row since there's no lookup for them yet.
class CreatorFollowListScreen extends StatefulWidget {
  final FollowListMode mode;

  const CreatorFollowListScreen({super.key, required this.mode});

  @override
  State<CreatorFollowListScreen> createState() => _CreatorFollowListScreenState();
}

class _CreatorFollowListScreenState extends State<CreatorFollowListScreen> {
  static const _bg     = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);

  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  bool get _isFollowers => widget.mode == FollowListMode.followers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = CreatorAccountService();
    final entries = _isFollowers
        ? await service.fetchFollowers(limit: 50)
        : await service.fetchFollowing(limit: 50);

    final enriched = await Future.wait(entries.map((e) async {
      final id = (_isFollowers ? e['followerId'] : e['followingId']) as String? ?? '';
      final type = e['followingType'] as String?;
      Map<String, dynamic>? creator;
      // Followers have no `followingType` (that's only set on the following
      // side); try the creator lookup regardless since most follow activity
      // on this platform is creator-to-creator.
      if (!_isFollowers || type == null || type == 'creator') {
        final raw = await CreatorsService().fetchCreator(id);
        if (raw != null) creator = normaliseCreator(raw);
      }
      return {
        'id': id,
        'type': type ?? 'creator',
        'creator': creator,
      };
    }));

    if (!mounted) return;
    setState(() {
      _rows = enriched;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_isFollowers ? 'Followers' : 'Following',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, fontFamily: 'ClashDisplay')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _rows.isEmpty
              ? Center(
                  child: Text(_isFollowers ? 'No followers yet' : 'Not following anyone yet',
                      style: const TextStyle(color: Colors.white54)),
                )
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _rows.length,
                    itemBuilder: (_, i) => _row(_rows[i]),
                  ),
                ),
    );
  }

  Widget _row(Map<String, dynamic> row) {
    final creator = row['creator'] as Map<String, dynamic>?;
    final isBrand = row['type'] == 'brand';
    final name = creator?['displayName'] as String? ?? (isBrand ? 'Brand' : 'Player');
    final username = creator?['username'] as String? ?? '';
    final avatar = creator?['avatar'] as String? ?? '';

    return GestureDetector(
      onTap: creator == null
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CreatorProfileScreen(creatorId: row['id'] as String)),
              ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF100A20),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _accent.withValues(alpha: 0.20),
              backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
              child: avatar.isEmpty
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  if (username.isNotEmpty)
                    Text('@$username', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),
            if (creator == null)
              const Icon(Icons.info_outline_rounded, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }
}
