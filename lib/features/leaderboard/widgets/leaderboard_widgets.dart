import 'package:flutter/material.dart';

import '../../../shared/theme/app_colors.dart';
import '../../../shared/widgets/video_thumbnail_widget.dart';

// The redesigned Leaderboard (client's pick, 26 Nov 2026): option A's podium for
// Global, option B's challenge cards for the Challenge tab.

const lbAccent = Color(0xFF7B2CBF);
const lbCard = Color(0xFF12101E);
const lbGold = Color(0xFFF5C451);
const lbSilver = Color(0xFFC9D1E0);
const lbBronze = Color(0xFFE09A5B);
final lbLine = Colors.white.withValues(alpha: 0.08);

String lbCompact(int n) {
  String one(double v) =>
      v >= 10
          ? v.toStringAsFixed(0)
          : v.toStringAsFixed(1).replaceAll('.0', '');
  if (n >= 1000000) return '${one(n / 1000000)}M';
  if (n >= 1000) return '${one(n / 1000)}K';
  return '$n';
}

String lbThousands(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// Rounded search field with a clear button.
class LbSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const LbSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder:
          (_, value, __) => TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            cursorColor: lbAccent,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textFaint,
                fontSize: 13.5,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: Colors.white38,
                size: 20,
              ),
              suffixIcon:
                  value.text.isEmpty
                      ? null
                      : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white38,
                          size: 18,
                        ),
                        onPressed: onClear,
                      ),
              isDense: true,
              filled: true,
              fillColor: lbCard,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: lbLine),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: BorderSide(color: lbLine),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(color: lbAccent),
              ),
            ),
          ),
    );
  }
}

class LbChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const LbChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color:
              selected
                  ? lbAccent.withValues(alpha: 0.35)
                  : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                selected
                    ? const Color(0xFFC4A6FF).withValues(alpha: 0.5)
                    : lbLine,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFFD6D0EA),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// "⇅ Most Aura": shows the current sort; tap to pick another.
class LbSortButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const LbSortButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.swap_vert_rounded,
              color: Color(0xFFC4A6FF),
              size: 16,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFC4A6FF),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet listing sort options; returns the picked value.
Future<T?> showLbSortSheet<T>(
  BuildContext context, {
  required List<(T, String)> options,
  required T current,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: const Color(0xFF14121F),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder:
        (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sort by',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              for (final (value, label) in options)
                ListTile(
                  title: Text(
                    label,
                    style: TextStyle(
                      color:
                          value == current ? Colors.white : AppColors.textMuted,
                      fontWeight:
                          value == current ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  trailing:
                      value == current
                          ? const Icon(
                            Icons.check_rounded,
                            color: Color(0xFFC4A6FF),
                          )
                          : null,
                  onTap: () => Navigator.pop(ctx, value),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
  );
}

class LbAvatar extends StatelessWidget {
  final String name;
  final String avatarUrl;
  final double size;
  final Color? ring;
  final Color background;

  const LbAvatar({
    super.key,
    required this.name,
    this.avatarUrl = '',
    this.size = 34,
    this.ring,
    this.background = const Color(0xFF2A2340),
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'U';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: background,
        border: ring == null ? null : Border.all(color: ring!, width: 2),
        boxShadow:
            ring == null
                ? null
                : [
                  BoxShadow(
                    color: ring!.withValues(alpha: 0.35),
                    blurRadius: 14,
                  ),
                ],
        image:
            avatarUrl.isEmpty
                ? null
                : DecorationImage(
                  image: NetworkImage(avatarUrl),
                  fit: BoxFit.cover,
                ),
      ),
      alignment: Alignment.center,
      child:
          avatarUrl.isEmpty
              ? Text(
                initial,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: size * 0.38,
                ),
              )
              : null,
    );
  }
}

String lbDisplayName(Map<String, dynamic> e) {
  final n = (e['name'] as String? ?? '').trim();
  return n.isEmpty ? 'User' : n;
}

/// Gen Z rank sticker (client's pick P2, 26 Nov 2026): tilted "#1 GOAT 🐐",
/// "#2 SLAY", "#3 W" instead of a crown.
class LbSticker extends StatelessWidget {
  final int place;

  const LbSticker({super.key, required this.place});

  static const _labels = {1: '#1 GOAT 🐐', 2: '#2 SLAY', 3: '#3 W'};
  static const _colors = {1: lbGold, 2: lbSilver, 3: lbBronze};
  static const _tilt = {1: -0.08, 2: -0.1, 3: 0.08};

  @override
  Widget build(BuildContext context) {
    final color = _colors[place] ?? lbSilver;
    return Transform.rotate(
      angle: _tilt[place] ?? 0,
      child: Container(
        key: Key('podium-sticker-$place'),
        padding: EdgeInsets.symmetric(
          horizontal: place == 1 ? 10 : 8,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 12),
          ],
        ),
        child: Text(
          _labels[place] ?? '#$place',
          style: TextStyle(
            fontFamily: 'ClashDisplay',
            fontWeight: FontWeight.w600,
            fontSize: place == 1 ? 13 : 11.5,
            wordSpacing: 2.5,
            color: const Color(0xFF15100A),
          ),
        ),
      ),
    );
  }
}

/// The top three on a podium: 2nd on the left, 1st in the middle, 3rd right,
/// each with its sticker.
class LbPodium extends StatelessWidget {
  final List<Map<String, dynamic>> top;
  final String? myId;
  final void Function(Map<String, dynamic>)? onTap;

  const LbPodium({super.key, required this.top, this.myId, this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget place(int index, double height, Color color) {
      if (index >= top.length) return const Expanded(child: SizedBox());
      final e = top[index];
      final isMe = e['id'] == myId;
      final name = isMe ? 'You' : lbDisplayName(e);
      return Expanded(
        child: GestureDetector(
          onTap: onTap == null || isMe ? null : () => onTap!(e),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LbSticker(place: index + 1),
              const SizedBox(height: 6),
              LbAvatar(
                name: lbDisplayName(e),
                avatarUrl: e['avatar'] as String? ?? '',
                size: index == 0 ? 56 : 46,
                ring: [lbGold, lbSilver, lbBronze][index],
                background:
                    index == 0
                        ? const Color(0xFF553A12)
                        : const Color(0xFF33334A),
              ),
              const SizedBox(height: 6),
              Container(
                key: Key('podium-${index + 1}'),
                height: height,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: lbCard,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                    bottom: Radius.circular(8),
                  ),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0.14), lbCard],
                  ),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      lbCompact(e['score'] as int? ?? 0),
                      style: const TextStyle(
                        fontFamily: 'ClashDisplay',
                        wordSpacing: 4,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          place(1, 78, lbSilver),
          place(0, 100, lbGold),
          place(2, 64, lbBronze),
        ],
      ),
    );
  }
}

class LbPlayerRow extends StatelessWidget {
  final Map<String, dynamic> entry;
  final int rank;
  final bool isMe;
  final VoidCallback? onTap;

  /// The unit under the number: "Aura" on region boards, "score" on a challenge's.
  final String scoreLabel;

  const LbPlayerRow({
    super.key,
    required this.entry,
    required this.rank,
    required this.isMe,
    this.onTap,
    this.scoreLabel = 'Aura',
  });

  @override
  Widget build(BuildContext context) {
    final username = entry['username'] as String? ?? '';
    final medal = switch (rank) {
      1 => lbGold,
      2 => lbSilver,
      3 => lbBronze,
      _ => null,
    };
    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isMe ? lbAccent.withValues(alpha: 0.16) : lbCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? const Color(0xFFC4A6FF).withValues(alpha: 0.5) : lbLine,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: medal ?? (isMe ? Colors.white : AppColors.textMuted),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 6),
          LbAvatar(
            name: lbDisplayName(entry),
            avatarUrl: entry['avatar'] as String? ?? '',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '${lbDisplayName(entry)} · You' : lbDisplayName(entry),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (username.isNotEmpty)
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textFaint,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                lbCompact(entry['score'] as int? ?? 0),
                style: TextStyle(
                  fontFamily: 'ClashDisplay',
                  wordSpacing: 4,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: medal ?? Colors.white,
                ),
              ),
              Text(
                scoreLabel,
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(onTap: onTap, child: row);
  }
}

/// Pinned above the nav: the viewer's own rank, however far down they are.
class LbYouBar extends StatelessWidget {
  final Map<String, dynamic> me;
  final String name;
  final String avatarUrl;
  final String periodLabel;
  final String scoreLabel;

  const LbYouBar({
    super.key,
    required this.me,
    required this.name,
    this.avatarUrl = '',
    required this.periodLabel,
    this.scoreLabel = 'Aura',
  });

  @override
  Widget build(BuildContext context) {
    final rank = (me['rank'] as num?)?.toInt();
    final score = (me['score'] as num?)?.toInt() ?? 0;
    final gapToFirst = (me['gapToFirst'] as num?)?.toInt() ?? 0;
    final String line;
    if (rank == null) {
      line = 'Farm some aura $periodLabel to get ranked ✦';
    } else if (rank == 1) {
      line = "#1 — you're the GOAT 🐐";
    } else {
      line =
          scoreLabel == 'Aura'
              ? '${lbThousands(gapToFirst)} Aura to #1 — lock in'
              : '${lbThousands(gapToFirst)} pts to #1 — lock in';
    }
    return Container(
      key: const Key('leaderboard-you-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFC4A6FF).withValues(alpha: 0.55),
        ),
        gradient: const LinearGradient(
          colors: [Color(0xFF3A1866), Color(0xFF1A0F30)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              rank == null ? '–' : '$rank',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 6),
          LbAvatar(name: name, avatarUrl: avatarUrl, background: lbAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD9CCF5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                lbCompact(score),
                style: const TextStyle(
                  fontFamily: 'ClashDisplay',
                  wordSpacing: 4,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
              Text(
                scoreLabel,
                style: const TextStyle(color: Color(0xFFD9CCF5), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One challenge on the Challenge tab: thumbnail, your rank, its leader and participants.
class LbChallengeCard extends StatelessWidget {
  final Map<String, dynamic> challenge;
  final VoidCallback onTap;

  const LbChallengeCard({
    super.key,
    required this.challenge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final title = challenge['title'] as String? ?? '';
    final myRank = (challenge['myRank'] as num?)?.toInt();
    final participants = (challenge['participants'] as num?)?.toInt() ?? 0;
    final leader =
        challenge['leader'] is Map ? challenge['leader'] as Map : null;
    final leaderName = (leader?['displayName'] as String? ?? '').trim();
    final people = '$participants participant${participants == 1 ? '' : 's'}';
    final line =
        leader == null
            ? (participants == 0 ? 'No scores yet · be first' : people)
            : '🐐 ${leaderName.isEmpty ? 'User' : leaderName} · ${leader['score']} · $people';

    return GestureDetector(
      key: Key('challenge-board-${challenge['_id']}'),
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: lbCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: lbLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumbnailWidget(
                    videoUrl: challenge['videoUrl'] as String? ?? '',
                    thumbnailUrl: challenge['thumbnailUrl'] as String? ?? '',
                    fit: BoxFit.cover,
                  ),
                  if (myRank != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: lbGold.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'You #$myRank',
                          style: const TextStyle(
                            color: lbGold,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget lbEmpty(
  String title,
  String subtitle, {
  IconData icon = Icons.emoji_events_outlined,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 52),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textFaint, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

/// One choice in a region / time picker sheet.
class LbOption<T> {
  final T value;
  final String emoji;
  final String title;
  final String subtitle;
  final bool enabled;

  const LbOption(
    this.value,
    this.emoji,
    this.title,
    this.subtitle, {
    this.enabled = true,
  });
}

/// A glass pill showing the current choice ("🌍 Global ▾"); tap to pick
/// another (client, 26 Nov 2026: choose region and time, no sorting).
class LbSelectorPill extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const LbSelectorPill({
    super.key,
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            colors: [
              lbAccent.withValues(alpha: 0.30),
              const Color(0xFF2F7BFF).withValues(alpha: 0.12),
            ],
          ),
          border: Border.all(
            color: const Color(0xFFC4A6FF).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFFC4A6FF),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet of option cards; returns the picked value.
Future<T?> showLbOptionSheet<T>(
  BuildContext context, {
  required String title,
  required List<LbOption<T>> options,
  required T current,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: const Color(0xFF110F1C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder:
        (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'ClashDisplay',
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                    wordSpacing: 4.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                for (final o in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      key: Key('lb-option-${o.value}'),
                      onTap:
                          o.enabled ? () => Navigator.pop(ctx, o.value) : null,
                      child: Opacity(
                        opacity: o.enabled ? 1 : 0.45,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color:
                                o.value == current
                                    ? lbAccent.withValues(alpha: 0.22)
                                    : lbCard,
                            border: Border.all(
                              color:
                                  o.value == current
                                      ? const Color(
                                        0xFFC4A6FF,
                                      ).withValues(alpha: 0.6)
                                      : lbLine,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  o.emoji,
                                  style: const TextStyle(fontSize: 19),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      o.title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      o.subtitle,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (o.value == current)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFFC4A6FF),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
  );
}

/// Region choices: Global, the viewer's country, the viewer's city.
List<LbOption<String>> lbRegionOptions(String? country, String? city) => [
  const LbOption('global', '🌍', 'Global', 'Every farmer, everywhere'),
  LbOption(
    'country',
    '🗺️',
    country ?? 'Your country',
    country == null
        ? 'Add your country in your profile first'
        : 'Who runs $country',
    enabled: country != null,
  ),
  LbOption(
    'city',
    '📍',
    city ?? 'Your city',
    city == null ? 'Add your city in your profile first' : 'The GOATs of $city',
    enabled: city != null,
  ),
];

String lbRegionEmoji(String scope) => switch (scope) {
  'country' => '🗺️',
  'city' => '📍',
  _ => '🌍',
};

String lbRegionLabel(String scope, String? country, String? city) =>
    switch (scope) {
      'country' => country ?? 'Your country',
      'city' => city ?? 'Your city',
      _ => 'Global',
    };
