import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../guide/guide_content.dart';
import '../../theme/instrument.dart';

/// FIELD MANUAL — the in-app user guide index.
///
/// Task-shaped articles grouped by what the user is trying to do, rendered on
/// the foundry language (seam rows, no cards). Support (Discord) sits at the
/// bottom as the escalation path, not the front door, with the privacy
/// policy beside it: App Review asks for the policy to be reachable in the
/// app (Guideline 5.1.1), and this is where a user looks for it.
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
                  ExternalLinkRow(
                    icon: Icons.chat_bubble_outline,
                    title: 'Still stuck? Contact support',
                    detail:
                        'Opens our Discord. Support will never ask for your recovery phrase.',
                    url: Uri.parse('https://discord.gg/kc6GMmbZvX'),
                  ),
                  ExternalLinkRow(
                    icon: Icons.policy_outlined,
                    title: 'Privacy policy',
                    detail:
                        'What the app sends, what stays on your device, and what we never do. Opens soqu.org.',
                    url: Uri.parse('https://soqu.org/privacy'),
                  ),
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

/// A row at the foot of the manual that opens a page outside the app, in the
/// device's browser: support, the privacy policy. The row carries its target,
/// so a test can read where it goes.
class ExternalLinkRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Uri url;
  const ExternalLinkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(url, mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        child: Row(
          children: [
            Icon(icon, color: Instrument.label, size: 18),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                        color: Instrument.readout,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      )),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
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
