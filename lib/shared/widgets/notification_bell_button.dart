import 'package:flutter/material.dart';
import '../../core/services/notifications_service.dart';
import '../../features/notifications/notifications_screen.dart';

class NotificationBellButton extends StatefulWidget {
  /// Passed straight through to the underlying [IconButton]. Left null for the
  /// default 48px AppBar sizing (home feed); the Dashboard header overrides
  /// them so the bell tucks against the page margin and lines up with the
  /// name/Aura stack beside it.
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;
  final AlignmentGeometry? alignment;

  const NotificationBellButton({
    super.key,
    this.padding,
    this.constraints,
    this.alignment,
  });

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _service = NotificationsService();
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _service.fetchUnreadCount().then((count) {
      if (mounted) setState(() => _unread = count);
    });
  }

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    if (!mounted) return;
    final count = await _service.fetchUnreadCount();
    if (mounted) setState(() => _unread = count);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: widget.padding,
      constraints: widget.constraints,
      alignment: widget.alignment ?? Alignment.center,
      // Flutter's Badge anchors the count past the top-right corner of the
      // glyph (offset nudges it further clear), so it never lands on top of
      // the bell and hides it the way the old hand-placed Stack did.
      icon: Badge(
        isLabelVisible: _unread > 0,
        offset: const Offset(4, -6),
        backgroundColor: const Color(0xFF7B2CBF),
        largeSize: 14,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 7.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        child: const Icon(Icons.notifications_outlined, color: Colors.white70),
      ),
      onPressed: _open,
    );
  }
}
