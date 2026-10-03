import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/l10n/strings.dart';
import 'package:tts_text_mp3_mobile/main.dart';

void main() {
  const contactUrl = 'https://github.com/t-and-i/yomipalette-android/issues';
  const languageLabels = {'en': 'English', 'ja': '日本語', 'zh': '简体中文'};

  for (final locale in AppStrings.supportedLocales) {
    for (final outcome in ['success', 'false', 'exception']) {
      testWidgets('Contact link $outcome in ${locale.languageCode}', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        Uri? attempted;
        String? copied;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null),
        );

        await tester.pumpWidget(
          TtsMobileApp(
            externalLinkLauncher: (uri) async {
              attempted = uri;
              if (outcome == 'exception') {
                throw PlatformException(code: 'launch_failed');
              }
              return outcome == 'success';
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(languageLabels[locale.languageCode]!).last);
        await tester.pumpAndSettle();

        for (final label in [
          'Support development',
          '開発を支援',
          '支持开发',
          'GitHub Sponsors',
          'Buy Me a Coffee',
        ]) {
          expect(find.text(label), findsNothing);
        }

        final s = AppStrings(locale);
        await tester.tap(find.byTooltip(s.get('about')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(s.get('projectContact')));
        await tester.pumpAndSettle();
        expect(attempted.toString(), contactUrl);

        if (outcome == 'success') {
          expect(find.byType(AlertDialog), findsNothing);
        } else {
          expect(
            find.text(s.get('externalLinkOpenFailedTitle')),
            findsOneWidget,
          );
          expect(find.text(s.get('externalLinkOpenFailed')), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(SelectableText),
            ),
            findsOneWidget,
          );
          expect(find.text(contactUrl), findsOneWidget);
          await tester.tap(find.text(s.get('copy')));
          await tester.pumpAndSettle();
          expect(copied, contactUrl);
          await tester.tap(find.text(s.get('close')));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
