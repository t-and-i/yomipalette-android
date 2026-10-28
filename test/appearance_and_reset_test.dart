import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/l10n/strings.dart';
import 'package:tts_text_mp3_mobile/main.dart';

Future<void> scrollTo(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('audio reset zeros all 3 adjustments and persists them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'rate_percent': 25.0,
      'volume_percent': -10.0,
      'pitch_hz': 12.0,
    });
    await tester.pumpWidget(const TtsMobileApp());
    await tester.pumpAndSettle();
    await scrollTo(tester, 'Audio adjustments');

    expect(
      tester
          .widgetList<Slider>(find.byType(Slider))
          .map((s) => s.value)
          .toList(),
      [25.0, -10.0, 12.0],
    );
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<Slider>(find.byType(Slider))
          .map((s) => s.value)
          .toList(),
      [0.0, 0.0, 0.0],
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('rate_percent'), 0.0);
    expect(prefs.getDouble('volume_percent'), 0.0);
    expect(prefs.getDouble('pitch_hz'), 0.0);
  });

  testWidgets('theme defaults to system and can persist dark and light', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const TtsMobileApp());
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await scrollTo(tester, 'Appearance');
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'dark');

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'system');
  });

  testWidgets('saved dark mode is restored on app startup', (tester) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    await tester.pumpWidget(const TtsMobileApp());
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(app.darkTheme, isNotNull);
    expect(app.darkTheme!.brightness, Brightness.dark);
  });

  testWidgets('unknown saved theme falls back to system', (tester) async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'future_mode'});
    await tester.pumpWidget(const TtsMobileApp());
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
  });

  test('new labels are translated into Japanese, English and Chinese', () {
    for (final locale in [
      const Locale('ja'),
      const Locale('en'),
      const Locale('zh'),
    ]) {
      final strings = AppStrings(locale);
      for (final key in [
        'resetAudio',
        'appearance',
        'themeSystem',
        'themeLight',
        'themeDark',
      ]) {
        expect(strings.get(key), isNot(key));
      }
    }
  });
}
