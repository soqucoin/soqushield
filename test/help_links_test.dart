// The foot of the Field Manual carries the two links outside the app: support
// and the privacy policy, which App Review asks to be reachable in the app
// (Guideline 5.1.1). The rows carry their targets, so the test reads them
// off the widgets and opens no browser.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/screens/guide/guide_screen.dart';

void main() {
  testWidgets('the Field Manual links to the privacy policy and to support',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GuideScreen()));
    await tester.pumpAndSettle();

    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Privacy policy'), 300,
        scrollable: list);
    await tester.pumpAndSettle();

    final privacy = tester.widget<ExternalLinkRow>(
        find.widgetWithText(ExternalLinkRow, 'Privacy policy'));
    expect(privacy.url, Uri.parse('https://soqu.org/privacy'));
    expect(find.textContaining('what we never do'), findsOneWidget,
        reason: 'the row says what the page is');

    final support = tester.widget<ExternalLinkRow>(
        find.widgetWithText(ExternalLinkRow, 'Still stuck? Contact support'));
    expect(support.url.host, 'discord.gg');
    expect(find.textContaining('never ask for your recovery phrase'),
        findsOneWidget);
  });
}
