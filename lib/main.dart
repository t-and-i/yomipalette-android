import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';
import 'l10n/strings.dart';
import 'models/chapter.dart';
import 'screens/home_screen.dart';
import 'services/ad_free_purchase.dart';
import 'services/preview_audio_player.dart';

// Preserve the existing public HomeScreen symbol for consumers of main.dart.
export 'screens/home_screen.dart' show HomeScreen;

void main() => runApp(const TtsMobileApp());

class TtsMobileApp extends StatefulWidget {
  const TtsMobileApp({
    this.previewPlayer,
    this.externalLinkLauncher,
    this.initialChapters = const [],
    super.key,
  });

  final PreviewAudioPlayer? previewPlayer;
  final ExternalLinkLauncher? externalLinkLauncher;
  final List<Chapter> initialChapters;

  @override
  State<TtsMobileApp> createState() => _TtsMobileAppState();
}

class _TtsMobileAppState extends State<TtsMobileApp> {
  Locale? locale;
  bool _localeChangedDuringRestore = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _themeChangedDuringRestore = false;
  late final AdFreePurchaseController _adFreeController;

  @override
  void initState() {
    super.initState();
    _adFreeController = AdFreePurchaseController();
    _adFreeController.addListener(_onPurchaseChanged);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_adFreeController.initialize());
    }
    unawaited(_restoreThemeMode());
    unawaited(_restoreLocale());
  }

  void _onPurchaseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _adFreeController.removeListener(_onPurchaseChanged);
    _adFreeController.dispose();
    super.dispose();
  }

  Future<void> _restoreThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    if (!mounted || _themeChangedDuringRestore) return;
    setState(
      () => _themeMode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
    );
  }

  Future<void> _restoreLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_locale');
    if (!mounted || _localeChangedDuringRestore) return;
    setState(() {
      locale =
          AppStrings.supportedLocales.any(
            (supported) => supported.languageCode == saved,
          )
          ? Locale(saved!)
          : null;
    });
  }

  void _changeLocale(Locale value) {
    _localeChangedDuringRestore = true;
    setState(() => locale = value);
    unawaited(_saveLocale(value));
  }

  Future<void> _saveLocale(Locale value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_locale', value.languageCode);
  }

  void _changeThemeMode(ThemeMode mode) {
    _themeChangedDuringRestore = true;
    setState(() => _themeMode = mode);
    unawaited(_saveThemeMode(mode));
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    title: 'YomiPalette',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    themeMode: _themeMode,
    home: HomeScreen(
      onLocaleChanged: _changeLocale,
      themeMode: _themeMode,
      onThemeModeChanged: _changeThemeMode,
      adFreeController: _adFreeController,
      previewPlayer: widget.previewPlayer,
      externalLinkLauncher: widget.externalLinkLauncher,
      initialChapters: widget.initialChapters,
    ),
  );
}
