import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tts_text_mp3_mobile/controllers/tts_settings_controller.dart';
import 'package:tts_text_mp3_mobile/providers/tts_provider.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('preferred locale matches UI language with a fallback', () {
    const voices = [
      VoiceInfo(name: 'en', locale: 'en-US'),
      VoiceInfo(name: 'ja', locale: 'ja-JP'),
    ];
    expect(TtsSettingsController.preferredVoiceLocale(voices, 'ja'), 'ja-JP');
    expect(TtsSettingsController.preferredVoiceLocale(voices, 'zh'), 'en-US');
    expect(TtsSettingsController.preferredVoiceLocale(voices, 'en'), 'en-US');
  });

  test('voice locale getter returns unique sorted codes', () {
    final controller = TtsSettingsController();
    addTearDown(controller.dispose);
    controller.voices = const [
      VoiceInfo(name: 'b', locale: 'zh-CN'),
      VoiceInfo(name: 'a', locale: 'ja-JP'),
      VoiceInfo(name: 'c', locale: 'ja-JP'),
    ];
    expect(controller.voiceLocales, ['ja-JP', 'zh-CN']);
    controller.voiceLocale = 'ja-JP';
    expect(controller.filteredVoices.map((v) => v.name), ['a', 'c']);
  });

  test('existing saved preference keys remain unchanged', () async {
    final controller = TtsSettingsController();
    addTearDown(controller.dispose);
    controller.providerName = 'edge';
    controller.ttsAutoSplit = false;
    controller.ttsAutoRetry = false;
    controller.ttsShowProgress = true;
    controller.ratePercent = 10;
    controller.volumePercent = -3;
    controller.pitchHz = 7;
    await controller.saveRunOptions(splitByChars: true, maxCharsText: '1234');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('provider'), 'edge');
    expect(prefs.getBool('split_by_chars'), isTrue);
    expect(prefs.getInt('max_chars'), 1234);
    expect(prefs.getBool('tts_auto_split'), isFalse);
    expect(prefs.getBool('tts_auto_retry'), isFalse);
    expect(prefs.getBool('tts_show_progress'), isTrue);
    expect(prefs.getDouble('rate_percent'), 10);
    expect(prefs.getDouble('volume_percent'), -3);
    expect(prefs.getDouble('pitch_hz'), 7);
  });

  test('missing device engine fails before launching platform TTS', () async {
    final controller = TtsSettingsController();
    addTearDown(controller.dispose);
    controller.providerName = 'device';
    await expectLater(
      controller.createProvider(deviceEngineRequiredMessage: 'Choose engine'),
      throwsA(isA<TtsProviderException>()),
    );
  });
}
