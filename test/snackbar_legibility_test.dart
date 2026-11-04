// SnackBar text is legible on the app theme. Material 3 draws SnackBar text in
// onInverseSurface, which the scheme left at its default (surface, a
// near-black), and the screens put every SnackBar on the void2 panel, so the
// text was near-black on near-black and the bar read as an empty black box.
// The first case is the shape the screens build: a font size on the text and
// the void2 panel. The second sets nothing, so the theme alone pairs the text
// with its panel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soqushield/theme/app_theme.dart';
import 'package:soqushield/theme/instrument.dart';

/// WCAG 2 contrast ratio between two colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> _show(WidgetTester tester, SnackBar bar) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(bar),
          child: const Text('show'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('show'));
  await tester.pumpAndSettle();
}

Color _textColour(WidgetTester tester) => tester
    .widget<RichText>(find
        .descendant(of: find.byType(SnackBar), matching: find.byType(RichText))
        .first)
    .text
    .style!
    .color!;

Color _panelColour(WidgetTester tester) => tester
    .widget<Material>(find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first)
    .color!;

void main() {
  testWidgets('a SnackBar as the screens build it is legible', (tester) async {
    await _show(
        tester,
        const SnackBar(
          content: Text('Address copied', style: TextStyle(fontSize: 12)),
          backgroundColor: Instrument.void2,
          behavior: SnackBarBehavior.floating,
        ));
    expect(_panelColour(tester), Instrument.void2);
    expect(_contrast(_textColour(tester), _panelColour(tester)),
        greaterThanOrEqualTo(4.5));
  });

  testWidgets('a SnackBar that sets nothing is legible', (tester) async {
    await _show(tester, const SnackBar(content: Text('Wallet creation failed.')));
    expect(_contrast(_textColour(tester), _panelColour(tester)),
        greaterThanOrEqualTo(4.5));
  });

  testWidgets('a SnackBar action and close icon are legible', (tester) async {
    await _show(
        tester,
        SnackBar(
          content: const Text('Saved'),
          showCloseIcon: true,
          action: SnackBarAction(label: 'UNDO', onPressed: () {}),
        ));
    final panel = _panelColour(tester);
    final action = tester
        .widget<RichText>(find
            .descendant(
                of: find.byType(SnackBarAction), matching: find.byType(RichText))
            .first)
        .text
        .style!
        .color!;
    final close = tester
        .widget<IconButton>(find.descendant(
            of: find.byType(SnackBar), matching: find.byType(IconButton)))
        .color!;
    expect(_contrast(action, panel), greaterThanOrEqualTo(4.5));
    expect(_contrast(close, panel), greaterThanOrEqualTo(3));
  });
}
