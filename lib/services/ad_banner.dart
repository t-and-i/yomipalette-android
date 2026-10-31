import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

const yomiPaletteTestBannerUnit = 'ca-app-pub-3940256099942544/9214589741';
const yomiPaletteProductionBannerUnit =
    'ca-app-pub-1772944769236082/3069565125';

// Explicitly opt into test ads for a release build used ONLY in internal QA.
// Normal release builds always use the production ad unit.
const yomiPaletteInternalTestAds = bool.fromEnvironment('YOMIPALETTE_TEST_ADS');
const yomiPaletteAdDiagnostics = bool.fromEnvironment(
  'YOMIPALETTE_AD_DIAGNOSTICS',
);

String yomiPaletteBannerUnitId({
  required bool isDebug,
  required bool internalTestAds,
}) => isDebug || internalTestAds
    ? yomiPaletteTestBannerUnit
    : yomiPaletteProductionBannerUnit;

/// Anchored adaptive AdMob banner, gated by UMP consent and ad-free ownership.
class YomiPaletteBanner extends StatefulWidget {
  const YomiPaletteBanner({super.key});

  @override
  State<YomiPaletteBanner> createState() => _YomiPaletteBannerState();
}

class _YomiPaletteBannerState extends State<YomiPaletteBanner> {
  BannerAd? _banner;
  Timer? _retryTimer;
  bool _loading = false;
  bool _consentReady = false;
  int _lastWidth = 0;
  int _failureCount = 0;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _log(String message) {
    if (kDebugMode || yomiPaletteAdDiagnostics) {
      debugPrint('YomiPaletteAds: $message');
    }
  }

  @override
  void initState() {
    super.initState();
    if (_android) unawaited(_requestConsent());
  }

  Future<void> _requestConsent() async {
    try {
      final info = ConsentInformation.instance;
      final completer = Completer<void>();
      info.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          _log('UMP consent information updated');
          ConsentForm.loadAndShowConsentFormIfRequired((error) {
            if (error != null) _log('UMP consent form: $error');
            if (!completer.isCompleted) completer.complete();
          });
        },
        (error) {
          _log('UMP consent update: $error');
          if (!completer.isCompleted) completer.complete();
        },
      );
      await completer.future;
      if (!mounted) return;
      final canRequestAds = await info.canRequestAds();
      _log('UMP canRequestAds=$canRequestAds');
      if (!canRequestAds) return;
      await MobileAds.instance.initialize();
      _log('Google Mobile Ads SDK initialized');
      if (!mounted) return;
      setState(() => _consentReady = true);
    } catch (error) {
      _log('Ad SDK initialization failed: $error');
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _failureCount++;
    final seconds = switch (_failureCount) {
      1 => 30,
      2 => 60,
      3 => 120,
      _ => 240,
    };
    _log('Retrying banner load after $seconds seconds');
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      setState(() => _lastWidth = 0);
    });
  }

  Future<void> _load(int width) async {
    if (!_consentReady || _loading || width <= 0) return;
    _loading = true;
    _lastWidth = width;
    BannerAd? created;
    try {
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
      if (!mounted) return;
      if (size == null) {
        _log('No anchored adaptive banner size for width=$width');
        _scheduleRetry();
        return;
      }
      // Unmount the old AdWidget before disposing its native ad.
      final old = _banner;
      if (old != null) {
        setState(() => _banner = null);
        await WidgetsBinding.instance.endOfFrame;
        await old.dispose();
        if (!mounted) return;
      }
      final unit = yomiPaletteBannerUnitId(
        isDebug: kDebugMode,
        internalTestAds: yomiPaletteInternalTestAds,
      );
      _log(
        'Requesting ${unit == yomiPaletteTestBannerUnit ? "TEST" : "PRODUCTION"} banner, width=$width',
      );
      final ad = BannerAd(
        size: size,
        adUnitId: unit,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (loaded) {
            _loading = false;
            _failureCount = 0;
            _retryTimer?.cancel();
            _log(
              'Banner loaded; responseId=${loaded.responseInfo?.responseId ?? "none"}',
            );
            if (mounted) {
              setState(() => _banner = loaded as BannerAd);
            } else {
              unawaited(loaded.dispose());
            }
          },
          onAdFailedToLoad: (failed, error) {
            _loading = false;
            unawaited(failed.dispose());
            _log(
              'Banner load failed: code=${error.code}, domain=${error.domain}, message=${error.message}',
            );
            // Invalid request (code 1) requires a configuration fix, not polling.
            if (mounted && error.code != 1) _scheduleRetry();
          },
          onAdImpression: (_) => _log('Banner impression recorded'),
        ),
      );
      created = ad;
      await ad.load();
    } catch (error) {
      _loading = false;
      _log('Banner request exception: $error');
      if (created != null) await created.dispose();
      if (mounted) _scheduleRetry();
    } finally {
      // Normal requests clear this flag in the asynchronous ad listener.
      // An early return or thrown exception must not block further loads.
      if (created == null) _loading = false;
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_android || !_consentReady) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.floor();
        if (width > 0 && width != _lastWidth && !_loading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) unawaited(_load(width));
          });
        }
        final ad = _banner;
        if (ad == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          bottom: false,
          child: Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        );
      },
    );
  }
}
