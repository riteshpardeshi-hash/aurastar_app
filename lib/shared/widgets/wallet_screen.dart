import 'package:flutter/material.dart';
import '../../core/services/auth_api_service.dart';
import '../../core/utils/wallet_today_total.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  final _api = AuthApiService();
  bool _loading = true;
  String? _error;
  int _balance = 0;
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchAuraBalance(),
        _api.fetchAuraHistory(limit: 50),
      ]);
      setState(() {
        _balance = results[0] as int;
        _transactions = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Failed to load wallet.';
        _loading = false;
      });
    }
  }

  int get _todayTotal => sumTodayTransactions(_transactions);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Aura Wallet'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: Colors.white54)),
                )
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: Column(
                    children: [
                      _buildBalanceCard(),
                      Expanded(child: _buildTransactionList()),
                    ],
                  ),
                ),
    );
  }

  Widget _buildBalanceCard() {
    final todayTotal = _todayTotal;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0533), Color(0xFF3A1C71)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(color: _accent.withValues(alpha: 0.25), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total Auras',
                  style: TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                '$_balance',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: todayTotal >= 0
                      ? Colors.greenAccent.withValues(alpha: 0.12)
                      : Colors.redAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: todayTotal >= 0
                        ? Colors.greenAccent.withValues(alpha: 0.3)
                        : Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  todayTotal >= 0 ? '+$todayTotal today' : '$todayTotal today',
                  style: TextStyle(
                    color: todayTotal >= 0 ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.auto_awesome_rounded, color: _accent, size: 44),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.account_balance_wallet_outlined, color: Colors.white24, size: 52),
          SizedBox(height: 14),
          Text('No transactions yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 15)),
          SizedBox(height: 6),
          Text('Complete a challenge to earn Auras',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Text(
            'Transaction History',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _transactions.length,
            itemBuilder: (context, i) => _buildTile(_transactions[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(Map<String, dynamic> tx) {
    final amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final type = tx['type'] as String? ?? '';
    final description = tx['description'] as String? ?? 'Transaction';
    final isPositive = amount >= 0;

    IconData icon;
    Color iconColor;
    switch (type) {
      case 'challenge_score':
        icon = Icons.star_rounded;
        iconColor = _accent;
        break;
      case 'daily_score_replacement':
        icon = Icons.swap_vert_rounded;
        iconColor = Colors.orange;
        break;
      case 'deleted_video_deduction':
        icon = Icons.delete_outline_rounded;
        iconColor = Colors.redAccent;
        break;
      case 'level_unlock_bonus':
        icon = Icons.arrow_upward_rounded;
        iconColor = const Color(0xFFFFD700);
        break;
      case 'referral_join_bonus':
      case 'new_user_referral_bonus':
        icon = Icons.group_add_outlined;
        iconColor = Colors.tealAccent;
        break;
      default:
        icon = Icons.account_balance_wallet_outlined;
        iconColor = Colors.white54;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isPositive ? '+$amount' : '$amount',
            style: TextStyle(
              color: isPositive ? Colors.greenAccent : Colors.redAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
