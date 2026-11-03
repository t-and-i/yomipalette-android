import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../controllers/tts_settings_controller.dart';
import '../l10n/strings.dart';

/// UI for provider choice, native engine, and API credential entry.
/// Async work and navigation are handled by HomeScreen callbacks.
class ProviderSettingsSection extends StatelessWidget {
  const ProviderSettingsSection({
    required this.strings,
    required this.settings,
    required this.busy,
    required this.onProviderChanged,
    required this.onDeviceEngineChanged,
    required this.onPrivacy,
    required this.onPersistChanged,
    required this.onForgetCredentials,
    super.key,
  });

  final AppStrings strings;
  final TtsSettingsController settings;
  final bool busy;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onDeviceEngineChanged;
  final VoidCallback onPrivacy;
  final ValueChanged<bool> onPersistChanged;
  final VoidCallback onForgetCredentials;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        strings.get('provider'),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      DropdownButtonFormField<String>(
        initialValue: settings.providerName,
        decoration: InputDecoration(labelText: strings.get('provider')),
        items: [
          DropdownMenuItem(
            value: 'edge',
            child: Text(strings.get('providerEdge')),
          ),
          if (defaultTargetPlatform == TargetPlatform.android)
            DropdownMenuItem(
              value: 'device',
              child: Text(strings.get('deviceTts')),
            ),
          const DropdownMenuItem(value: 'azure', child: Text('Azure Speech')),
          const DropdownMenuItem(
            value: 'google',
            child: Text('Google Cloud TTS'),
          ),
        ],
        onChanged: busy
            ? null
            : (provider) {
                if (provider != null) onProviderChanged(provider);
              },
      ),
      const SizedBox(height: 8),
      Text(
        strings.get(
          settings.providerName == 'device'
              ? 'deviceDisclosure'
              : 'cloudDisclosure',
        ),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: onPrivacy,
          child: Text(strings.get('privacy')),
        ),
      ),
      if (settings.providerName == 'device') ...[
        DropdownButtonFormField<String>(
          key: ValueKey('device-engine-${settings.deviceTtsEngine}'),
          initialValue: settings.deviceTtsEngine,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: strings.get('deviceTtsEngine'),
          ),
          items: settings.deviceTtsEngines
              .map(
                (engine) => DropdownMenuItem(
                  value: engine.name,
                  child: Text(
                    engine.isDefault
                        ? '${engine.label} (${strings.get('defaultEngine')})'
                        : engine.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (engine) {
                  if (engine != null) onDeviceEngineChanged(engine);
                },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            strings.get('deviceTtsNote'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
      if (settings.providerName == 'azure' || settings.providerName == 'google')
        TextField(
          controller: settings.keyController,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: strings.get('apiKey')),
        ),
      if (settings.providerName == 'azure')
        TextField(
          controller: settings.regionController,
          autocorrect: false,
          decoration: InputDecoration(labelText: strings.get('region')),
        ),
      if (settings.providerName == 'azure' ||
          settings.providerName == 'google') ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: settings.persist,
          title: Text(strings.get('persist')),
          onChanged: onPersistChanged,
        ),
        TextButton.icon(
          onPressed: onForgetCredentials,
          icon: const Icon(Icons.delete_outline),
          label: Text(strings.get('forget')),
        ),
      ],
    ],
  );
}
