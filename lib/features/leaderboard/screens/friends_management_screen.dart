import 'package:flutter/material.dart';
import '../../../core/services/friends_service.dart';
import '../../../shared/theme/app_colors.dart';

class FriendsManagementScreen extends StatefulWidget {
  const FriendsManagementScreen({super.key});

  @override
  State<FriendsManagementScreen> createState() =>
      _FriendsManagementScreenState();
}

class _FriendsManagementScreenState extends State<FriendsManagementScreen>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  late TabController _tabs;
  final _service = FriendsService();

  List<Map<String, dynamic>> _friends = [];
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _loadingFriends = true;
  bool _loadingRequests = true;
  bool _loadingSuggestions = true;

  final _friendsSearchCtrl = TextEditingController();
  final _requestsSearchCtrl = TextEditingController();
  final _suggestionsSearchCtrl = TextEditingController();
  String _friendsQuery = '';
  String _requestsQuery = '';
  String _suggestionsQuery = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadFriends();
    _loadRequests();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _friendsSearchCtrl.dispose();
    _requestsSearchCtrl.dispose();
    _suggestionsSearchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filterByQuery(
      List<Map<String, dynamic>> list, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((p) {
      final name = (p['name'] as String? ?? '').toLowerCase();
      final username = (p['username'] as String? ?? '').toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
  }

  Future<void> _loadFriends() async {
    final raw = await _service.fetchFriends();
    if (!mounted) return;
    setState(() {
      _friends = raw.map(normaliseFriendUser).toList();
      _loadingFriends = false;
    });
  }

  Future<void> _loadRequests() async {
    final raw = await _service.fetchPendingRequests();
    if (!mounted) return;
    setState(() {
      _requests = raw.map(normaliseFriendUser).toList();
      _loadingRequests = false;
    });
  }

  Future<void> _loadSuggestions() async {
    final raw = await _service.fetchSuggestions();
    if (!mounted) return;
    setState(() {
      _suggestions = raw.map(normaliseFriendUser).toList();
      _loadingSuggestions = false;
    });
  }

  Future<void> _removeFriend(Map<String, dynamic> friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        title: const Text('Remove friend?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'You and ${friend['name']} will no longer be connected as friends.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final id = friend['id'] as String;
    final ok = await _service.removeFriend(id);
    if (ok && mounted) {
      setState(() => _friends.removeWhere((f) => f['id'] == id));
    }
  }

  Future<void> _respondToRequest(Map<String, dynamic> req,
      {required bool accept}) async {
    final requestId = req['requestId'] as String;
    final ok = await _service.respondToRequest(requestId, accept: accept);
    if (ok && mounted) {
      setState(() => _requests.removeWhere((r) => r['requestId'] == requestId));
      if (accept) _loadFriends();
    }
  }

  Future<void> _sendRequest(Map<String, dynamic> suggestion) async {
    final id = suggestion['id'] as String;
    final ok = await _service.sendRequest(id);
    if (ok && mounted) {
      setState(() {
        final i = _suggestions.indexWhere((s) => s['id'] == id);
        if (i != -1) _suggestions[i] = {..._suggestions[i], 'requested': true};
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Friends'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textFaint,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'SpaceGrotesk'),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, fontFamily: 'SpaceGrotesk'),
          tabs: [
            const Tab(text: 'Friends'),
            Tab(text: _requests.isEmpty ? 'Requests' : 'Requests (${_requests.length})'),
            const Tab(text: 'Suggestions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _friendsTab(),
          _requestsTab(),
          _suggestionsTab(),
        ],
      ),
    );
  }

  Widget _searchBar(
      TextEditingController controller, String hint, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, fontFamily: 'SpaceGrotesk'),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(
                      color: Colors.white38, fontSize: 14, fontFamily: 'SpaceGrotesk'),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                child: const Icon(Icons.close_rounded, color: Colors.white38, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  Widget _friendsTab() {
    if (_loadingFriends) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    final filtered = _filterByQuery(_friends, _friendsQuery);
    return Column(
      children: [
        _searchBar(_friendsSearchCtrl, 'Search friends',
            (v) => setState(() => _friendsQuery = v)),
        Expanded(
          child: filtered.isEmpty
              ? _empty(
                  _friends.isEmpty ? 'No friends yet' : 'No matches',
                  _friends.isEmpty
                      ? 'Add friends from the Suggestions tab'
                      : 'Try a different name or username',
                )
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _loadFriends,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final f = filtered[i];
                      return _PersonRow(
                        name: f['name'] as String,
                        username: f['username'] as String,
                        trailing: IconButton(
                          icon: const Icon(Icons.person_remove_outlined,
                              color: Colors.white38),
                          onPressed: () => _removeFriend(f),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _requestsTab() {
    if (_loadingRequests) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    final filtered = _filterByQuery(_requests, _requestsQuery);
    return Column(
      children: [
        _searchBar(_requestsSearchCtrl, 'Search requests',
            (v) => setState(() => _requestsQuery = v)),
        Expanded(
          child: filtered.isEmpty
              ? _empty(
                  _requests.isEmpty ? 'No pending requests' : 'No matches',
                  _requests.isEmpty
                      ? 'Friend requests you receive show up here'
                      : 'Try a different name or username',
                )
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _loadRequests,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final r = filtered[i];
                      return _PersonRow(
                        name: r['name'] as String,
                        username: r['username'] as String,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle, color: _accent),
                              onPressed: () => _respondToRequest(r, accept: true),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel_outlined,
                                  color: Colors.white38),
                              onPressed: () => _respondToRequest(r, accept: false),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _suggestionsTab() {
    if (_loadingSuggestions) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    final filtered = _filterByQuery(_suggestions, _suggestionsQuery);
    return Column(
      children: [
        _searchBar(_suggestionsSearchCtrl, 'Search suggestions',
            (v) => setState(() => _suggestionsQuery = v)),
        Expanded(
          child: filtered.isEmpty
              ? _empty(
                  _suggestions.isEmpty ? 'No suggestions right now' : 'No matches',
                  _suggestions.isEmpty
                      ? 'Check back later'
                      : 'Try a different name or username',
                )
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _loadSuggestions,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final s = filtered[i];
                      final requested = s['requested'] == true;
                      return _PersonRow(
                        name: s['name'] as String,
                        username: s['username'] as String,
                        trailing: TextButton(
                          onPressed: requested ? null : () => _sendRequest(s),
                          child: Text(
                            requested ? 'Requested' : 'Add',
                            style: TextStyle(
                              color: requested ? AppColors.textFaint : _accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _empty(String title, String subtitle) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, color: Colors.white24, size: 52),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 16, fontFamily: 'SpaceGrotesk')),
            const SizedBox(height: 6),
            Text(subtitle,
                style: const TextStyle(
                    color: Colors.white24, fontSize: 13, fontFamily: 'SpaceGrotesk')),
          ],
        ),
      );
}

class _PersonRow extends StatelessWidget {
  final String name;
  final String username;
  final Widget trailing;

  static const _accent = Color(0xFF7B2CBF);

  const _PersonRow({
    required this.name,
    required this.username,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: _accent.withValues(alpha: 0.25),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'SpaceGrotesk'),
                ),
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 11, fontFamily: 'SpaceGrotesk'),
                  ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
