import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// True if [error] represents the user cancelling/dismissing the native
/// Apple sign-in sheet, rather than a genuine failure — mirrors how
/// GoogleSignIn().signIn() returns null on cancel instead of throwing.
bool isAppleSignInCancelled(Object error) =>
    error is SignInWithAppleAuthorizationException &&
    error.code == AuthorizationErrorCode.canceled;
