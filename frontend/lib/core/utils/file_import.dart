// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

enum UploadState { idle, reviewing, importing, done }

class ParsedImport {
  final String fileName;
  final List<String> headers; // lowercase trimmed
  final List<Map<String, String>> rows;

  const ParsedImport({
    required this.fileName,
    required this.headers,
    required this.rows,
  });
}

/// Opens a browser file picker (web-only) for .csv or .xlsx files and parses
/// them into a [ParsedImport] with lowercase header keys.
void pickAndParseFile({
  required void Function(ParsedImport result) onSuccess,
  required void Function(String message) onError,
}) {
  final input = html.FileUploadInputElement()
    ..accept = '.csv,.xlsx'
    ..style.display = 'none';
  html.document.body!.append(input);

  input.onChange.listen((_) async {
    final file = input.files?.first;
    input.remove();
    if (file == null) return; // user cancelled

    try {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      final bytes = (reader.result as ByteBuffer).asUint8List();

      List<List<String>> allRows;
      final name = file.name.toLowerCase();

      if (name.endsWith('.csv')) {
        final text = utf8.decode(bytes, allowMalformed: true);
        final raw = const CsvToListConverter(eol: '\n').convert(text);
        allRows =
            raw.map((r) => r.map((c) => c.toString().trim()).toList()).toList();
      } else if (name.endsWith('.xlsx')) {
        final excel = Excel.decodeBytes(bytes);
        final sheetName = excel.tables.keys.first;
        final sheet = excel.tables[sheetName]!;
        allRows = sheet.rows
            .map((r) =>
                r.map((c) => c?.value?.toString().trim() ?? '').toList())
            .toList();
      } else {
        onError('Unsupported format. Please choose a .csv or .xlsx file.');
        return;
      }

      // drop fully-blank rows
      allRows = allRows.where((r) => r.any((c) => c.isNotEmpty)).toList();

      if (allRows.length < 2) {
        onError('File is empty or has no data rows.');
        return;
      }

      final headers = allRows.first.map((h) => h.toLowerCase()).toList();
      final rows = allRows.skip(1).map((r) {
        final map = <String, String>{};
        for (int i = 0; i < headers.length; i++) {
          map[headers[i]] = i < r.length ? r[i] : '';
        }
        return map;
      }).toList();

      onSuccess(
          ParsedImport(fileName: file.name, headers: headers, rows: rows));
    } catch (e) {
      onError('Failed to read file: $e');
    }
  });

  input.click();
}

// ---------------------------------------------------------------------------
// Normalisation helpers (shared between member + sponsor upload sheets)
// ---------------------------------------------------------------------------

String? notEmpty(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

String? normaliseGender(String? raw) {
  if (raw == null) return null;
  final g = raw.trim().toLowerCase();
  if (g == 'm' || g == 'male') return 'MALE';
  if (g == 'f' || g == 'female') return 'FEMALE';
  return null;
}

String? normaliseMaritalStatus(String? raw) {
  if (raw == null) return null;
  final v = raw.trim().toLowerCase();
  if (v.startsWith('s')) return 'SINGLE';
  if (v.startsWith('m')) return 'MARRIED';
  if (v.startsWith('d')) return 'DIVORCED';
  if (v.startsWith('w')) return 'WIDOWED';
  return null;
}

String? normaliseSponsorTier(String? raw) {
  if (raw == null) return null;
  final t = raw.trim().toLowerCase();
  if (t.contains('month')) return 'MONTHLY';
  if (t.contains('quarter')) return 'QUARTERLY';
  if (t.contains('annual') || t.contains('year')) return 'ANNUAL';
  if (t.contains('one') || t.contains('once') || t == 'o') return 'ONE_TIME';
  return null;
}
