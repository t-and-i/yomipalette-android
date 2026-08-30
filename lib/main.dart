import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/strings.dart';
import 'models/chapter.dart';
import 'providers/azure_provider.dart';
import 'providers/google_provider.dart';
import 'providers/tts_provider.dart';
import 'services/audio_generator.dart';
import 'services/credential_store.dart';
import 'services/document_reader.dart';
import 'services/text_splitter.dart';

void main() => runApp(const TtsMobileApp());

class TtsMobileApp extends StatefulWidget {
  const TtsMobileApp({super.key});

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
        title: 'TTS Text to MP3',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: HomeScreen(
            onLocaleChanged: (value) => setState(() => locale = value)),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.onLocaleChanged, super.key});
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _credentials = CredentialStore();
  final _keyController = TextEditingController();
  final _regionController = TextEditingController();
  final _charsController = TextEditingController(text: '5000');
  final _player = AudioPlayer();

  String _providerName = 'azure';
  bool _persist = true;
  bool _splitByChars = false;
  bool _busy = false;
  String? _fileName;
  List<Chapter> _chapters = const [];
  List<VoiceInfo> _voices = const [];
  VoiceInfo? _voice;
  int? _selectedIndex;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _credentials.clearSession();
    _keyController.dispose();
    _regionController.dispose();
    _charsController.dispose();
    _player.dispose();
    super.dispose();
  }

  AppStrings get s => AppStrings(Localizations.localeOf(context));

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final provider = prefs.getString('provider') ?? 'azure';
    final key = await _credentials.read(provider, 'api_key') ?? '';
    final region = await _credentials.read(provider, 'region') ?? '';
    if (!mounted) return;
    setState(() {
      _providerName = provider;
      _keyController.text = key;
      _regionController.text = region;
      _splitByChars = prefs.getBool('split_by_chars') ?? false;
      _charsController.text = (prefs.getInt('max_chars') ?? 5000).toString();
    });
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
      final chapters = await DocumentReader.read(file.name, bytes);
      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _chapters = chapters;
        _selectedIndex = null;
      });
    } catch (error) {
      _showError(error);
    }
  }

  List<Chapter> get _units {
    if (!_splitByChars) return _chapters;
    final count = int.tryParse(_charsController.text);
    if (count == null || count <= 0) return const [];
    return splitChaptersByChars(_chapters, count);
  }

  Future<TtsProvider> _provider() async {
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

  Future<void> _loadVoices() async => _run(() async {
        final provider = await _provider();
        final voices = await provider.listVoices();
        voices.sort(
            (a, b) => '${a.locale}${a.name}'.compareTo('${b.locale}${b.name}'));
        if (!mounted) return;
        setState(() {
          _voices = voices;
          _voice = voices.isEmpty ? null : voices.first;
          _status = '${voices.length} voices';
        });
      });

  Future<void> _preview() async {
    if (_chapters.isEmpty) return _showError(s.get('noFile'));
    await _run(() async {
      final units = _units;
      if (units.isEmpty) {
        throw const FormatException('Enter a positive character count.');
      }
      final voice = _voice;
      if (voice == null) {
        throw const TtsProviderException('Load and select a voice first.');
      }
      final unit = units[(_selectedIndex ?? 0).clamp(0, units.length - 1)];
      final provider = await _provider();
      final bytes =
          await provider.synthesize(previewText(unit.text), voice.name);
      final file =
          await AudioGenerator.writeTemporary(bytes, 'tts-preview.mp3');
      await _player.setFilePath(file);
      await _player.play();
    });
  }

  Future<void> _generate() async {
    if (_chapters.isEmpty) return _showError(s.get('noFile'));
    await _run(() async {
      final units = _units;
      if (units.isEmpty) {
        throw const FormatException('Enter a positive character count.');
      }
      final voice = _voice;
      if (voice == null) {
        throw const TtsProviderException('Load and select a voice first.');
      }
      final provider = await _provider();
      final paths = await AudioGenerator.generateAll(
        provider,
        units,
        voice.name,
        onProgress: (current, total) {
          if (mounted) setState(() => _status = '$current / $total');
        },
      );
      if (!mounted) return;
      setState(() => _status = s.get('done'));
      await Share.shareXFiles(paths.map(XFile.new).toList());
    });
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
          const SizedBox(height: 16),
          Text(s.get('provider'),
              style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'azure', label: Text('Azure Speech')),
              ButtonSegment(value: 'google', label: Text('Google Cloud TTS')),
            ],
            selected: {_providerName},
            onSelectionChanged: _busy
                ? null
                : (values) async {
                    final provider = values.first;
                    final key =
                        await _credentials.read(provider, 'api_key') ?? '';
                    final region =
                        await _credentials.read(provider, 'region') ?? '';
                    setState(() {
                      _providerName = provider;
                      _keyController.text = key;
                      _regionController.text = region;
                      _voices = const [];
                      _voice = null;
                    });
                  },
          ),
          const SizedBox(height: 8),
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
          const Divider(height: 32),
          Text(s.get('split'), style: Theme.of(context).textTheme.titleMedium),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(s.get('chapter'))),
              ButtonSegment(value: true, label: Text(s.get('chars'))),
            ],
            selected: {_splitByChars},
            onSelectionChanged: (values) =>
                setState(() => _splitByChars = values.first),
          ),
          if (_splitByChars)
            TextField(
                controller: _charsController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.get('maxChars')),
                onChanged: (_) => setState(() {})),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: _busy ? null : _loadVoices,
              child: Text(s.get('loadVoices'))),
          if (_voices.isNotEmpty)
            DropdownButtonFormField<VoiceInfo>(
              key: ValueKey(_voice),
              initialValue: _voice,
              isExpanded: true,
              decoration: InputDecoration(labelText: s.get('voice')),
              items: _voices
                  .map((voice) => DropdownMenuItem(
                      value: voice,
                      child: Text('${voice.locale} · ${voice.name}',
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) => setState(() => _voice = value),
            ),
          if (units.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: units.length,
                itemBuilder: (context, index) => ListTile(
                  selected: _selectedIndex == index,
                  leading: Icon(
                    _selectedIndex == index
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(units[index].title),
                  subtitle: Text('${units[index].text.length} chars'),
                  onTap: () => setState(() => _selectedIndex = index),
                ),
              ),
            ),
          ],
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _busy ? null : _preview,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(s.get('preview')))),
            const SizedBox(width: 8),
            Expanded(
                child: FilledButton.icon(
                    onPressed: _busy ? null : _generate,
                    icon: const Icon(Icons.download),
                    label: Text(s.get('generate')))),
          ]),
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator()),
          if (_status.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status, textAlign: TextAlign.center)),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(s.get('unsupported')),
            subtitle: Text(s.get('limitations')),
          ),
        ],
      ),
    );
  }
}
