import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Minimal .xlsx reader.
///
/// The `excel` package refuses workbooks whose style sheet declares a custom
/// number format with a built-in id - which Excel itself writes as soon as a
/// column is formatted as an accounting number. Import only needs cell text,
/// so the sheet XML is read directly and the styles are ignored entirely.
class XlsxReader {
  XlsxReader._(this.rows);

  /// Row-major cell text. Missing cells are empty strings.
  final List<List<String>> rows;

  bool get isEmpty => rows.isEmpty;

  static XlsxReader parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? file(String path) {
      for (final f in archive.files) {
        if (f.name == path) return f;
      }
      return null;
    }

    String? read(String path) {
      final f = file(path);
      if (f == null) return null;
      return String.fromCharCodes(f.content as List<int>);
    }

    // Shared strings: every cell of type "s" indexes into this table.
    final shared = <String>[];
    final sharedXml = read('xl/sharedStrings.xml');
    if (sharedXml != null) {
      final doc = XmlDocument.parse(sharedXml);
      for (final si in doc.findAllElements('si')) {
        final buffer = StringBuffer();
        for (final t in si.findAllElements('t')) {
          buffer.write(t.innerText);
        }
        shared.add(buffer.toString());
      }
    }

    // First worksheet, by file order.
    final sheetNames = archive.files
        .map((f) => f.name)
        .where((n) =>
            n.startsWith('xl/worksheets/') && n.endsWith('.xml'))
        .toList()
      ..sort();
    if (sheetNames.isEmpty) return XlsxReader._(const []);

    final sheetXml = read(sheetNames.first);
    if (sheetXml == null) return XlsxReader._(const []);

    final doc = XmlDocument.parse(sheetXml);
    final out = <List<String>>[];

    for (final row in doc.findAllElements('row')) {
      final cells = <int, String>{};
      var widest = -1;

      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r') ?? '';
        final column = _columnIndex(ref);
        if (column < 0) continue;

        final type = c.getAttribute('t');
        String value;

        if (type == 'inlineStr') {
          final buffer = StringBuffer();
          for (final t in c.findAllElements('t')) {
            buffer.write(t.innerText);
          }
          value = buffer.toString();
        } else {
          // Formula cells carry their cached result in <v>, which is what
          // the sheet shows and what the import should use.
          final v = c.findElements('v').firstOrNull;
          final raw = v?.innerText ?? '';
          if (type == 's') {
            final index = int.tryParse(raw);
            value = (index != null && index >= 0 && index < shared.length)
                ? shared[index]
                : '';
          } else {
            value = raw;
          }
        }

        if (value.isEmpty) continue;
        cells[column] = value;
        if (column > widest) widest = column;
      }

      final line = List<String>.generate(
        widest + 1,
        (i) => cells[i] ?? '',
      );
      out.add(line);
    }

    // Trailing blank rows carry no information.
    while (out.isNotEmpty && out.last.every((c) => c.isEmpty)) {
      out.removeLast();
    }

    return XlsxReader._(out);
  }

  /// "BC12" -> 54. Returns -1 when the reference has no column letters.
  static int _columnIndex(String reference) {
    var value = 0;
    var seen = false;
    for (final unit in reference.codeUnits) {
      if (unit >= 65 && unit <= 90) {
        value = value * 26 + (unit - 64);
        seen = true;
      } else if (unit >= 97 && unit <= 122) {
        value = value * 26 + (unit - 96);
        seen = true;
      } else {
        break;
      }
    }
    return seen ? value - 1 : -1;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
