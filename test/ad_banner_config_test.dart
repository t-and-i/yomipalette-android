import 'package:flutter_test/flutter_test.dart';
import 'package:tts_text_mp3_mobile/services/ad_banner.dart';

void main() {
  test('debug builds always use the Google sample banner', () {
    expect(
      yomiPaletteBannerUnitId(isDebug: true, internalTestAds: false),
      yomiPaletteTestBannerUnit,
    );
  });

  test('opt-in release internal QA uses the Google sample banner', () {
    expect(
      yomiPaletteBannerUnitId(isDebug: false, internalTestAds: true),
      yomiPaletteTestBannerUnit,
    );
  });

  test('normal release uses the production banner unit', () {
    expect(
      yomiPaletteBannerUnitId(isDebug: false, internalTestAds: false),
      yomiPaletteProductionBannerUnit,
    );
  });
}
