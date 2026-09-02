import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/strings.dart';
import 'models/chapter.dart';
import 'providers/azure_provider.dart';
import 'providers/device_tts_provider.dart';
import 'providers/edge_provider.dart';
import 'providers/google_provider.dart';
import 'providers/tts_provider.dart';
import 'services/audio_generator.dart';
import 'services/credential_store.dart';
import 'services/document_reader.dart';
import 'services/output_directory_service.dart';
import 'services/preview_audio_player.dart';
import 'services/text_splitter.dart';

void main() => runApp(const TtsMobileApp());

class TtsMobileApp extends StatefulWidget {
  const TtsMobileApp({
    this.previewPlayer,
    this.initialChapters = const [],
    super.key,
  });

  final PreviewAudioPlayer? previewPlayer;
  final List<Chapter> initialChapters;

  @override
  State<TtsMobileApp> createState() => _TtsMobileAppState();
}

class _TtsMobileAppState extends State<TtsMobileApp> {
  Locale? locale;

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
        title: 'TTS Text to MP3',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: HomeScreen(
          onLocaleChanged: (value) => setState(() => locale = value),
          previewPlayer: widget.previewPlayer,
          initialChapters: widget.initialChapters,
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onLocaleChanged,
    this.previewPlayer,
    this.initialChapters = const [],
    super.key,
  });
  final ValueChanged<Locale> onLocaleChanged;
  final PreviewAudioPlayer? previewPlayer;
  final List<Chapter> initialChapters;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _credentials = CredentialStore();
  final _keyController = TextEditingController();
  final _regionController = TextEditingController();
  final _charsController = TextEditingController(text: '5000');
  late final PreviewAudioPlayer _player;
  StreamSubscription<bool>? _playerSubscription;

  String _providerName = 'azure';
  String _textEncoding = 'auto';
  bool _persist = true;
  bool _splitByChars = false;
  bool _busy = false;
  bool _isPreviewPlaying = false;
  bool _showLimitations = true;
  double _ratePercent = 0;
  double _volumePercent = 0;
  double _pitchHz = 0;
  String? _fileName;
  Uint8List? _fileBytes;
  String? _outputDirectory;
  String? _outputDirectoryLabel;
  List<Chapter> _chapters = const [];
  List<VoiceInfo> _voices = const [];
  List<DeviceTtsEngine> _deviceTtsEngines = const [];
  String? _deviceTtsEngine;
  String? _voiceLocale;
  VoiceInfo? _voice;
  int? _selectedIndex;
  int? _resumeIndex;
  final Set<int> _checkedUnitIndices = {};
  final List<String> _generatedPaths = [];
  String _status = '';

  @override
  void initState() {
    super.initState();
    _player = widget.previewPlayer ?? JustAudioPreviewPlayer();
    _playerSubscription = _player.playingStream.listen(
      _onPreviewPlayingChanged,
      onError: (_) => _onPreviewPlayingChanged(false),
    );
    _chapters = widget.initialChapters;
    _checkedUnitIndices.addAll(
      List.generate(_units.length, (index) => index),
    );
    _restore();
  }

  @override
  void dispose() {
    _credentials.clearSession();
    _keyController.dispose();
    _regionController.dispose();
    _charsController.dispose();
    unawaited(_disposePlayer());
    super.dispose();
  }

  Future<void> _disposePlayer() async {
    await _playerSubscription?.cancel();
    await _player.stop();
    await _player.dispose();
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
    final key = await _credentials.read(provider, 'api_key') ?? '';
    final region = await _credentials.read(provider, 'region') ?? '';
    if (!mounted) return;
    setState(() {
      _providerName = provider == 'device' &&
              defaultTargetPlatform != TargetPlatform.android
          ? 'edge'
          : provider;
      _textEncoding = prefs.getString('text_encoding') ?? 'auto';
      if (!DocumentReader.textEncodings.contains(_textEncoding)) {
        _textEncoding = 'auto';
      }
      _keyController.text = key;
      _regionController.text = region;
      _splitByChars = prefs.getBool('split_by_chars') ?? false;
      _charsController.text = (prefs.getInt('max_chars') ?? 5000).toString();
      _showLimitations = prefs.getBool('show_mobile_limitations') ?? true;
      _ratePercent = prefs.getDouble('rate_percent') ?? 0;
      _volumePercent = prefs.getDouble('volume_percent') ?? 0;
      _pitchHz = prefs.getDouble('pitch_hz') ?? 0;
      _outputDirectory = prefs.getString('output_directory');
      _outputDirectoryLabel = prefs.getString('output_directory_label');
      _deviceTtsEngine = prefs.getString('device_tts_engine');
    });
    if (_providerName == 'device') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeviceEngines());
    } else if (_providerName == 'edge' ||
        (key.isNotEmpty && (provider != 'azure' || region.isNotEmpty))) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadVoices());
    }
  }

  Future<void> _selectFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub'],
      withData: true,
    );
    if (result == null) return;
    try {
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw const FormatException('Could not read file.');
      final chapters = await DocumentReader.read(
        file.name,
        bytes,
        textEncoding: _textEncoding,
      );
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _fileBytes = bytes;
        _chapters = chapters;
        _selectedIndex = null;
        _resetGeneration(resetChecks: true);
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _changeTextEncoding(String encoding) async {
    final name = _fileName;
    final bytes = _fileBytes;
    if (name == null || bytes == null || !name.toLowerCase().endsWith('.txt')) {
      setState(() => _textEncoding = encoding);
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
        _textEncoding = encoding;
        _chapters = chapters;
        _selectedIndex = null;
        _resetGeneration(resetChecks: true);
        _status = s.get('encodingReloaded');
      });
    });
  }

  void _resetGeneration({bool resetChecks = false}) {
    _resumeIndex = null;
    _generatedPaths.clear();
    if (resetChecks) {
      _checkedUnitIndices
        ..clear()
        ..addAll(List.generate(_units.length, (index) => index));
    }
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

  List<Chapter> get _units {
    if (!_splitByChars) return _chapters;
    final count = int.tryParse(_charsController.text);
    if (count == null || count <= 0) return const [];
    return splitChaptersByChars(_chapters, count);
  }

  Future<TtsProvider> _provider() async {
    if (_providerName == 'edge') return EdgeProvider();
    if (_providerName == 'device') {
      final engine = _deviceTtsEngine;
      if (engine == null) {
        throw TtsProviderException(s.get('deviceEngineRequired'));
      }
      return DeviceTtsProvider(engine);
    }
    final key = _keyController.text.trim();
    if (key.isEmpty) throw const TtsProviderException('API key is required.');
    await _credentials.write(
      _providerName,
      'api_key',
      key,
      persist: _persist,
    );
    if (_providerName == 'azure') {
      final region = _regionController.text.trim();
      if (region.isEmpty) {
        throw const TtsProviderException('Azure region is required.');
      }
      await _credentials.write('azure', 'region', region, persist: _persist);
      return AzureProvider(key: key, region: region);
    }
    return GoogleProvider(apiKey: key);
  }

  List<String> get _voiceLocales =>
      _voices.map((voice) => voice.locale).toSet().toList()..sort();

  List<VoiceInfo> get _filteredVoices => _voiceLocale == null
      ? const []
      : _voices.where((voice) => voice.locale == _voiceLocale).toList();

  String _preferredVoiceLocale(List<VoiceInfo> voices) {
    final language = Localizations.localeOf(context).languageCode;
    final preferred = switch (language) {
      'ja' => 'ja-JP',
      'zh' => 'zh-CN',
      _ => 'en-US',
    };
    return voices.any((voice) => voice.locale == preferred)
        ? preferred
        : voices.first.locale;
  }

  Future<void> _loadVoices() async => _run(() async {
        final provider = await _provider();
        final voices = await provider.listVoices();
        voices.sort(
            (a, b) => '${a.locale}${a.name}'.compareTo('${b.locale}${b.name}'));
        if (!mounted) return;
        final locale = voices.isEmpty ? null : _preferredVoiceLocale(voices);
        final matching =
            voices.where((voice) => voice.locale == locale).toList();
        setState(() {
          _voices = voices;
          _voiceLocale = locale;
          _voice = matching.isEmpty ? null : matching.first;
          _status = '${voices.length} voices';
        });
      });

  Future<void> _loadDeviceEngines() async {
    await _run(() async {
      final engines = await DeviceTtsProvider.listEngines();
      if (engines.isEmpty) {
        throw TtsProviderException(s.get('deviceEngineMissing'));
      }
      final saved = _deviceTtsEngine;
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
        _deviceTtsEngines = engines;
        _deviceTtsEngine = selected;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_tts_engine', selected!);
    });
    if (_deviceTtsEngine != null) await _loadVoices();
  }

  Future<void> _preview() async {
    if (_chapters.isEmpty) return _showError(s.get('noFile'));
    await _run(() async {
      final units = _units;
      if (units.isEmpty) {
        throw FormatException(s.get('invalidChars'));
      }
      final voice = _voice;
      if (voice == null) {
        throw TtsProviderException(s.get('voiceRequired'));
      }
      final unit = units[(_selectedIndex ?? 0).clamp(0, units.length - 1)];
      final provider = await _provider();
      final bytes = await provider.synthesize(
        previewText(unit.text),
        voice.name,
        rate: 1 + _ratePercent / 100,
        volume: _volumePercent,
        pitch: _pitchHz,
      );
      final file =
          await AudioGenerator.writeTemporary(bytes, 'tts-preview.mp3');
      await _player.setFilePath(file);
      await _player.play();
    });
  }

  Future<void> _stopPreview() async {
    try {
      await _player.stop();
      await _player.seekToStart();
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
    if (_chapters.isEmpty) return _showError(s.get('noFile'));
    await _run(() async {
      final units = _units;
      if (units.isEmpty) {
        throw FormatException(s.get('invalidChars'));
      }
      final selectedIndices = _checkedUnitIndices
          .where((index) => index >= 0 && index < units.length)
          .toList()
        ..sort();
      final selectedUnits =
          selectedIndices.map((index) => units[index]).toList();
      if (selectedUnits.isEmpty) {
        throw FormatException(s.get('noUnitsChecked'));
      }
      final voice = _voice;
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
      const startIndex = 0;
      if (!resume) {
        _generatedPaths.clear();
        _resumeIndex = 0;
      }
      final provider = await _provider();
      final paths = await AudioGenerator.generateAll(
        provider,
        selectedUnits,
        voice.name,
        outputDirectory: outputDirectory == null ||
                OutputDirectoryService.isAndroidDocumentTree(outputDirectory)
            ? null
            : outputDirectory,
        fileWriter: outputDirectory != null &&
                OutputDirectoryService.isAndroidDocumentTree(outputDirectory)
            ? (filename, bytes) => OutputDirectoryService.writeFile(
                  outputDirectory,
                  filename,
                  bytes,
                )
            : null,
        startIndex: startIndex,
        existingPaths: _generatedPaths,
        rate: 1 + _ratePercent / 100,
        volume: _volumePercent,
        pitch: _pitchHz,
        onProgress: (current, total) {
          if (mounted) setState(() => _status = '$current / $total');
        },
        onFileGenerated: (path, current, total) {
          if (!mounted) return;
          setState(() {
            if (!_generatedPaths.contains(path)) _generatedPaths.add(path);
            _checkedUnitIndices.remove(selectedIndices[current - 1]);
            _resumeIndex = current < total ? 0 : null;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _resumeIndex = null;
        _status = s.get('done');
      });
      if (outputDirectory == null) {
        await Share.shareXFiles(paths.map(XFile.new).toList());
        if (!mounted) return;
        await _askDeleteSharedFiles(paths);
      }
    });
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
      _generatedPaths.clear();
      if (mounted) setState(() => _status = s.get('filesDeleted'));
    } else if (mounted) {
      setState(() => _status = s.get('filesKept'));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('provider', _providerName);
      await prefs.setBool('split_by_chars', _splitByChars);
      await prefs.setInt(
          'max_chars', int.tryParse(_charsController.text) ?? 5000);
      await prefs.setDouble('rate_percent', _ratePercent);
      await prefs.setDouble('volume_percent', _volumePercent);
      await prefs.setDouble('pitch_hz', _pitchHz);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
  }

  @override
  Widget build(BuildContext context) {
    final units = _units;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.get('title')),
        actions: [
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
          Row(children: [
            Expanded(
                child: Text(_fileName ?? '—', overflow: TextOverflow.ellipsis)),
            FilledButton.tonal(
                onPressed: _busy ? null : _selectFile,
                child: Text(s.get('choose'))),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('text-encoding-$_textEncoding'),
            initialValue: _textEncoding,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.get('textEncoding')),
            items: DocumentReader.textEncodings
                .map((encoding) => DropdownMenuItem(
                      value: encoding,
                      child: Text(s.get('encoding_$encoding')),
                    ))
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
          Text(s.get('provider'),
              style: Theme.of(context).textTheme.titleMedium),
          DropdownButtonFormField<String>(
            initialValue: _providerName,
            decoration: InputDecoration(labelText: s.get('provider')),
            items: [
              DropdownMenuItem(
                  value: 'edge', child: Text(s.get('providerEdge'))),
              if (defaultTargetPlatform == TargetPlatform.android)
                DropdownMenuItem(
                    value: 'device', child: Text(s.get('deviceTts'))),
              const DropdownMenuItem(
                  value: 'azure', child: Text('Azure Speech')),
              const DropdownMenuItem(
                  value: 'google', child: Text('Google Cloud TTS')),
            ],
            onChanged: _busy
                ? null
                : (provider) async {
                    if (provider == null) return;
                    final key =
                        await _credentials.read(provider, 'api_key') ?? '';
                    final region =
                        await _credentials.read(provider, 'region') ?? '';
                    setState(() {
                      _providerName = provider;
                      _keyController.text = key;
                      _regionController.text = region;
                      _voices = const [];
                      _voiceLocale = null;
                      _voice = null;
                    });
                    if (provider == 'device') {
                      await _loadDeviceEngines();
                    } else if (provider == 'edge' ||
                        (key.isNotEmpty &&
                            (provider != 'azure' || region.isNotEmpty))) {
                      await _loadVoices();
                    }
                  },
          ),
          const SizedBox(height: 8),
          if (_providerName == 'device') ...[
            DropdownButtonFormField<String>(
              key: ValueKey('device-engine-$_deviceTtsEngine'),
              initialValue: _deviceTtsEngine,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.get('deviceTtsEngine')),
              items: _deviceTtsEngines
                  .map((engine) => DropdownMenuItem(
                        value: engine.name,
                        child: Text(
                          engine.isDefault
                              ? '${engine.label} (${s.get('defaultEngine')})'
                              : engine.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: _busy
                  ? null
                  : (engine) async {
                      if (engine == null) return;
                      setState(() {
                        _deviceTtsEngine = engine;
                        _voices = const [];
                        _voiceLocale = null;
                        _voice = null;
                      });
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('device_tts_engine', engine);
                      await _loadVoices();
                    },
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                s.get('deviceTtsNote'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          if (_providerName == 'azure' || _providerName == 'google')
            TextField(
                controller: _keyController,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(labelText: s.get('apiKey'))),
          if (_providerName == 'azure')
            TextField(
                controller: _regionController,
                autocorrect: false,
                decoration: InputDecoration(labelText: s.get('region'))),
          if (_providerName == 'azure' || _providerName == 'google') ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _persist,
              title: Text(s.get('persist')),
              onChanged: (value) => setState(() => _persist = value),
            ),
            TextButton.icon(
              onPressed: () async {
                await _credentials.deleteProvider(_providerName);
                _keyController.clear();
                if (_providerName == 'azure') _regionController.clear();
              },
              icon: const Icon(Icons.delete_outline),
              label: Text(s.get('forget')),
            ),
          ],
          const Divider(height: 32),
          Text(s.get('split'), style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(s.get('chapter'))),
              ButtonSegment(value: true, label: Text(s.get('chars'))),
            ],
            selected: {_splitByChars},
            onSelectionChanged: _busy
                ? null
                : (values) => setState(() {
                      _splitByChars = values.first;
                      _resetGeneration(resetChecks: true);
                    }),
          ),
          if (_splitByChars)
            TextField(
                controller: _charsController,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.get('maxChars')),
                onChanged: (_) =>
                    setState(() => _resetGeneration(resetChecks: true))),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: _busy ? null : _loadVoices,
              child: Text(s.get('loadVoices'))),
          DropdownButtonFormField<String>(
            key: ValueKey('voice-locale-$_voiceLocale'),
            initialValue: _voiceLocale,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.get('voiceLanguage')),
            items: _voiceLocales
                .map((locale) =>
                    DropdownMenuItem(value: locale, child: Text(locale)))
                .toList(),
            onChanged: _busy || _voices.isEmpty
                ? null
                : (locale) {
                    if (locale == null) return;
                    setState(() {
                      _voiceLocale = locale;
                      _voice = _voices.firstWhere(
                        (voice) => voice.locale == locale,
                      );
                    });
                  },
          ),
          DropdownButtonFormField<VoiceInfo>(
            key: ValueKey(_voice),
            initialValue: _voice,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.get('voice')),
            items: _filteredVoices
                .map((voice) => DropdownMenuItem(
                    value: voice,
                    child: Text(voice.name, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: _busy || _voices.isEmpty
                ? null
                : (value) => setState(() => _voice = value),
          ),
          if (_voices.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s.get('voiceNotLoaded')),
            ),
          const SizedBox(height: 12),
          Text(s.get('audioAdjustments'),
              style: Theme.of(context).textTheme.titleMedium),
          _AudioSlider(
            label: s.get('rate'),
            value: _ratePercent,
            suffix: '%',
            enabled: !_busy,
            onChanged: (value) => setState(() {
              _ratePercent = value;
              _resetGeneration();
            }),
          ),
          _AudioSlider(
            label: s.get('volume'),
            value: _volumePercent,
            suffix: '%',
            enabled: !_busy,
            onChanged: (value) => setState(() {
              _volumePercent = value;
              _resetGeneration();
            }),
          ),
          _AudioSlider(
            label: s.get('pitch'),
            value: _pitchHz,
            suffix: ' Hz',
            enabled: !_busy,
            onChanged: (value) => setState(() {
              _pitchHz = value;
              _resetGeneration();
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(s.get('outputUnits'),
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton(
                onPressed: _busy || units.isEmpty
                    ? null
                    : () => setState(() {
                          _resetGeneration();
                          _checkedUnitIndices.addAll(
                              List.generate(units.length, (index) => index));
                        }),
                child: Text(s.get('selectAll')),
              ),
              TextButton(
                onPressed: _busy || units.isEmpty
                    ? null
                    : () => setState(() {
                          _resetGeneration();
                          _checkedUnitIndices.clear();
                        }),
                child: Text(s.get('deselectAll')),
              ),
            ],
          ),
          if (units.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(s.get('outputUnitsEmpty')),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: units.length,
              itemBuilder: (context, index) => ListTile(
                selected: _selectedIndex == index,
                leading: Checkbox(
                  value: _checkedUnitIndices.contains(index),
                  onChanged: _busy
                      ? null
                      : (checked) => setState(() {
                            _resetGeneration();
                            if (checked == true) {
                              _checkedUnitIndices.add(index);
                            } else {
                              _checkedUnitIndices.remove(index);
                            }
                          }),
                ),
                title: Text(units[index].title),
                subtitle:
                    Text('${units[index].text.length} ${s.get('characters')}'),
                onTap: () => setState(() => _selectedIndex = index),
              ),
            ),
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
          if (_status.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status, textAlign: TextAlign.center)),
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
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: _isPreviewPlaying
                      ? _stopPreview
                      : (_busy ? null : _preview),
                  icon: Icon(_isPreviewPlaying ? Icons.stop : Icons.play_arrow),
                  label: Text(
                      s.get(_isPreviewPlaying ? 'stopPreview' : 'preview')))),
          const SizedBox(width: 8),
          Expanded(
              child: FilledButton.icon(
                  onPressed: _busy || _isPreviewPlaying
                      ? null
                      : () => _generate(resume: _resumeIndex != null),
                  icon: const Icon(Icons.download),
                  label: Text(_resumeIndex == null
                      ? s.get('generate')
                      : s.get('resumeGenerate')))),
        ]),
      ),
    );
  }
}

class _AudioSlider extends StatelessWidget {
  const _AudioSlider({
    required this.label,
    required this.value,
    required this.suffix,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String suffix;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 64, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: -50,
              max: 50,
              divisions: 100,
              onChanged: enabled ? onChanged : null,
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              '${value >= 0 ? '+' : ''}${value.round()}$suffix',
              textAlign: TextAlign.end,
            ),
          ),
        ],
      );
}
