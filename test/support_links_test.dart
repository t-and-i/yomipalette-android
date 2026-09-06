import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/app_info.dart';
import 'package:tts_text_mp3_mobile/main.dart';

void main() {
  test('support links retain their service names, order and URLs', () async {
    expect(supportLinks.map((link) => link.label), [
      'GitHub Sponsors',
      'Buy Me a Coffee',
    ]);
    expect(supportLinks.map((link) => link.url), [
      'https://github.com/sponsors/tjsongwei',
      'https://buymeacoffee.com/tjsongweic',
    ]);

    final opened = <Uri>[];
    for (final link in supportLinks) {
      expect(
        await openSupportLink(
          link,
          launcher: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
        isTrue,
      );
    }
    expect(
      opened.map((uri) => uri.toString()),
      supportLinks.map((link) => link.url),
    );
  });

  testWidgets('support button opens choices and failed URL is selectable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    Uri? attempted;

    await tester.pumpWidget(
      TtsMobileApp(
        supportLauncher: (uri) async {
          attempted = uri;
          return false;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Support development'));
    await tester.pumpAndSettle();
    expect(find.text('GitHub Sponsors'), findsOneWidget);
    expect(find.text('Buy Me a Coffee'), findsOneWidget);

    await tester.tap(find.text('Buy Me a Coffee'));
    await tester.pumpAndSettle();
    expect(attempted.toString(), 'https://buymeacoffee.com/tjsongweic');
    expect(find.text('Could not open browser'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('https://buymeacoffee.com/tjsongweic'), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
