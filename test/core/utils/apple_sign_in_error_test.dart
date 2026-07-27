import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'package:aura_app/core/utils/apple_sign_in_error.dart';

// Regression coverage: dismissing the native Apple sign-in sheet throws
// SignInWithAppleAuthorizationException(code: canceled) instead of returning
// null the way GoogleSignIn().signIn() does on cancel. auth_choice_screen.dart
// used to catch every error the same way, so a user who simply backed out of
// the Apple sheet saw "Apple sign-in failed. Please try again." right next
// to Google's cancel path, which handles this silently.
void main() {
  test('a canceled Apple authorization is recognized as a cancel', () {
    expect(
      isAppleSignInCancelled(const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.canceled,
        message: 'The user canceled the authorization attempt',
      )),
      isTrue,
    );
  });

  test('a genuine Apple authorization failure is not treated as a cancel', () {
    expect(
      isAppleSignInCancelled(const SignInWithAppleAuthorizationException(
        code: AuthorizationErrorCode.failed,
        message: 'The authorization attempt failed',
      )),
      isFalse,
    );
  });

  test('an unrelated error is never treated as a cancel', () {
    expect(isAppleSignInCancelled(Exception('No ID token from Google')),
        isFalse);
  });
}
