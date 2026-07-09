import 'package:flutter/material.dart';

const String kChallengeBaseUrl = 'https://aura-app-efae1.web.app/challenge';

class AchievementCardView extends StatelessWidget {
  final String challengeTitle;
  final String challengeId;
  final int auraPoints;
  final String username;
  final String? city;
  final int? cityRank;

  const AchievementCardView({
    super.key,
    required this.challengeTitle,
    required this.challengeId,
    required this.auraPoints,
    required this.username,
    this.city,
    this.cityRank,
  });

  @override
  Widget build(BuildContext context) {
    const cardWidth = 268.0;
    const textColWidth = cardWidth * 0.58;

    return SizedBox(
      width: cardWidth,
      child: AspectRatio(
        aspectRatio: 810 / 1231,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset('assets/images/flex/Asset 111.png', fit: BoxFit.cover),
            ),
            Image.asset('assets/images/flex/Asset 112.png', fit: BoxFit.fill),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset('assets/images/flex/Asset 113.png', height: 16),
                  const Spacer(flex: 3),
                  SizedBox(
                    width: textColWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          challengeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        Image.asset('assets/images/flex/Asset 115.png', height: 20, alignment: Alignment.centerLeft),
                        const SizedBox(height: 18),
                        Image.asset('assets/images/flex/Asset 116.png', height: 13, alignment: Alignment.centerLeft),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '+$auraPoints',
                              style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1),
                            ),
                            const SizedBox(width: 6),
                            Image.asset('assets/images/flex/Asset 118.png', height: 22),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Image.asset('assets/images/flex/Asset 119.png', height: 12, alignment: Alignment.centerLeft),
                        const SizedBox(height: 2),
                        const Text(
                          'Beat This?',
                          style: TextStyle(color: Color(0xFFA700FF), fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        AspectRatio(
                          aspectRatio: 303 / 63,
                          child: Image.asset('assets/images/flex/Asset 123.png', fit: BoxFit.fill),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 3),
                  Text(
                    '@$username',
                    style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                  if (cityRank != null && city != null && city!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF54A0FF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF54A0FF).withValues(alpha: 0.40)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_city_rounded, color: Color(0xFF54A0FF), size: 11),
                          const SizedBox(width: 4),
                          Text(
                            '#$cityRank in $city',
                            style: const TextStyle(
                              color: Color(0xFF54A0FF),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
