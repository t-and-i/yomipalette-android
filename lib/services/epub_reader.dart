// Keep navigation/range rules in sync with core/epub_reader.py.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import '../models/chapter.dart';

const _backTypes = {
  'backmatter',
  'appendix',
  'endnotes',
  'footnotes',
  'bibliography',
  'glossary',
  'index',
  'colophon',
  'afterword',
  'acknowledgments',
};
final _backTitle = RegExp(
  r'^(補[註注]|注釈|脚注|巻末注|あとがき|後書き|奥付|著者紹介|訳者紹介|参考文献|索引|付録|附録|謝辞|appendix|endnotes|footnotes|bibliography|glossary|index|colophon|afterword|acknowledgments)$',
  caseSensitive: false,
);

String _clean(String text) => text
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r' ?\n ?'), '\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

typedef _Target = (String, String);
typedef _Position = (int, int);

_Target? _resolve(String base, String href) {
  final uri = Uri.tryParse(href);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  try {
    return (
      uri.path.isEmpty
          ? base
          : path.posix.normalize(path.posix
              .join(path.posix.dirname(base), Uri.decodeComponent(uri.path))),
      Uri.decodeComponent(uri.fragment),
    );
  } on FormatException {
    return null;
  }
}

bool _isBack(String text) =>
    _backTitle.hasMatch(text.replaceAll(RegExp(r'\s+'), ''));
bool _hasBack(String? types) =>
    (types ?? '').split(RegExp(r'\s+')).any(_backTypes.contains);
String _label(dom.Node node) {
  if (node is dom.Element &&
      ['script', 'style', 'rt', 'rp'].contains(node.localName)) {
    return '';
  }
  if (node is dom.Text) return node.data.trim();
  return node.nodes.map(_label).join();
}

class _Document {
  _Document(this.name, String source) {
    final tree = html.parse(source);
    final buffer = StringBuffer();
    void walk(dom.Node node) {
      if (node is dom.Text) {
        if (node.data.trim().isNotEmpty) buffer.writeln(node.data);
        return;
      }
      if (node is! dom.Element ||
          node.localName == 'script' ||
          node.localName == 'style' ||
          node.localName == 'rt' ||
          node.localName == 'rp') {
        return;
      }
      for (final key in ['id', 'name']) {
        final value = node.attributes[key];
        if (value != null && value.isNotEmpty) {
          anchors.putIfAbsent(value, () => buffer.length);
        }
      }
      final roles = (node.attributes['role'] ?? '')
          .split(' ')
          .map((r) => r.startsWith('doc-') ? r.substring(4) : r)
          .join(' ');
      if (_hasBack(node.attributes['epub:type']) || _hasBack(roles)) {
        final headings = node.querySelectorAll('h1,h2,h3,h4,h5,h6');
        extras[buffer.length] = headings.isEmpty ? '' : _label(headings.first);
      }
      if (RegExp(r'^h[1-6]$').hasMatch(node.localName ?? '') &&
          _isBack(_label(node))) {
        extras[buffer.length] = _label(node);
      }
      if (node.localName == 'a' && node.attributes.containsKey('href')) {
        links.add((node.attributes['href']!, _label(node)));
      }
      for (final child in node.nodes) {
        walk(child);
      }
    }

    walk(tree.body!);
    text = buffer.toString();
    final first = _clean(text).split('\n').first;
    if (_isBack(first)) extras[0] = first;
  }

  final String name;
  late final String text;
  final anchors = <String, int>{};
  final extras = <int, String>{};
  final links = <(String, String)>[];
}

Iterable<XmlElement> _elements(XmlNode node, String local) => node.descendants
    .whereType<XmlElement>()
    .where((e) => e.name.local == local);

int _compare(_Position a, _Position b) =>
    a.$1 == b.$1 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1);

String _decode(List<int> bytes) {
  if (bytes.length >= 2) {
    final littleBom = bytes[0] == 0xff && bytes[1] == 0xfe;
    final bigBom = bytes[0] == 0xfe && bytes[1] == 0xff;
    final little = littleBom || (bytes[0] == 0x3c && bytes[1] == 0);
    final big = bigBom || (bytes[0] == 0 && bytes[1] == 0x3c);
    if (little || big) {
      if (bytes.length.isOdd) {
        throw const FormatException('Invalid UTF-16 EPUB resource');
      }
      return String.fromCharCodes([
        for (var i = littleBom || bigBom ? 2 : 0; i < bytes.length; i += 2)
          little
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1],
      ]);
    }
  }
  return utf8.decode(bytes);
}

List<Chapter> readEpubSections(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  String read(String name) {
    final file = archive.findFile(name);
    if (file == null) throw FormatException('Missing EPUB resource: $name');
    return _decode(file.content as List<int>);
  }

  final container = XmlDocument.parse(read('META-INF/container.xml'));
  final opfPath =
      _elements(container, 'rootfile').first.getAttribute('full-path')!;
  final package = XmlDocument.parse(read(opfPath));
  final manifest = {
    for (final e in _elements(package, 'item')) e.getAttribute('id')!: e
  };
  final spine = _elements(package, 'spine').first;
  final docs = <_Document>[];
  for (final ref in spine.childElements) {
    final item = manifest[ref.getAttribute('idref')];
    if (item == null ||
        !['application/xhtml+xml', 'text/html']
            .contains(item.getAttribute('media-type'))) {
      continue;
    }
    final target = _resolve(opfPath, item.getAttribute('href')!);
    if (target != null) docs.add(_Document(target.$1, read(target.$1)));
  }

  final entries = <(_Target?, String)>[];
  final childTargets = <_Target?>[];
  final navItems = manifest.values.where(
      (e) => (e.getAttribute('properties') ?? '').split(' ').contains('nav'));
  dom.Document? navTree;
  String? navPath;
  if (navItems.isNotEmpty) {
    navPath = _resolve(opfPath, navItems.first.getAttribute('href') ?? '')?.$1;
    if (navPath != null && archive.findFile(navPath) != null) {
      navTree = html.parse(read(navPath));
    }
  }
  if (navTree != null) {
    final tocs = navTree.querySelectorAll('nav').where((e) =>
        (e.attributes['epub:type'] ?? '').split(' ').contains('toc') ||
        e.attributes['role'] == 'doc-toc');
    final ol = tocs.isEmpty ? null : tocs.first.querySelector('ol');
    if (ol != null) {
      for (final li in ol.children.where((e) => e.localName == 'li')) {
        final link = li.querySelector('a[href]');
        final labels = li.children
            .where((e) => e.localName == 'a' || e.localName == 'span');
        if (link != null) {
          entries.add((
            _resolve(navPath!, link.attributes['href']!),
            _label(labels.isEmpty ? link : labels.first)
          ));
          childTargets.addAll(li
              .querySelectorAll('a[href]')
              .where((a) => a != link)
              .map((a) => _resolve(navPath!, a.attributes['href']!)));
        }
      }
    }
  }
  if (entries.isEmpty) {
    final ncxItems = manifest.values.where(
        (e) => e.getAttribute('media-type') == 'application/x-dtbncx+xml');
    final ncx = manifest[spine.getAttribute('toc')] ??
        (ncxItems.isEmpty ? null : ncxItems.first);
    if (ncx != null) {
      final ncxPath =
          _resolve(opfPath, ncx.getAttribute('href') ?? '')?.$1 ?? '';
      var tree = XmlDocument();
      try {
        tree = XmlDocument.parse(read(ncxPath));
      } on FormatException {
        // Optional navigation can be absent/broken; retain spine content.
      }
      final maps = _elements(tree, 'navMap');
      if (maps.isNotEmpty) {
        for (final point in maps.first.childElements
            .where((e) => e.name.local == 'navPoint')) {
          final contents = _elements(point, 'content');
          final labels = _elements(point, 'navLabel');
          if (contents.isNotEmpty) {
            entries.add((
              _resolve(ncxPath, contents.first.getAttribute('src') ?? ''),
              labels.isEmpty ? '' : labels.first.innerText.trim()
            ));
            childTargets.addAll(contents
                .skip(1)
                .map((e) => _resolve(ncxPath, e.getAttribute('src') ?? '')));
          }
        }
      }
    }
  }

  final byPath = {for (var i = 0; i < docs.length; i++) docs[i].name: i};
  _Position? position(_Target? target) {
    if (target == null) return null;
    final i = byPath[target.$1];
    if (i == null) return null;
    final offset = target.$2.isEmpty ? 0 : docs[i].anchors[target.$2];
    return offset == null ? null : (i, offset);
  }

  final boundaries = <_Position, String>{};
  final missingAnchorDocs = <int>{};
  for (final entry in entries) {
    final pos = position(entry.$1);
    if (pos != null) {
      boundaries.putIfAbsent(pos, () => _clean(entry.$2));
    } else {
      final target = entry.$1;
      final i = target == null ? null : byPath[target.$1];
      if (i != null) missingAnchorDocs.add(i);
    }
  }
  final tocPositions = boundaries.keys.toSet();
  final ordered = boundaries.keys.toList()..sort(_compare);
  final first = ordered.isEmpty ? (docs.length, 0) : ordered.first;
  // Resolve failures locally. An unlisted cover must not split every chapter.
  final validDocs = tocPositions.map((p) => p.$1).toSet();
  for (final i in missingAnchorDocs.difference(validDocs)) {
    boundaries[(i, 0)] = '';
  }
  final protected = childTargets.map(position).toSet()..removeAll(tocPositions);
  final extras = <_Position, String>{
    for (var i = 0; i < docs.length; i++)
      for (final entry in docs[i].extras.entries) (i, entry.key): entry.value,
  };
  for (final doc in docs) {
    for (final link in doc.links) {
      if (_isBack(link.$2)) {
        final pos = position(_resolve(doc.name, link.$1));
        if (pos != null &&
            (tocPositions.isEmpty || _compare(pos, first) >= 0)) {
          extras.putIfAbsent(pos, () => link.$2);
        }
      }
    }
  }
  for (final ref in _elements(package, 'reference')) {
    if (_hasBack(ref.getAttribute('type'))) {
      final pos = position(_resolve(opfPath, ref.getAttribute('href') ?? ''));
      if (pos != null) {
        extras.putIfAbsent(pos, () => ref.getAttribute('title') ?? '');
      }
    }
  }
  if (navTree != null) {
    for (final link in navTree.querySelectorAll('a[href]')) {
      if (_hasBack(link.attributes['epub:type'])) {
        final pos = position(_resolve(navPath!, link.attributes['href']!));
        if (pos != null) extras.putIfAbsent(pos, () => _label(link));
      }
    }
  }
  extras.removeWhere((pos, _) => protected.contains(pos));
  for (final entry in extras.entries) {
    boundaries.putIfAbsent(entry.key, () => entry.value);
  }
  var inBackmatter = false;
  for (var i = 0; i < docs.length; i++) {
    if (tocPositions.contains((i, 0))) inBackmatter = false;
    if (tocPositions.isEmpty || _compare((i, 0), first) < 0 || inBackmatter) {
      boundaries.putIfAbsent((i, 0), () => '');
    }
    final events = {...extras.keys, ...tocPositions}
        .where((p) => p.$1 == i)
        .toList()
      ..sort(_compare);
    for (final pos in events) {
      inBackmatter = !tocPositions.contains(pos);
    }
  }

  final result = <Chapter>[];
  var pieces = StringBuffer();
  var title = '';
  void flush() {
    final text = _clean(pieces.toString());
    if (text.isNotEmpty) {
      final firstLine = text.split('\n').first;
      result.add(Chapter(
          index: result.length + 1,
          title: title.isNotEmpty
              ? title
              : (firstLine.runes.length <= 80
                  ? firstLine
                  : 'Chapter ${result.length + 1}'),
          text: text));
    }
    pieces = StringBuffer();
  }

  for (var i = 0; i < docs.length; i++) {
    var offset = 0;
    final cuts = boundaries.keys.where((p) => p.$1 == i).toList()
      ..sort(_compare);
    for (final pos in cuts) {
      pieces.write(docs[i].text.substring(offset, pos.$2));
      flush();
      title = boundaries[pos]!;
      offset = pos.$2;
    }
    pieces.write(docs[i].text.substring(offset));
  }
  flush();
  if (result.isEmpty) throw const FormatException('No readable text found.');
  return result;
}
