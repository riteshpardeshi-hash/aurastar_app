import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/core/utils/deep_link_validation.dart';

// Regression coverage: main.dart's _handleLink used to silently return (zero
// user feedback) for any malformed or unrecognized deep link — a bad share
// link, a truncated URL, or a typo'd path just did nothing with no
// indication anything was wrong. deepLinkValidationError is the extracted
// check _handleLink now uses to decide whether to show an error snackbar.
void main() {
  test('valid challenge and referral links pass validation', () {
    expect(deepLinkValidationError(Uri.parse('https://aura.app/challenge/abc123')),
        isNull);
    expect(deepLinkValidationError(Uri.parse('https://aura.app/ref/FRIEND1')),
        isNull);
  });

  test('a link with fewer than 2 path segments is invalid', () {
    expect(deepLinkValidationError(Uri.parse('https://aura.app/challenge')),
        isNotNull);
    expect(deepLinkValidationError(Uri.parse('https://aura.app/')), isNotNull);
  });

  test('an empty challenge id is invalid', () {
    expect(deepLinkValidationError(Uri.parse('https://aura.app/challenge/')),
        isNotNull);
  });

  test('an empty or whitespace-only referral code is invalid', () {
    expect(deepLinkValidationError(Uri.parse('https://aura.app/ref/')),
        isNotNull);
    expect(deepLinkValidationError(Uri.parse('https://aura.app/ref/%20')),
        isNotNull);
  });

  test('an unrecognized link type is invalid', () {
    expect(deepLinkValidationError(Uri.parse('https://aura.app/unknown/xyz')),
        isNotNull);
  });
}
