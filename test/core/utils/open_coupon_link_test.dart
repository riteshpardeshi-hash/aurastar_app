import 'package:aura_app/core/utils/open_coupon_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records launches; `inApp` / `external` decide whether each mode "succeeds".
class _FakeLauncher extends UrlLauncherPlatform {
  _FakeLauncher({this.inApp = true, this.external = true, this.throws = false});

  final bool inApp;
  final bool external;
  final bool throws;
  final List<(String, PreferredLaunchMode)> launches = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url, options.mode));
    if (throws) throw Exception('no handler');
    return options.mode == PreferredLaunchMode.externalApplication
        ? external
        : inApp;
  }
}

// App Review (guideline 2.1) tapped a coupon's link and got nothing useful.
// The old call sites ignored launchUrl's false return / exceptions, so a link
// that couldn't open silently did nothing. Now the user is told.
void main() {
  Future<void> tapOpen(WidgetTester tester, String url) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => openCouponLink(context, url),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
  }

  const failure = "Couldn't open this offer. Please try again later.";

  testWidgets('opens in the in-app browser and shows nothing on success',
      (tester) async {
    final launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;

    await tapOpen(tester, 'https://api.example.com/r/G1');

    expect(launcher.launches.single.$2, PreferredLaunchMode.inAppBrowserView);
    expect(find.text(failure), findsNothing);
  });

  testWidgets('falls back to the external browser when in-app fails',
      (tester) async {
    final launcher = _FakeLauncher(inApp: false);
    UrlLauncherPlatform.instance = launcher;

    await tapOpen(tester, 'https://api.example.com/r/G1');

    expect(launcher.launches.map((l) => l.$2).last,
        PreferredLaunchMode.externalApplication);
    expect(find.text(failure), findsNothing);
  });

  testWidgets('tells the user when neither browser can open the link',
      (tester) async {
    UrlLauncherPlatform.instance = _FakeLauncher(inApp: false, external: false);

    await tapOpen(tester, 'https://api.example.com/r/G1');

    expect(find.text(failure), findsOneWidget);
  });

  testWidgets('tells the user when launching throws', (tester) async {
    UrlLauncherPlatform.instance = _FakeLauncher(throws: true);

    await tapOpen(tester, 'https://api.example.com/r/G1');

    expect(find.text(failure), findsOneWidget);
  });

  testWidgets('a non-http(s) link is never launched and the user is told',
      (tester) async {
    final launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;

    await tapOpen(tester, 'javascript:alert(1)');

    expect(launcher.launches, isEmpty);
    expect(find.text(failure), findsOneWidget);
  });
}
