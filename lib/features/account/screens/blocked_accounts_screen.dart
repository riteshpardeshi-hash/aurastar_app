import 'package:flutter/material.dart';

import '../../../core/services/safety_service.dart';
import '../../../core/services/screen_cache.dart';
import '../../../shared/theme/app_colors.dart';

/// Settings → Blocked accounts: everyone this user blocked (backend ADR 117), with Unblock.
/// Unblocking doesn't restore follows or friendship — those were removed by the block.
class BlockedAccountsScreen extends StatefulWidget {
  final SafetyService? service;
  const BlockedAccountsScreen({super.key, this.service});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  static const _bg = Color(0xFF080810);
  static const _accent = Color(0xFF7B2CBF);
  late final SafetyService _service = widget.service ?? SafetyService();
  List<BlockedAccount>? _accounts;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.blocked();
      if (mounted) setState(() => _accounts = list);
    } catch (e) {
      if (mounted) setState(() => _error = e is SafetyException ? e.message : "Couldn't load blocked accounts.");
    }
  }

  Future<void> _unblock(BlockedAccount a) async {
    setState(() => _busy.add(a.id));
    try {
      await _service.unblock(a.id);
      ScreenCache.clear(); // their content can show again
      if (!mounted) return;
      setState(() => _accounts = _accounts?.where((x) => x.id != a.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Unblocked ${a.displayName}. Follow them again if you want to.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is SafetyException ? e.message : "Couldn't unblock. Please try again."),
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _accounts;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Blocked accounts', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.textMuted)))
          : accounts == null
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : accounts.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  "You haven't blocked anyone. Block an account from the ⋯ menu on their profile or video.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14, height: 1.5),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: accounts.length,
              separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
              itemBuilder: (_, i) {
                final a = accounts[i];
                return ListTile(
                  key: Key('blocked-${a.id}'),
                  leading: CircleAvatar(
                    backgroundColor: _accent.withValues(alpha: 0.3),
                    backgroundImage: a.avatar != null ? NetworkImage(a.avatar!) : null,
                    child: a.avatar == null
                        ? Text(a.displayName.isEmpty ? '?' : a.displayName[0].toUpperCase(), style: const TextStyle(color: Colors.white))
                        : null,
                  ),
                  title: Text(a.displayName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [if (a.profileName != null) '@${a.profileName}', if (a.role == 'brand') 'Brand', if (a.role == 'creator') 'Creator'].join(' · '),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  trailing: OutlinedButton(
                    key: Key('unblock-${a.id}'),
                    onPressed: _busy.contains(a.id) ? null : () => _unblock(a),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(_busy.contains(a.id) ? '…' : 'Unblock'),
                  ),
                );
              },
            ),
    );
  }
}
