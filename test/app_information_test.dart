import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/l10n/strings.dart';
import 'package:tts_text_mp3_mobile/screens/app_information_screen.dart';

void main() {
  for (final locale in AppStrings.supportedLocales) {
    testWidgets('About and offline privacy in ${locale.languageCode}', (
      tester,
    ) async {

      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() => rootBundle.loadString('LICENSE'));
      final s = AppStrings(locale);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: AppInformationScreen(
            version: '0.2.0',
            buildNumber: '8',
            openProject: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('0.2.0 (8)'), findsOneWidget);
      await tester.tap(find.text(s.get('privacy')));
      await tester.pumpAndSettle();
      expect(find.text(s.get('privacyDocuments')), findsOneWidget);
      await tester.scrollUntilVisible(find.text(s.get('privacyExternal')), 250);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text(s.get('licenses')));
        await rootBundle.loadString('LICENSE');
      });
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.textContaining('MIT License'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
