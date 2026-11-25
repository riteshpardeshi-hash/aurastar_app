import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Tester report (25 Nov 2026): headings like "Water bottle Campaign" and "Brand brief"
// read as one word. Clash Display's space is very narrow, so every style that uses it
// sets wordSpacing (about 0.22 × the font size). This fails if one is added without it.
void main() {
  test('every Clash Display text style sets wordSpacing', () {
    final missing = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in RegExp(r"fontFamily: 'ClashDisplay'").allMatches(src)) {
        final start = src.lastIndexOf('TextStyle(', m.start);
        var depth = 0, end = start + 'TextStyle'.length;
        for (; end < src.length; end++) {
          if (src[end] == '(') depth++;
          if (src[end] == ')' && --depth == 0) break;
        }
        if (!src.substring(start, end).contains('wordSpacing')) {
          missing.add('${f.path}:${'\n'.allMatches(src.substring(0, m.start)).length + 1}');
        }
      }
    }
    expect(missing, isEmpty);
  });
}
