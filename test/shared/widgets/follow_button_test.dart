import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura_app/shared/widgets/follow_button.dart';

// Regression coverage: a failed follow/unfollow used to be swallowed
// entirely by CreatorsService/BrandsService (`catch (_) { return false; }`),
// so FollowButton had no way to tell the user anything went wrong — the
// button just silently stayed on "Follow", indistinguishable from a
// successful follow that simply hadn't been tapped yet. The fix makes the
// service throw with the backend's message instead, and FollowButton now
// shows it in a SnackBar.
void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'api_access_token': 'token',
      'api_refresh_token': 'refresh',
      'api_user_id': 'user-1',
    });
  });

  testWidgets(
      'shows the backend error and leaves the button on "Follow" when the follow call fails',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowButton(
            targetUserId: 'creator-1',
            followFn: (_) async =>
                throw Exception('Already following this creator'),
          ),
        ),
      ),
    );

    // Resolve the initState ApiClient().userId lookup.
    await tester.pump();
    await tester.pump();

    expect(find.text('Follow'), findsOneWidget);

    await tester.tap(find.text('Follow'));
    await tester.pump(); // start the tap's async work
    await tester.pump(); // let the thrown Future settle
    await tester.pump(); // let the SnackBar animate in

    expect(find.text('Already following this creator'), findsOneWidget,
        reason: 'the real backend failure reason must reach the user, not '
            'be swallowed silently');
    expect(find.text('Follow'), findsOneWidget,
        reason: 'button must not optimistically flip to "Following" when '
            'the follow call actually failed');
    expect(find.text('Following'), findsNothing);
  });

  testWidgets('flips to "Following" when the follow call succeeds',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowButton(
            targetUserId: 'creator-1',
            followFn: (_) async => true,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Follow'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Following'), findsOneWidget);
  });
}
