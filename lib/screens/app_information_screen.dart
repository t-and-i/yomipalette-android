import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/strings.dart';

class AppInformationScreen extends StatelessWidget {
  const AppInformationScreen({
    required this.version,
    required this.buildNumber,
    required this.openProject,
    super.key,
  });

  final String? version;
  final String? buildNumber;
  final VoidCallback openProject;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(Localizations.localeOf(context));
    final versionLabel = version == null || version!.isEmpty
        ? s.get('versionUnavailable')
        : '$version${buildNumber == null || buildNumber!.isEmpty ? '' : ' ($buildNumber)'}';
    return Scaffold(
      appBar: AppBar(title: Text(s.get('about'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('YomiPalette', style: Theme.of(context).textTheme.headlineSmall),
          SelectableText(versionLabel),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(s.get('privacy')),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(s.get('licenses')),
            onTap: () async {
              final license = await rootBundle.loadString('LICENSE');
              if (!context.mounted) return;
              showLicensePage(
                context: context,
                applicationName: 'YomiPalette',
                applicationVersion: versionLabel,
                applicationLegalese: license,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(s.get('projectContact')),
            onTap: openProject,
          ),
        ],
      ),
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings(Localizations.localeOf(context));
    return Scaffold(
      appBar: AppBar(title: Text(s.get('privacy'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'YomiPalette',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(s.get('privacyUpdated')),
              const SizedBox(height: 16),
              Text(s.get('privacyIntro')),
              for (final section in [
                'Documents',
                'Device',
                'Credentials',
                'Audio',
                'External',
              ]) ...[
                const SizedBox(height: 24),
                Text(
                  s.get('privacy${section}Title'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(s.get('privacy$section')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
