import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_info.dart';
import '../controllers/audio_generation_controller.dart';
import '../controllers/document_controller.dart';
import '../controllers/tts_settings_controller.dart';
import '../l10n/strings.dart';
import '../models/chapter.dart';
import '../providers/device_tts_provider.dart';
import '../providers/tts_provider.dart';
import '../services/audio_generator.dart';
import '../services/audio_generation_cancellation.dart';
import '../services/ad_free_purchase.dart';
import '../services/document_reader.dart';
import '../services/output_directory_service.dart';
import '../services/pdf_reader.dart';
import '../services/preview_audio_player.dart';
import '../screens/app_information_screen.dart';
import '../widgets/ad_free_section.dart';
import '../widgets/audio_adjustment_slider.dart';
import '../widgets/generation_actions.dart';
import '../widgets/output_units_section.dart';
import '../widgets/provider_settings_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onLocaleChanged,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
    this.adFreeController,
    this.previewPlayer,
    this.externalLinkLauncher,
    this.initialChapters = const [],
    super.key,
  });
  final ValueChanged<Locale> onLocaleChanged;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final AdFreePurchaseController? adFreeController;
  final PreviewAudioPlayer? previewPlayer;
  final ExternalLinkLauncher? externalLinkLauncher;
  final List<Chapter> initialChapters;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final DocumentController _document;
  final TtsSettingsController _tts = TtsSettingsController();
  late final AudioGenerationController _audio;
  StreamSubscription<bool>? _playerSubscription;

  bool _busy = false;
  bool _isGenerating = false;
  bool _isPreviewPlaying = false;
  bool _showLimitations = true;
  String? _outputDirectory;
  String? _outputDirectoryLabel;
  String _status = '';
  String? _appVersion;
  String? _appBuildNumber;

  @override
  void initState() {
    super.initState();
    _document = DocumentController(initialChapters: widget.initialChapters);
    _audio = AudioGenerationController(
      player: widget.previewPlayer ?? JustAudioPreviewPlayer(),
    );
    _playerSubscription = _audio.player.playingStream.listen(
      _onPreviewPlayingChanged,
      onError: (_) => _onPreviewPlayingChanged(false),
    );
    _restore();
    unawaited(_loadAppVersion());
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = info.version;
          _appBuildNumber = info.buildNumber;
        });
      }
    } catch (_) {
      // The app remains usable when platform metadata is unavailable.
    }
  }

  Future<void> _openExternalLink(String url) async {
    var opened = false;
    try {
      opened = await openExternalLink(
        url,
        launcher: widget.externalLinkLauncher,
      );
    } catch (_) {
      // Show a copyable address when the platform cannot open a browser.
    }
    if (opened || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('externalLinkOpenFailedTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.get('externalLinkOpenFailed')),
            const SizedBox(height: 8),
            SelectableText(url),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
            icon: const Icon(Icons.copy),
            label: Text(s.get('copy')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.get('close')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tts.dispose();
    _document.dispose();
    unawaited(_disposePlayer());
    super.dispose();
  }

  Future<void> _disposePlayer() async {
    await _playerSubscription?.cancel();
    await _audio.dispose();
  }

  void _onPreviewPlayingChanged(bool playing) {
    if (!mounted || _isPreviewPlaying == playing) return;
    setState(() {
      _isPreviewPlaying = playing;
      if (playing) _status = s.get('previewPlaying');
    });
  }

  AppStrings get s => AppStrings(Localizations.localeOf(context));

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('provider') ?? 'azure';
    final key = await _tts.credentials.read(provider, 'api_key') ?? '';
    final region = await _tts.credentials.read(provider, 'region') ?? '';
    if (!mounted) return;
    setState(() {
      _tts.providerName =
          provider == 'device' &&
              defaultTargetPlatform != TargetPlatform.android
          ? 'edge'
          : provider;
      _document.textEncoding = prefs.getString('text_encoding') ?? 'auto';
      if (!DocumentReader.textEncodings.contains(_document.textEncoding)) {
        _document.textEncoding = 'auto';
      }
      _tts.keyController.text = key;
      _tts.regionController.text = region;
      _document.splitByChars = prefs.getBool('split_by_chars') ?? false;
      _document.charsController.text = (prefs.getInt('max_chars') ?? 5000)
          .toString();
      _showLimitations = prefs.getBool('show_mobile_limitations') ?? true;
      _tts.ttsAutoSplit = prefs.getBool('tts_auto_split') ?? true;
      _tts.ttsAutoRetry = prefs.getBool('tts_auto_retry') ?? true;
      _tts.ttsShowProgress = prefs.getBool('tts_show_progress') ?? true;
      _tts.ratePercent = prefs.getDouble('rate_percent') ?? 0;
      _tts.volumePercent = prefs.getDouble('volume_percent') ?? 0;
      _tts.pitchHz = prefs.getDouble('pitch_hz') ?? 0;
      _outputDirectory = prefs.getString('output_directory');
      _outputDirectoryLabel = prefs.getString('output_directory_label');
      _tts.deviceTtsEngine = prefs.getString('device_tts_engine');
    });
    if (_tts.providerName == 'device') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeviceEngines());
    } else if (_tts.providerName == 'edge' ||
        (key.isNotEmpty && (provider != 'azure' || region.isNotEmpty))) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadVoices());
    }
  }

  Future<void> _selectFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub', 'pdf'],
      withData: true,
    );
    if (result == null) return;
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('Could not read file.');
      final chapters = await DocumentReader.read(
        file.name,
        bytes,
        textEncoding: _document.textEncoding,
      );
      if (!mounted) return;
      setState(() {
        _document.loadFile(file.name, bytes, chapters);
        _resetGeneration();
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeTextEncoding(String encoding) async {
    final name = _document.fileName;
    final bytes = _document.fileBytes;
    if (name == null || bytes == null || !name.toLowerCase().endsWith('.txt')) {
      setState(() => _document.textEncoding = encoding);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('text_encoding', encoding);
      return;
    }
    await _run(() async {
      final chapters = await DocumentReader.read(
        name,
        bytes,
        textEncoding: encoding,
      );
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('text_encoding', encoding);
      setState(() {
        _document.updateDecodedText(encoding, chapters);
        _resetGeneration();
        _status = s.get('encodingReloaded');
      });
    });
  }

  void _resetGeneration({bool resetChecks = false}) {
    _audio.reset();
    if (resetChecks) _document.selectAll();
  }

  Future<void> _selectOutputDirectory() async {
    try {
      final selected = await OutputDirectoryService.select();
      if (selected == null) return;
      await OutputDirectoryService.verify(selected.id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('output_directory', selected.id);
      await prefs.setString('output_directory_label', selected.label);
      if (!mounted) return;
      setState(() {
        _outputDirectory = selected.id;
        _outputDirectoryLabel = selected.label;
        _resetGeneration();
        _status = s.get('outputSelected');
      });
    } catch (_) {
      _showError(s.get('outputNotWritable'));
    }
  }

  Future<void> _clearOutputDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('output_directory');
    await prefs.remove('output_directory_label');
    if (!mounted) return;
    setState(() {
      _outputDirectory = null;
      _outputDirectoryLabel = null;
      _resetGeneration();
      _status = '';
    });
  }

  List<Chapter> get _units => _document.units;

  Future<TtsProvider> _provider() => _tts.createProvider(
    deviceEngineRequiredMessage: s.get('deviceEngineRequired'),
  );

  List<String> get _voiceLocales => _tts.voiceLocales;

  List<VoiceInfo> get _filteredVoices => _tts.filteredVoices;

  String _preferredVoiceLocale(List<VoiceInfo> voices) =>
      TtsSettingsController.preferredVoiceLocale(
        voices,
        Localizations.localeOf(context).languageCode,
      );

  Future<void> _loadVoices() async => _run(() async {
    final provider = await _provider();
    try {
      final voices = await provider.listVoices();
      voices.sort(
        (a, b) => '${a.locale}${a.name}'.compareTo('${b.locale}${b.name}'),
      );
      if (!mounted) return;
      final locale = voices.isEmpty ? null : _preferredVoiceLocale(voices);
      final matching = voices.where((voice) => voice.locale == locale).toList();
      setState(() {
        _tts.voices = voices;
        _tts.voiceLocale = locale;
        _tts.voice = matching.isEmpty ? null : matching.first;
        _status = '${voices.length} voices';
      });
    } finally {
      closeTtsProvider(provider);
    }
  });

  Future<void> _loadDeviceEngines() async {
    await _run(() async {
      final engines = await DeviceTtsProvider.listEngines();
      if (engines.isEmpty) {
        throw TtsProviderException(s.get('deviceEngineMissing'));
      }
      final saved = _tts.deviceTtsEngine;
      final selected = engines.any((engine) => engine.name == saved)
          ? saved
          : engines
                .firstWhere(
                  (engine) => engine.isDefault,
                  orElse: () => engines.first,
                )
                .name;
      if (!mounted) return;
      setState(() {
        _tts.deviceTtsEngines = engines;
        _tts.deviceTtsEngine = selected;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_tts_engine', selected!);
    });
    if (_tts.deviceTtsEngine != null) await _loadVoices();
  }

  Future<void> _preview() async {
    if (_document.chapters.isEmpty) return _showError(s.get('noFile'));
    await _run(() async {
      final units = _units;
      if (units.isEmpty) {
        throw FormatException(s.get('invalidChars'));
      }
      final voice = _tts.voice;
      if (voice == null) {
        throw TtsProviderException(s.get('voiceRequired'));
      }
      final unit =
          units[(_document.selectedIndex ?? 0).clamp(0, units.length - 1)];
      final provider = await _provider();
      await _audio.preview(
        provider: provider,
        unit: unit,
        voiceName: voice.name,
        ratePercent: _tts.ratePercent,
        volumePercent: _tts.volumePercent,
        pitchHz: _tts.pitchHz,
        autoSplit: _tts.providerName != 'google' || _tts.ttsAutoSplit,
        autoRetry: _tts.ttsAutoRetry,
        onChunkProgress: _updatePreviewChunkProgress,
      );
    });
  }

  Future<void> _stopPreview() async {
    try {
      await _audio.stopPreview();
      if (!mounted) return;
      setState(() {
        _isPreviewPlaying = false;
        _status = s.get('previewStopped');
      });
    } catch (error) {
      if (mounted) setState(() => _isPreviewPlaying = false);
      _showError(error);
    }
  }

  Future<void> _generate({bool resume = false}) async {
    if (_document.chapters.isEmpty) return _showError(s.get('noFile'));
    _audio.prepareGeneration();
    setState(() => _isGenerating = true);
    try {
      await _run(() async {
        final units = _units;
        if (units.isEmpty) {
          throw FormatException(s.get('invalidChars'));
        }
        final selectedIndices = _document.selectedUnitIndices;
        final selectedUnits = selectedIndices
            .map((index) => units[index])
            .toList();
        if (selectedUnits.isEmpty) {
          throw FormatException(s.get('noUnitsChecked'));
        }
        final voice = _tts.voice;
        if (voice == null) {
          throw TtsProviderException(s.get('voiceRequired'));
        }
        final outputDirectory = _outputDirectory;
        if (outputDirectory != null) {
          try {
            await OutputDirectoryService.verify(outputDirectory);
          } catch (_) {
            throw TtsProviderException(s.get('outputNotWritable'));
          }
        }
        if (!resume) {
          _audio.generatedPaths.clear();
          _audio.resumeIndex = 0;
        }
        final provider = await _provider();
        final paths = await _audio.generate(
          provider: provider,
          units: selectedUnits,
          voiceName: voice.name,
          outputDirectory: outputDirectory,
          ratePercent: _tts.ratePercent,
          volumePercent: _tts.volumePercent,
          pitchHz: _tts.pitchHz,
          autoSplit: _tts.providerName != 'google' || _tts.ttsAutoSplit,
          autoRetry: _tts.ttsAutoRetry,
          onChunkProgress: (unit, unitTotal, chunk, chunkTotal, retrying) {
            if (!mounted || !_tts.ttsShowProgress) return;
            setState(
              () => _status =
                  '${s.get('unitProgress')} $unit/$unitTotal — '
                  '${s.get(retrying ? 'ttsRetrying' : 'ttsChunkProgress')} '
                  '$chunk/$chunkTotal',
            );
          },
          onProgress: (current, total) {
            if (mounted) setState(() => _status = '$current / $total');
          },
          onFileGenerated: (path, current, total) {
            if (!mounted) return;
            setState(() {
              if (!_audio.generatedPaths.contains(path)) {
                _audio.generatedPaths.add(path);
              }
              _document.checkedUnitIndices.remove(selectedIndices[current - 1]);
              _audio.resumeIndex = current < total ? 0 : null;
            });
          },
        );
        if (!mounted) return;
        setState(() {
          _audio.resumeIndex = null;
          _status = s.get('done');
        });
        if (outputDirectory == null) {
          await Share.shareXFiles(paths.map(XFile.new).toList());
          if (!mounted) return;
          await _askDeleteSharedFiles(paths);
        }
      });
    } finally {
      _audio.clearPendingGeneration();
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _askDeleteSharedFiles(List<String> paths) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.get('deleteSharedTitle')),
        content: Text(s.get('deleteSharedMessage')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.get('keepFiles')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.get('deleteFiles')),
          ),
        ],
      ),
    );
    if (delete == true) {
      await AudioGenerator.deleteFiles(paths);
      _audio.generatedPaths.clear();
      if (mounted) setState(() => _status = s.get('filesDeleted'));
    } else if (mounted) {
      setState(() => _status = s.get('filesKept'));
    }
  }

  void _updatePreviewChunkProgress(int current, int total, bool retrying) {
    if (!mounted || !_tts.ttsShowProgress) return;
    setState(
      () => _status =
          '${s.get(retrying ? 'ttsRetrying' : 'ttsChunkProgress')} '
          '$current/$total',
    );
  }

  void _resetAudioAdjustments() {
    if (_busy) return;
    setState(() {
      _tts.ratePercent = 0;
      _tts.volumePercent = 0;
      _tts.pitchHz = 0;
      _resetGeneration();
    });
    unawaited(_saveAudioAdjustments());
  }

  Future<void> _saveAudioAdjustments() => _tts.saveAudioAdjustments();

  Future<void> _saveTtsOptions() => _tts.saveTtsOptions();

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _tts.saveRunOptions(
        splitByChars: _document.splitByChars,
        maxCharsText: _document.charsController.text,
      );
    } catch (error) {
      if (error is AudioGenerationCancelled) {
        if (mounted) setState(() => _status = s.get('generationCancelled'));
      } else {
        _showError(error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    final message = error is PdfReadException
        ? s.get(error.messageKey)
        : '$error';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _changeProvider(String provider) async {
    final key = await _tts.credentials.read(provider, 'api_key') ?? '';
    final region = await _tts.credentials.read(provider, 'region') ?? '';
    if (!mounted) return;
    setState(() {
      _tts.providerName = provider;
      _tts.keyController.text = key;
      _tts.regionController.text = region;
      _tts.voices = const [];
      _tts.voiceLocale = null;
      _tts.voice = null;
    });
    if (provider == 'device') {
      await _loadDeviceEngines();
    } else if (provider == 'edge' ||
        (key.isNotEmpty && (provider != 'azure' || region.isNotEmpty))) {
      await _loadVoices();
    }
  }

  Future<void> _changeDeviceEngine(String engine) async {
    setState(() {
      _tts.deviceTtsEngine = engine;
      _tts.voices = const [];
      _tts.voiceLocale = null;
      _tts.voice = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_tts_engine', engine);
    if (mounted) await _loadVoices();
  }

  Future<void> _forgetCredentials() async {
    await _tts.credentials.deleteProvider(_tts.providerName);
    if (!mounted) return;
    _tts.keyController.clear();
    if (_tts.providerName == 'azure') _tts.regionController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final units = _units;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.get('title')),
        actions: [
          IconButton(
            tooltip: s.get('about'),
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AppInformationScreen(
                  version: _appVersion,
                  buildNumber: _appBuildNumber,
                  openProject: () => _openExternalLink(projectContactUrl),
                ),
              ),
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: Localizations.localeOf(context).languageCode,
              items: const [
                DropdownMenuItem(value: 'ja', child: Text('日本語')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'zh', child: Text('简体中文')),
              ],
              onChanged: (value) {
                if (value != null) widget.onLocaleChanged(Locale(value));
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(s.get('file'), style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              Expanded(
                child: Text(
                  _document.fileName ?? '—',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              FilledButton.tonal(
                onPressed: _busy ? null : _selectFile,
                child: Text(s.get('choose')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('text-encoding-${_document.textEncoding}'),
            initialValue: _document.textEncoding,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.get('textEncoding')),
            items: DocumentReader.textEncodings
                .map(
                  (encoding) => DropdownMenuItem(
                    value: encoding,
                    child: Text(s.get('encoding_$encoding')),
                  ),
                )
                .toList(),
            onChanged: _busy
                ? null
                : (encoding) {
                    if (encoding != null) _changeTextEncoding(encoding);
                  },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _selectOutputDirectory,
                  icon: const Icon(Icons.folder_open),
                  label: Text(s.get('selectOutput')),
                ),
              ),
              if (_outputDirectory != null)
                IconButton(
                  tooltip: s.get('clearOutput'),
                  onPressed: _busy ? null : _clearOutputDirectory,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          Text(
            _outputDirectoryLabel ??
                _outputDirectory ??
                s.get('outputNotSelected'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ProviderSettingsSection(
            strings: s,
            settings: _tts,
            busy: _busy,
            onProviderChanged: _changeProvider,
            onDeviceEngineChanged: _changeDeviceEngine,
            onPrivacy: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
            ),
            onPersistChanged: (value) => setState(() => _tts.persist = value),
            onForgetCredentials: _forgetCredentials,
          ),
          const Divider(height: 32),
          Text(s.get('split'), style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(s.get('chapter'))),
              ButtonSegment(value: true, label: Text(s.get('chars'))),
            ],
            selected: {_document.splitByChars},
            onSelectionChanged: _busy
                ? null
                : (values) => setState(() {
                    _document.splitByChars = values.first;
                    _resetGeneration(resetChecks: true);
                  }),
          ),
          if (_document.splitByChars)
            TextField(
              controller: _document.charsController,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.get('maxChars')),
              onChanged: (_) =>
                  setState(() => _resetGeneration(resetChecks: true)),
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _loadVoices,
            child: Text(s.get('loadVoices')),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('voice-locale-${_tts.voiceLocale}'),
            initialValue: _tts.voiceLocale,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.get('voiceLanguage')),
            items: _voiceLocales
                .map(
                  (locale) =>
                      DropdownMenuItem(value: locale, child: Text(locale)),
                )
                .toList(),
            onChanged: _busy || _tts.voices.isEmpty
                ? null
                : (locale) {
                    if (locale == null) return;
                    setState(() {
                      _tts.voiceLocale = locale;
                      _tts.voice = _tts.voices.firstWhere(
                        (voice) => voice.locale == locale,
                      );
                    });
                  },
          ),
          DropdownButtonFormField<VoiceInfo>(
            key: ValueKey(_tts.voice),
            initialValue: _tts.voice,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.get('voice')),
            items: _filteredVoices
                .map(
                  (voice) => DropdownMenuItem(
                    value: voice,
                    child: Text(voice.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: _busy || _tts.voices.isEmpty
                ? null
                : (value) => setState(() => _tts.voice = value),
          ),
          if (_tts.voices.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s.get('voiceNotLoaded')),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.get('audioAdjustments'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _busy ? null : _resetAudioAdjustments,
                icon: const Icon(Icons.restart_alt),
                label: Text(s.get('resetAudio')),
              ),
            ],
          ),
          AudioAdjustmentSlider(
            label: s.get('rate'),
            value: _tts.ratePercent,
            suffix: '%',
            enabled: !_busy,
            onChanged: (value) => setState(() {
              _tts.ratePercent = value;
              _resetGeneration();
            }),
          ),
          AudioAdjustmentSlider(
            label: s.get('volume'),
            value: _tts.volumePercent,
            suffix: '%',
            enabled: !_busy,
            onChanged: (value) => setState(() {
              _tts.volumePercent = value;
              _resetGeneration();
            }),
          ),
          AudioAdjustmentSlider(
            label: s.get('pitch'),
            value: _tts.pitchHz,
            suffix: ' Hz',
            enabled: !_busy,
            onChanged: (value) => setState(() {
              _tts.pitchHz = value;
              _resetGeneration();
            }),
          ),
          if (_tts.providerName == 'google') ...[
            const SizedBox(height: 12),
            Text(
              s.get('ttsLongText'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.get('ttsAutoSplit')),
              value: _tts.ttsAutoSplit,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() {
                        _tts.ttsAutoSplit = value;
                        _resetGeneration();
                      });
                      unawaited(_saveTtsOptions());
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.get('ttsAutoRetry')),
              value: _tts.ttsAutoRetry,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() {
                        _tts.ttsAutoRetry = value;
                        _resetGeneration();
                      });
                      unawaited(_saveTtsOptions());
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.get('ttsShowProgress')),
              value: _tts.ttsShowProgress,
              onChanged: _busy
                  ? null
                  : (value) {
                      setState(() => _tts.ttsShowProgress = value);
                      unawaited(_saveTtsOptions());
                    },
            ),
            if (_tts.voice?.name.toLowerCase().contains('-chirp3-hd-') ?? false)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  s.get('ttsChirpLimited'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
          if (widget.adFreeController != null &&
              !kIsWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              !widget.adFreeController!.isAdFree)
            AdFreeSection(purchase: widget.adFreeController!, strings: s),
          const Divider(height: 32),
          Text(
            s.get('appearance'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.brightness_auto_outlined),
                label: Text(s.get('themeSystem')),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_outlined),
                label: Text(s.get('themeLight')),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode_outlined),
                label: Text(s.get('themeDark')),
              ),
            ],
            selected: {widget.themeMode},
            onSelectionChanged: (values) =>
                widget.onThemeModeChanged?.call(values.first),
          ),
          OutputUnitsSection(
            strings: s,
            units: units,
            checkedIndices: _document.checkedUnitIndices,
            selectedIndex: _document.selectedIndex,
            busy: _busy,
            onSelectAll: () => setState(() {
              _resetGeneration();
              _document.selectAll();
            }),
            onDeselectAll: () => setState(() {
              _resetGeneration();
              _document.clearSelection();
            }),
            onToggle: (index, checked) => setState(() {
              _resetGeneration();
              _document.toggleSelection(index, checked);
            }),
            onTap: (index) => setState(() => _document.selectedIndex = index),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status, textAlign: TextAlign.center),
            ),
          const Divider(height: 32),
          if (_showLimitations)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(s.get('unsupported')),
                subtitle: Text(s.get('limitations')),
                trailing: IconButton(
                  tooltip: s.get('hide'),
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    setState(() => _showLimitations = false);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('show_mobile_limitations', false);
                  },
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: GenerationActions(
        strings: s,
        busy: _busy,
        generating: _isGenerating && _audio.canCancel,
        previewPlaying: _isPreviewPlaying,
        showProgress: _tts.ttsShowProgress,
        status: _status,
        showBanner:
            widget.adFreeController == null ||
            !widget.adFreeController!.isAdFree,
        canGenerateResume: _audio.resumeIndex != null,
        onPreview: _isPreviewPlaying ? _stopPreview : _preview,
        onGenerate: () => _generate(resume: _audio.resumeIndex != null),
        onCancel: () {
          if (!_audio.canCancel) return;
          _audio.cancel();
          setState(() => _status = s.get('generationCancelling'));
        },
      ),
    );
  }
}
