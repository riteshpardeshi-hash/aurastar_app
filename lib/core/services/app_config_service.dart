import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Feature switches an admin controls (backend `GET /app/config`).
///
/// [couponsEnabled] is the coupons on/off switch (backend ADR 119). When it's false the
/// backend gives out, lists and accepts claims for no coupons, and the app hides every
/// coupon screen and entry point — listen to it with a `ValueListenableBuilder`.
///
/// The last value is remembered across launches so a cold start while coupons are off
/// doesn't flash coupon UI before the first fetch returns. If the fetch fails the last
/// known value stays (default: on — the backend still refuses coupons when they're off).
class AppConfigService {
  AppConfigService._();
  static final AppConfigService instance = AppConfigService._();

  static const _prefsKey = 'app_config.coupons_enabled';

  final ValueNotifier<bool> couponsEnabled = ValueNotifier<bool>(true);

  /// Restores the remembered value, then fetches the current one.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_prefsKey);
      if (saved != null) couponsEnabled.value = saved;
    } catch (_) {}
    await refresh();
  }

  /// Fetches the current switches. Never throws.
  Future<void> refresh() async {
    try {
      final res = await ApiClient().get('/app/config');
      final data = res['data'];
      final features = data is Map ? data['features'] : null;
      final coupons = features is Map ? features['coupons'] : null;
      if (res['status'] != 'success' || coupons is! bool) return;
      couponsEnabled.value = coupons;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, coupons);
    } catch (_) {}
  }
}
