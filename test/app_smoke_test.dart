import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/l10n/strings.dart';
import 'package:tts_text_mp3_mobile/main.dart';

void main() {
  testWidgets('mobile screen builds with Material localizations',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const TtsMobileApp());
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
    expect(find.text('TXT character encoding'), findsOneWidget);
    expect(find.text('Select output folder'), findsOneWidget);
    expect(find.text('Generate MP3'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Azure Speech').first);
    await tester.pumpAndSettle();
    expect(find.text('Edge TTS'), findsOneWidget);
  });

  testWidgets('voice guidance is shown and limitations can be hidden',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const TtsMobileApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Load voices to select a voice.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Load voices to select a voice.'), findsOneWidget);
    expect(
      AppStrings(const Locale('ja')).get('voiceRequired'),
      '先に音声一覧を取得し、Voiceを選択してください。',
    );

    await tester.scrollUntilVisible(
      find.text('Not supported on mobile'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Not supported on mobile'), findsOneWidget);
    await Scrollable.ensureVisible(
      tester.element(find.byIcon(Icons.close)),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Not supported on mobile'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_mobile_limitations'), isFalse);
  });
}
