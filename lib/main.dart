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
import 'services/trial_access.dart';
import 'services/offline_entitlement_cache.dart';
import 'services/signed_trial_cache.dart';
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

class _TtsMobileAppState extends State<TtsMobileApp>
    with WidgetsBindingObserver {
  Locale? locale;
  bool _localeChangedDuringRestore = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _themeChangedDuringRestore = false;
  late final AdFreePurchaseController _adFreeController;
  late final TrialAccessController _trialController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Both controllers share the same installation ID. Paid purchases do not
    // require a Google account or depend on the trial service.
    final purchaseCache = SignedOfflineEntitlementStore();
    _adFreeController = AdFreePurchaseController(offlineStore: purchaseCache);
    _trialController = TrialAccessController(
      store: SignedTrialEntitlementStore(
        deviceIdProvider: purchaseCache.getDeviceId,
      ),
    );
    _trialController.addListener(_onPurchaseChanged);
    _adFreeController.addListener(_onPurchaseChanged);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_trialController.initialize());
      unawaited(_adFreeController.initialize());
    }
    unawaited(_restoreThemeMode());
    unawaited(_restoreLocale());
  }

  void _onPurchaseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_trialController.refresh());
      unawaited(_adFreeController.refreshEntitlement());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trialController.removeListener(_onPurchaseChanged);
    _trialController.dispose();
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
      trialController:
          !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? _trialController
          : null,
      previewPlayer: widget.previewPlayer,
      externalLinkLauncher: widget.externalLinkLauncher,
      initialChapters: widget.initialChapters,
    ),
  );
}
