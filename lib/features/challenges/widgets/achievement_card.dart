import 'package:flutter/material.dart';

const String kChallengeBaseUrl = 'https://aura-app-efae1.web.app/challenge';

class AchievementCardView extends StatelessWidget {
  final String challengeTitle;
  final String challengeId;
  final int auraPoints;
  final String username;

  const AchievementCardView({
    super.key,
    required this.challengeTitle,
    required this.challengeId,
    required this.auraPoints,
    required this.username,
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
                            decoration: TextDecoration.none,
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
                              style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1, decoration: TextDecoration.none),
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
                          style: TextStyle(color: Color(0xFFA700FF), fontSize: 17, fontWeight: FontWeight.w800, decoration: TextDecoration.none),
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
                    style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600, decoration: TextDecoration.none),
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
