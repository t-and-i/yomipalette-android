import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/ad_banner.dart';

class GenerationActions extends StatelessWidget {
  const GenerationActions({
    required this.strings,
    required this.busy,
    required this.previewPlaying,
    required this.showProgress,
    required this.status,
    required this.showBanner,
    required this.canGenerateResume,
    required this.onPreview,
    required this.onGenerate,
    super.key,
  });

  final AppStrings strings;
  final bool busy;
  final bool previewPlaying;
  final bool showProgress;
  final String status;
  final bool showBanner;
  final bool canGenerateResume;
  final VoidCallback onPreview;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (busy && showProgress && status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const LinearProgressIndicator(minHeight: 2),
              Text(
                status,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      if (showBanner) const YomiPaletteBanner(),
      SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: previewPlaying || !busy ? onPreview : null,
                icon: Icon(previewPlaying ? Icons.stop : Icons.play_arrow),
                label: Text(
                  strings.get(previewPlaying ? 'stopPreview' : 'preview'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy || previewPlaying ? null : onGenerate,
                icon: const Icon(Icons.download),
                label: Text(
                  strings.get(
                    canGenerateResume ? 'resumeGenerate' : 'generate',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
