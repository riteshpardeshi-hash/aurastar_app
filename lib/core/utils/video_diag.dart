import 'dart:io';

import 'package:flutter/foundation.dart';

/// Diagnostics for "reference video won't load on some devices" reports.
///
/// The players swallow the exception, so a failing phone only shows a spinner
/// or "Ghost unavailable". [describeVideoFailure] builds a copy-pasteable
/// report (device OS, unsigned URL, cached-vs-network, exception text) and
/// logs it as `[videodiag]` (`adb logcat -s flutter | findstr videodiag`) for
/// engineers to pull from device logs — it is deliberately never shown to
/// users as a raw dialog.
///
/// The query string is stripped from the URL — it carries the presigned
/// signature.
String describeVideoFailure(
  Object error, {
  required String where,
  required String url,
  required bool fromCache,
  String? playerError,
}) {
  final uri = Uri.tryParse(url);
  final safeUrl = uri == null
      ? '(unparseable)'
      : '${uri.scheme}://${uri.host}${uri.path}';
  final report = [
    'where: $where',
    'os: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    'url: $safeUrl',
    'source: ${fromCache ? 'local cache file' : 'network stream'}',
    'error: $error',
    if (playerError != null) 'player: $playerError',
  ].join('\n');
  debugPrint('[videodiag] ${DateTime.now().toIso8601String()}\n$report');
  return report;
}
