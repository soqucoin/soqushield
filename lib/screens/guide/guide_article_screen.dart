import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../guide/guide_content.dart';
import '../../theme/instrument.dart';

/// One Field Manual article: title, then sections of paragraph / numbered
/// steps / NOTE callout. Step numerals are mono copper so the "do this next"
/// path reads at a glance; everything else stays quiet.
class GuideArticleScreen extends StatelessWidget {
  final String articleId;
  const GuideArticleScreen({super.key, required this.articleId});

  @override
  Widget build(BuildContext context) {
    final article = guideArticleById(articleId);
    return Scaffold(
      backgroundColor: Instrument.void0,
      body: SafeArea(
        child: article == null
            ? const Center(
                child: Text('Article not found',
                    style: TextStyle(color: Instrument.label)))
            : Column(
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
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
                      children: [
                        Text(article.title,
                            style: const TextStyle(
                              color: Instrument.readout,
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            )),
                        const SizedBox(height: 6),
                        Text(article.tagline,
                            style: const TextStyle(
                              color: Instrument.faint,
                              fontSize: 12.5,
                              height: 1.4,
                            )),
                        const SizedBox(height: 8),
                        for (final s in article.sections) _Section(section: s),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final GuideSection section;
  const _Section({required this.section});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.heading != null) ...[
          const SizedBox(height: 22),
          Text(section.heading!.toUpperCase(),
              style: Instrument.eyebrow(size: 10)),
          const SizedBox(height: 10),
        ] else
          const SizedBox(height: 14),
        if (section.body != null)
          Text(section.body!,
              style: const TextStyle(
                color: Instrument.label,
                fontSize: 13.5,
                height: 1.55,
              )),
        if (section.steps.isNotEmpty) ...[
          if (section.body != null) const SizedBox(height: 12),
          for (var i = 0; i < section.steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 26,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                          color: Instrument.signal,
                          fontSize: 13,
                          fontFamily: kMono,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        )),
                  ),
                  Expanded(
                    child: Text(section.steps[i],
                        style: const TextStyle(
                          color: Instrument.readout,
                          fontSize: 13.5,
                          height: 1.5,
                        )),
                  ),
                ],
              ),
            ),
        ],
        if (section.note != null) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Instrument.void2,
              border: Border.all(color: Instrument.line, width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NOTE', style: Instrument.eyebrow(size: 9.5)),
                const SizedBox(height: 6),
                Text(section.note!,
                    style: const TextStyle(
                      color: Instrument.label,
                      fontSize: 12.5,
                      height: 1.5,
                    )),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
