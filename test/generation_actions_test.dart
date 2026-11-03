import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/l10n/strings.dart';
import 'package:tts_text_mp3_mobile/widgets/generation_actions.dart';

void main() {
  testWidgets('active generation shows a working cancel button', (
    tester,
  ) async {
    var cancelled = 0;
    var generated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GenerationActions(
            strings: AppStrings(const Locale('en')),
            busy: true,
            generating: true,
            previewPlaying: false,
            showProgress: true,
            status: 'Chunk 1/4',
            showBanner: false,
            canGenerateResume: true,
            onPreview: () {},
            onGenerate: () => generated++,
            onCancel: () => cancelled++,
          ),
        ),
      ),
    );

    expect(find.text('Cancel generation'), findsOneWidget);
    expect(find.text('Chunk 1/4'), findsOneWidget);
    await tester.tap(find.text('Cancel generation'));
    expect(cancelled, 1);
    expect(generated, 0);
  });

  testWidgets('idle generation preserves the resume label', (tester) async {
    var generated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GenerationActions(
            strings: AppStrings(const Locale('en')),
            busy: false,
            generating: false,
            previewPlaying: false,
            showProgress: true,
            status: '',
            showBanner: false,
            canGenerateResume: true,
            onPreview: () {},
            onGenerate: () => generated++,
            onCancel: () {},
          ),
        ),
      ),
    );

    expect(find.text('Continue generation'), findsOneWidget);
    await tester.tap(find.text('Continue generation'));
    expect(generated, 1);
  });
}
