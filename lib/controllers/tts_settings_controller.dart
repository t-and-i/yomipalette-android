import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/azure_provider.dart';
import '../providers/device_tts_provider.dart';
import '../providers/edge_provider.dart';
import '../providers/google_provider.dart';
import '../providers/tts_provider.dart';
import '../services/credential_store.dart';

/// TTS configuration and provider construction, without a BuildContext.
///
/// Mutations are orchestrated by the screen so widget updates remain explicit.
/// Storage keys intentionally match all pre-Phase-2 releases.
class TtsSettingsController {
  final CredentialStore credentials = CredentialStore();
  final TextEditingController keyController = TextEditingController();
  final TextEditingController regionController = TextEditingController();

  String providerName = 'azure';
  bool persist = true;
  List<VoiceInfo> voices = const [];
  List<DeviceTtsEngine> deviceTtsEngines = const [];
  String? deviceTtsEngine;
  String? voiceLocale;
  VoiceInfo? voice;
  bool ttsAutoSplit = true;
  bool ttsAutoRetry = true;
  bool ttsShowProgress = true;
  double ratePercent = 0;
  double volumePercent = 0;
  double pitchHz = 0;

  List<String> get voiceLocales =>
      voices.map((voice) => voice.locale).toSet().toList()..sort();

  List<VoiceInfo> get filteredVoices => voiceLocale == null
      ? const []
      : voices.where((entry) => entry.locale == voiceLocale).toList();

  static String preferredVoiceLocale(
    List<VoiceInfo> voices,
    String languageCode,
  ) {
    final preferred = switch (languageCode) {
      'ja' => 'ja-JP',
      'zh' => 'zh-CN',
      _ => 'en-US',
    };
    return voices.any((voice) => voice.locale == preferred)
        ? preferred
        : voices.first.locale;
  }

  Future<TtsProvider> createProvider({
    required String deviceEngineRequiredMessage,
  }) async {
    if (providerName == 'edge') return EdgeProvider();
    if (providerName == 'device') {
      final engine = deviceTtsEngine;
      if (engine == null) {
        throw TtsProviderException(deviceEngineRequiredMessage);
      }
      return DeviceTtsProvider(engine);
    }
    final key = keyController.text.trim();
    if (key.isEmpty) throw const TtsProviderException('API key is required.');
    await credentials.write(providerName, 'api_key', key, persist: persist);
    if (providerName == 'azure') {
      final region = regionController.text.trim();
      if (region.isEmpty) {
        throw const TtsProviderException('Azure region is required.');
      }
      await credentials.write('azure', 'region', region, persist: persist);
      return AzureProvider(key: key, region: region);
    }
    return GoogleProvider(apiKey: key);
  }

  Future<void> saveAudioAdjustments() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('rate_percent', ratePercent);
    await prefs.setDouble('volume_percent', volumePercent);
    await prefs.setDouble('pitch_hz', pitchHz);
  }

  Future<void> saveTtsOptions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('tts_auto_split', ttsAutoSplit);
    await prefs.setBool('tts_auto_retry', ttsAutoRetry);
    await prefs.setBool('tts_show_progress', ttsShowProgress);
  }

  Future<void> saveRunOptions({
    required bool splitByChars,
    required String maxCharsText,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', providerName);
    await prefs.setBool('split_by_chars', splitByChars);
    await prefs.setBool('tts_auto_split', ttsAutoSplit);
    await prefs.setBool('tts_auto_retry', ttsAutoRetry);
    await prefs.setBool('tts_show_progress', ttsShowProgress);
    await prefs.setInt('max_chars', int.tryParse(maxCharsText) ?? 5000);
    await prefs.setDouble('rate_percent', ratePercent);
    await prefs.setDouble('volume_percent', volumePercent);
    await prefs.setDouble('pitch_hz', pitchHz);
  }

  void dispose() {
    credentials.clearSession();
    keyController.dispose();
    regionController.dispose();
  }
}
