import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/core/models/aura_tier.dart';
import 'package:aura_app/core/utils/cdn_url.dart';

void main() {
  group('auraTierForLevel', () {
    test('level 1 returns Rookie', () {
      expect(auraTierForLevel(1).name, 'Rookie');
    });

    test('level 4 stays Rookie (below Rising threshold)', () {
      expect(auraTierForLevel(4).name, 'Rookie');
    });

    test('level 5 returns Rising', () {
      expect(auraTierForLevel(5).name, 'Rising');
    });

    test('level 10 returns Viral', () {
      expect(auraTierForLevel(10).name, 'Viral');
    });

    test('level 20 returns Elite', () {
      expect(auraTierForLevel(20).name, 'Elite');
    });

    test('level 30 returns Sigma', () {
      expect(auraTierForLevel(30).name, 'Sigma');
    });

    test('level 100 stays at top tier Sigma', () {
      expect(auraTierForLevel(100).name, 'Sigma');
    });
  });

  group('nextAuraTier', () {
    test('level 1 next tier is Rising at level 5', () {
      final next = nextAuraTier(1);
      expect(next?.name, 'Rising');
      expect(next?.minLevel, 5);
    });

    test('level 5 next tier is Viral at level 10', () {
      final next = nextAuraTier(5);
      expect(next?.name, 'Viral');
      expect(next?.minLevel, 10);
    });

    test('level 30 has no next tier', () {
      expect(nextAuraTier(30), isNull);
    });

    test('level 100 has no next tier', () {
      expect(nextAuraTier(100), isNull);
    });
  });

  group('cdn_url', () {
    const sampleUrl =
        'https://firebasestorage.googleapis.com/v0/b/bucket/o/file.mp4?alt=media';

    test('toCdnUrl returns original when CDN base is empty', () {
      expect(toCdnUrl(sampleUrl), sampleUrl);
    });

    test('toCdnUrl returns empty string unchanged', () {
      expect(toCdnUrl(''), '');
    });

    test('toOptimizedVideoUrl returns original when CDN base is empty', () {
      expect(toOptimizedVideoUrl(sampleUrl), sampleUrl);
    });

    test('toOptimizedVideoUrl returns empty string unchanged', () {
      expect(toOptimizedVideoUrl(''), '');
    });

    test('toThumbnailUrl returns URL unchanged', () {
      expect(toThumbnailUrl(sampleUrl), sampleUrl);
    });

    test('toThumbnailUrl returns empty string unchanged', () {
      expect(toThumbnailUrl(''), '');
    });
  });
}
