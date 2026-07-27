import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura_app/core/models/aura_tier.dart';

void main() {
  group('auraTierForLevel', () {
    group('tier boundaries — exact minLevel', () {
      test('level 1 → Rookie', () {
        expect(auraTierForLevel(1).name, 'Rookie');
      });
      test('level 5 → Rising', () {
        expect(auraTierForLevel(5).name, 'Rising');
      });
      test('level 10 → Viral', () {
        expect(auraTierForLevel(10).name, 'Viral');
      });
      test('level 20 → Elite', () {
        expect(auraTierForLevel(20).name, 'Elite');
      });
      test('level 30 → Sigma', () {
        expect(auraTierForLevel(30).name, 'Sigma');
      });
    });

    group('between thresholds — stays at lower tier', () {
      test('level 2 stays Rookie', () {
        expect(auraTierForLevel(2).name, 'Rookie');
      });
      test('level 4 stays Rookie (one below Rising)', () {
        expect(auraTierForLevel(4).name, 'Rookie');
      });
      test('level 7 stays Rising', () {
        expect(auraTierForLevel(7).name, 'Rising');
      });
      test('level 9 stays Rising (one below Viral)', () {
        expect(auraTierForLevel(9).name, 'Rising');
      });
      test('level 15 stays Viral', () {
        expect(auraTierForLevel(15).name, 'Viral');
      });
      test('level 19 stays Viral (one below Elite)', () {
        expect(auraTierForLevel(19).name, 'Viral');
      });
      test('level 25 stays Elite', () {
        expect(auraTierForLevel(25).name, 'Elite');
      });
      test('level 29 stays Elite (one below Sigma)', () {
        expect(auraTierForLevel(29).name, 'Elite');
      });
      test('level 40 stays Sigma', () {
        expect(auraTierForLevel(40).name, 'Sigma');
      });
    });

    group('above max tier', () {
      test('level 51 stays Sigma', () {
        expect(auraTierForLevel(51).name, 'Sigma');
      });
      test('level 100 stays Sigma', () {
        expect(auraTierForLevel(100).name, 'Sigma');
      });
      test('level 999 stays Sigma', () {
        expect(auraTierForLevel(999).name, 'Sigma');
      });
    });

    group('edge cases', () {
      // level 0 is below minLevel 1 — the loop never overwrites the initial
      // result (auraTiers.first), so it returns Rookie
      test('level 0 returns Rookie (below minimum)', () {
        expect(auraTierForLevel(0).name, 'Rookie');
      });
    });

    group('return fields — Rookie at level 1', () {
      late AuraTier tier;
      setUp(() => tier = auraTierForLevel(1));

      test('minLevel is 1', () => expect(tier.minLevel, 1));
      test('unlock is Generic coupons', () => expect(tier.unlock, 'Generic coupons'));
      test('color is grey', () => expect(tier.color, const Color(0xFF9E9E9E)));
    });

    group('return fields — Sigma at level 30', () {
      late AuraTier tier;
      setUp(() => tier = auraTierForLevel(30));

      test('minLevel is 30', () => expect(tier.minLevel, 30));
      test('unlock is Invite-only drops', () => expect(tier.unlock, 'Invite-only drops'));
      test('color is pink', () => expect(tier.color, const Color(0xFFE91E63)));
    });
  });

  group('nextAuraTier', () {
    test('level 1 → Rising (minLevel 5)', () {
      final next = nextAuraTier(1);
      expect(next?.name, 'Rising');
      expect(next?.minLevel, 5);
    });
    test('level 4 → Rising (one below threshold)', () {
      expect(nextAuraTier(4)?.name, 'Rising');
    });
    test('level 5 → Viral (minLevel 10)', () {
      final next = nextAuraTier(5);
      expect(next?.name, 'Viral');
      expect(next?.minLevel, 10);
    });
    test('level 9 → Viral (one below threshold)', () {
      expect(nextAuraTier(9)?.name, 'Viral');
    });
    test('level 10 → Elite', () => expect(nextAuraTier(10)?.name, 'Elite'));
    test('level 19 → Elite (one below threshold)', () => expect(nextAuraTier(19)?.name, 'Elite'));
    test('level 20 → Sigma', () => expect(nextAuraTier(20)?.name, 'Sigma'));
    test('level 29 → Sigma (one below threshold)', () => expect(nextAuraTier(29)?.name, 'Sigma'));
    test('level 30 → null (already at top tier)', () => expect(nextAuraTier(30), isNull));
    test('level 100 → null (above top tier)', () => expect(nextAuraTier(100), isNull));
  });

  group('auraTierForName', () {
    test('maps each backend tier string to the matching AuraTier', () {
      expect(auraTierForName('rookie').name, 'Rookie');
      expect(auraTierForName('rising').name, 'Rising');
      expect(auraTierForName('viral').name, 'Viral');
      expect(auraTierForName('elite').name, 'Elite');
      expect(auraTierForName('sigma').name, 'Sigma');
    });

    test('is case-insensitive', () {
      expect(auraTierForName('SIGMA').name, 'Sigma');
    });

    test('falls back to Rookie for null or unrecognized input', () {
      expect(auraTierForName(null).name, 'Rookie');
      expect(auraTierForName('legendary').name, 'Rookie');
    });
  });
}
