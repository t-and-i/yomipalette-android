import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Test ads are used in debug builds; release uses the AdMob banner unit.
class YomiPaletteBanner extends StatefulWidget {
  const YomiPaletteBanner({super.key});

  @override
  State<YomiPaletteBanner> createState() => _YomiPaletteBannerState();
}

class _YomiPaletteBannerState extends State<YomiPaletteBanner> {
  static const _testUnit = 'ca-app-pub-3940256099942544/9214589741';
  static const _productionUnit = 'ca-app-pub-1772944769236082/3069565125';
  BannerAd? _banner;
  bool _loading = false;
  bool _consentReady = false;
  int _lastWidth = 0;

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    if (_android) unawaited(_requestConsent());
  }

  Future<void> _requestConsent() async {
    final info = ConsentInformation.instance;
    final completer = Completer<void>();
    info.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((error) {
          if (!completer.isCompleted) completer.complete();
        });
      },
      (error) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    await completer.future;
    if (!mounted) return;
    if (await info.canRequestAds()) {
      await MobileAds.instance.initialize();
      if (!mounted) return;
      setState(() => _consentReady = true);
    }
  }

  Future<void> _load(int width) async {
    if (!_consentReady || _loading || width <= 0) return;
    _loading = true;
    _lastWidth = width;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
      width,
    );
    if (!mounted || size == null) {
      _loading = false;
      return;
    }
    final old = _banner;
    if (old != null) {
      _banner = null;
      await old.dispose();
    }
    final ad = BannerAd(
      size: size,
      adUnitId: kDebugMode ? _testUnit : _productionUnit,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loaded) {
          if (mounted) setState(() => _banner = loaded as BannerAd);
          _loading = false;
        },
        onAdFailedToLoad: (failed, error) {
          failed.dispose();
          _loading = false;
          if (kDebugMode) debugPrint('AdMob banner: $error');
        },
      ),
    );
    await ad.load();
  }

  @override
  void dispose() {
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
