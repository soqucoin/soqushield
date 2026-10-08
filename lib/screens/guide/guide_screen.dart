import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../guide/guide_content.dart';
import '../../theme/instrument.dart';

/// FIELD MANUAL — the in-app user guide index.
///
/// Task-shaped articles grouped by what the user is trying to do, rendered on
/// the foundry language (seam rows, no cards). Support (Discord) sits at the
/// bottom as the escalation path, not the front door.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    icon: const Icon(Icons.arrow_back,
                        color: Instrument.label, size: 20),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 4),
                  Text('FIELD MANUAL', style: Instrument.eyebrow(size: 10.5)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Text('How to use SoquShield',
                  style: TextStyle(
                    color: Instrument.readout,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  )),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                'Short, step-by-step answers. No jargon without a plain-words translation.',
                style: TextStyle(color: Instrument.faint, fontSize: 12.5, height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final cat in guideCategories) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 22, 22, 6),
                      child: Text(cat.label, style: Instrument.eyebrow(size: 10)),
                    ),
                    for (final a in cat.articles) _ArticleRow(article: a),
                  ],
                  const SizedBox(height: 18),
                  const InstrumentDivider(inset: 22),
                  const _SupportRow(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final GuideArticle article;
  const _ArticleRow({required this.article});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/guide/${article.id}'),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Instrument.line, width: 0.6)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        child: Row(
          children: [
            Icon(article.icon, color: Instrument.label, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(article.title,
                      style: const TextStyle(
                        color: Instrument.readout,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      )),
                  const SizedBox(height: 3),
                  Text(article.tagline,
                      style: const TextStyle(
                        color: Instrument.faint,
                        fontSize: 11.5,
                        height: 1.35,
                      )),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded,
                color: Instrument.faint, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The escalation path: guide first, humans second.
class _SupportRow extends StatelessWidget {
  const _SupportRow();

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse('https://discord.gg/kc6GMmbZvX'),
          mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline,
                color: Instrument.label, size: 18),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Still stuck? Contact support',
                      style: TextStyle(
                        color: Instrument.readout,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      )),
                  SizedBox(height: 3),
                  Text(
                    'Opens our Discord. Support will never ask for your recovery phrase.',
                    style: TextStyle(
                      color: Instrument.faint,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.north_east, color: Instrument.faint, size: 13),
          ],
        ),
      ),
    );
  }
}
