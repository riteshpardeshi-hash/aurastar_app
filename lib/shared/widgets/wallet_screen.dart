import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key});

  static const _accent = Color(0xFF7B2CBF);
  static const _bg = Color(0xFF080810);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: Text('Not logged in', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Aura Wallet'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, userSnap) {
          final userData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
          final totalRewards = (userData['totalRewards'] as num?)?.toInt() ?? 0;

          return Column(
            children: [
              _buildBalanceCard(totalRewards, user.uid),
              Expanded(child: _buildTransactionList(user.uid)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(int totalRewards, String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('auraTransactions')
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: _todayStart())
          .snapshots(),
      builder: (context, snap) {
        final todayDocs = snap.data?.docs ?? [];
        final todayTotal = todayDocs.fold<int>(
          0,
          (acc, d) => acc + ((d.data() as Map)['amount'] as num? ?? 0).toInt(),
        );

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
                    '$totalRewards',
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
      },
    );
  }

  Widget _buildTransactionList(String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('auraTransactions')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: Colors.white24, size: 52),
                SizedBox(height: 14),
                Text('No transactions yet',
                    style: TextStyle(color: Colors.white38, fontSize: 15)),
                SizedBox(height: 6),
                Text('Complete a challenge to earn Auras',
                    style: TextStyle(color: Colors.white24, fontSize: 12)),
              ],
            ),
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
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final tx = docs[i].data() as Map<String, dynamic>;
                  return _buildTile(tx);
                },
              ),
            ),
          ],
        );
      },
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

  Timestamp _todayStart() {
    final now = DateTime.now();
    return Timestamp.fromDate(DateTime(now.year, now.month, now.day));
  }
}
