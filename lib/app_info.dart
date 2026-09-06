import 'package:url_launcher/url_launcher.dart';

class SupportLink {
  const SupportLink(this.label, this.url);

  final String label;
  final String url;
}

typedef SupportLauncher = Future<bool> Function(Uri uri);

const supportLinks = [
  SupportLink('GitHub Sponsors', 'https://github.com/sponsors/tjsongwei'),
  SupportLink('Buy Me a Coffee', 'https://buymeacoffee.com/tjsongweic'),
];

Future<bool> openSupportLink(SupportLink link, {SupportLauncher? launcher}) {
  return (launcher ??
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication))(
    Uri.parse(link.url),
  );
}
