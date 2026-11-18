import 'package:flutter/material.dart';

import '../l10n/strings.dart';

class GenerationActions extends StatelessWidget {
  const GenerationActions({
    required this.strings,
    required this.busy,
    required this.generating,
    required this.previewPlaying,
    required this.showProgress,
    required this.status,
    this.canUse = true,
    required this.canGenerateResume,
    required this.onPreview,
    required this.onGenerate,
    required this.onCancel,
    super.key,
  });

  final AppStrings strings;
  final bool busy;
  final bool generating;
  final bool previewPlaying;
  final bool showProgress;
  final String status;
  final bool canUse;
  final bool canGenerateResume;
  final VoidCallback onPreview;
  final VoidCallback onGenerate;
  final VoidCallback onCancel;

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
      if (!canUse)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(strings.get('trialExpired'), textAlign: TextAlign.center),
        ),
      SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canUse && (previewPlaying || !busy)
                    ? onPreview
                    : null,
                icon: Icon(previewPlaying ? Icons.stop : Icons.play_arrow),
                label: Text(
                  strings.get(previewPlaying ? 'stopPreview' : 'preview'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: generating
                    ? onCancel
                    : (!canUse || busy || previewPlaying ? null : onGenerate),
                icon: Icon(generating ? Icons.cancel_outlined : Icons.download),
                label: Text(
                  strings.get(
                    generating
                        ? 'cancelGeneration'
                        : (canGenerateResume ? 'resumeGenerate' : 'generate'),
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
