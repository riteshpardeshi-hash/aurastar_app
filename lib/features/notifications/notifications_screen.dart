import 'package:flutter/material.dart';
import '../../core/services/notifications_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _bg = Color(0xFF000000);
  static const _accent = Color(0xFF7B2CBF);

  final _service = NotificationsService();

  bool _loading = true;
  bool _loadingMore = false;
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final result = await _service.fetchNotifications(page: 1, limit: 20);
    if (!mounted) return;
    setState(() {
      _items = (result['items'] as List).cast<Map<String, dynamic>>();
      _page = result['page'] as int;
      _totalPages = result['totalPages'] as int;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _page >= _totalPages) return;
    setState(() => _loadingMore = true);
    final result = await _service.fetchNotifications(page: _page + 1, limit: 20);
    if (!mounted) return;
    setState(() {
      _items.addAll((result['items'] as List).cast<Map<String, dynamic>>());
      _page = result['page'] as int;
      _totalPages = result['totalPages'] as int;
      _loadingMore = false;
    });
  }

  Future<void> _markAllRead() async {
    setState(() {
      for (final n in _items) {
        n['isRead'] = true;
      }
    });
    try {
      await _service.markAllRead();
    } catch (_) {}
  }

  Future<void> _markRead(Map<String, dynamic> n) async {
    if (n['isRead'] == true) return;
    setState(() => n['isRead'] = true);
    try {
      await _service.markRead(n['id'] as String);
    } catch (_) {}
  }

  Future<void> _delete(Map<String, dynamic> n) async {
    setState(() => _items.remove(n));
    try {
      await _service.deleteNotification(n['id'] as String);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: _items.isEmpty ? null : _markAllRead,
            child: const Text('Mark all read',
                style: TextStyle(color: Color(0xFFD4A8FF), fontSize: 13)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _items.isEmpty
              ? RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Icon(Icons.notifications_none_rounded,
                          color: Colors.white24, size: 56),
                      SizedBox(height: 14),
                      Text('No notifications yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 15)),
                      SizedBox(height: 6),
                      Text('We\'ll notify you about scores, stars and offers.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white24, fontSize: 12)),
                    ],
                  ),
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: RefreshIndicator(
                    color: _accent,
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: _items.length + (_loadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: _accent, strokeWidth: 2),
                            ),
                          );
                        }
                        final n = _items[i];
                        return Dismissible(
                          key: ValueKey(n['id']),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.delete_outline_rounded,
                                color: Colors.redAccent),
                          ),
                          onDismissed: (_) => _delete(n),
                          child: _NotificationTile(
                            data: n,
                            onTap: () => _markRead(n),
                          ),
                        );
                      },
                    ),
                  ),
                ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _NotificationTile({required this.data, required this.onTap});

  static const _accent = Color(0xFF7B2CBF);
  static const _card = Color(0xFF0E0E1A);

  @override
  Widget build(BuildContext context) {
    final isRead = data['isRead'] as bool? ?? false;
    final message = data['message'] as String? ?? '';
    final type = data['type'] as String? ?? 'general';
    final time = _timeAgo(data['createdAt']);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isRead ? _card : _accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRead ? Colors.white10 : _accent.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _iconColor(type).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(_iconFor(type), color: _iconColor(type), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(time,
                        style:
                            const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ],
              ),
            ),
            if (!isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, left: 8),
                decoration:
                    const BoxDecoration(color: _accent, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'star':
        return Icons.star_rounded;
      case 'rank':
        return Icons.emoji_events_rounded;
      case 'offer':
        return Icons.local_offer_rounded;
      case 'referral':
        return Icons.group_add_rounded;
      case 'approved':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _iconColor(String type) {
    switch (type) {
      case 'star':
        return const Color(0xFFFFD700);
      case 'rank':
        return const Color(0xFFFF9800);
      case 'offer':
        return Colors.greenAccent;
      case 'referral':
        return Colors.tealAccent;
      case 'approved':
        return Colors.greenAccent;
      case 'rejected':
        return Colors.redAccent;
      default:
        return _accent;
    }
  }

  String _timeAgo(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
