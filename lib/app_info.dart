import 'package:url_launcher/url_launcher.dart';

typedef ExternalLinkLauncher = Future<bool> Function(Uri uri);

const projectContactUrl =
    'https://github.com/t-and-i/yomipalette-android/issues';

Future<bool> openExternalLink(String url, {ExternalLinkLauncher? launcher}) {
  return (launcher ??
      (uri) =>
          launchUrl(uri, mode: LaunchMode.externalApplication))(Uri.parse(url));
}
