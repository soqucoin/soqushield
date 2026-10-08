import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soqushield/guide/guide_content.dart';

void main() {
  List<GuideSection> safetySections() {
    final safety = guideCategories
        .expand((c) => c.articles)
        .firstWhere((a) => a.id == 'safety');
    return safety.sections;
  }

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android sees the black-screenshot section', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final headings = safetySections().map((s) => s.heading).toList();
    expect(headings, contains('Why screenshots look black'));
    expect(headings, isNot(contains('How the app hides from prying screens')));
  });

  test('iOS sees the app-switcher blur section, not the black-screenshot claim',
      () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final sections = safetySections();
    final headings = sections.map((s) => s.heading).toList();
    expect(headings, contains('How the app hides from prying screens'));
    expect(headings, isNot(contains('Why screenshots look black')));
    // The iOS text must not claim captures come out black anywhere.
    for (final s in sections) {
      expect(s.body ?? '', isNot(contains('comes out black')));
    }
  });
}
