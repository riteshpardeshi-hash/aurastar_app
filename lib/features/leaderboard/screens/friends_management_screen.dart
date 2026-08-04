import 'package:flutter/material.dart';
import '../../../core/services/friends_service.dart';

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
    super.dispose();
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
          style: const TextStyle(color: Colors.white70),
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
        title: const Text(
          'Friends',
          style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'ClashDisplay'),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _accent,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
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

  Widget _friendsTab() {
    if (_loadingFriends) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_friends.isEmpty) {
      return _empty('No friends yet', 'Add friends from the Suggestions tab');
    }
    return RefreshIndicator(
      color: _accent,
      onRefresh: _loadFriends,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _friends.length,
        itemBuilder: (_, i) {
          final f = _friends[i];
          return _PersonRow(
            name: f['name'] as String,
            username: f['username'] as String,
            trailing: IconButton(
              icon: const Icon(Icons.person_remove_outlined, color: Colors.white38),
              onPressed: () => _removeFriend(f),
            ),
          );
        },
      ),
    );
  }

  Widget _requestsTab() {
    if (_loadingRequests) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_requests.isEmpty) {
      return _empty('No pending requests', 'Friend requests you receive show up here');
    }
    return RefreshIndicator(
      color: _accent,
      onRefresh: _loadRequests,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _requests.length,
        itemBuilder: (_, i) {
          final r = _requests[i];
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
                  icon: const Icon(Icons.cancel_outlined, color: Colors.white38),
                  onPressed: () => _respondToRequest(r, accept: false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _suggestionsTab() {
    if (_loadingSuggestions) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (_suggestions.isEmpty) {
      return _empty('No suggestions right now', 'Check back later');
    }
    return RefreshIndicator(
      color: _accent,
      onRefresh: _loadSuggestions,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _suggestions.length,
        itemBuilder: (_, i) {
          final s = _suggestions[i];
          final requested = s['requested'] == true;
          return _PersonRow(
            name: s['name'] as String,
            username: s['username'] as String,
            trailing: TextButton(
              onPressed: requested ? null : () => _sendRequest(s),
              child: Text(
                requested ? 'Requested' : 'Add',
                style: TextStyle(
                  color: requested ? Colors.white38 : _accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
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
                    color: Colors.white38, fontSize: 16, fontFamily: 'SpaceGrotesk')),
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
                        color: Colors.white38, fontSize: 11, fontFamily: 'SpaceGrotesk'),
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
