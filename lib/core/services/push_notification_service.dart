import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notifications_service.dart';

// Owns the client side of the nudge engine (ADR 042): OS permission
// request, FCM/APNs token retrieval, and keeping the backend's DeviceToken
// row in sync (register on token issue/refresh, deregister on logout).
class PushNotificationService {
  static bool _initializing = false;
  static const _kDeviceId = 'push_device_id';
  static const _kLastToken = 'push_last_token';
  static const _kAutoOptedIn = 'push_auto_opted_in';

  final _notifications = NotificationsService();

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<void> initialize() async {
    if (_initializing) return;
    _initializing = true;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerIfNew(token);

      FirebaseMessaging.instance.onTokenRefresh.listen(_registerIfNew);
    } catch (_) {
      // Best-effort — push registration failing shouldn't block app usage.
    } finally {
      _initializing = false;
    }
  }

  Future<void> _registerIfNew(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kLastToken) == token) return;
    try {
      final device = await _notifications.registerDevice(
        platform: _platform,
        token: token,
      );
      final id = device['_id'] as String?;
      if (id != null) await prefs.setString(_kDeviceId, id);
      await prefs.setString(_kLastToken, token);

      // NudgePreference.pushEnabled defaults to false server-side until the
      // client opts the user in after OS permission is granted — do that
      // once, here, on first successful registration. Never repeated after
      // that so it can't stomp on a later explicit opt-out from the
      // notification preferences screen.
      if (prefs.getBool(_kAutoOptedIn) != true) {
        try {
          await _notifications.updatePreferences(pushEnabled: true);
        } catch (_) {}
        await prefs.setBool(_kAutoOptedIn, true);
      }
    } catch (_) {
      // Best-effort — a failed registration will simply retry next launch.
    }
  }

  Future<void> deregisterCurrentDevice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kDeviceId);
      if (id != null) await _notifications.deregisterDevice(id);
      await prefs.remove(_kDeviceId);
      await prefs.remove(_kLastToken);
      await prefs.remove(_kAutoOptedIn);
    } catch (_) {
      // Best-effort — logout must not be blocked by this.
    }
  }
}
