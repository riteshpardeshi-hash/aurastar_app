import 'package:aura_app/core/utils/legal_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every legal link is an https auraarenaplay.com /legal/ page', () {
    expect(LegalLinks.all, hasLength(7));
    for (final d in LegalLinks.all) {
      expect(d.uri.scheme, 'https', reason: d.title);
      expect(d.uri.host, 'www.auraarenaplay.com', reason: d.title);
      expect(d.uri.path, startsWith('/legal/'), reason: d.title);
      expect(d.uri.path, endsWith('.html'), reason: d.title);
    }
  });

  test('privacy and terms are in the list', () {
    expect(LegalLinks.all, containsAll([LegalLinks.privacy, LegalLinks.terms]));
  });
}
