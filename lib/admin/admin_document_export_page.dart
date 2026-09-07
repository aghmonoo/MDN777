import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../document_types.dart';
import '../file_download_helper.dart';
import '../theme.dart';

/// Bulk export of staff documents: one PDF per person, named after them.
class AdminDocumentExportPage extends StatefulWidget {
  const AdminDocumentExportPage({super.key});

  @override
  State<AdminDocumentExportPage> createState() =>
      _AdminDocumentExportPageState();
}

class _AdminDocumentExportPageState extends State<AdminDocumentExportPage> {
  final Set<String> _selected = {};
  final _searchController = TextEditingController();

  String _search = '';
  bool _busy = false;
  String _status = '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _usersStream;

  @override
  void initState() {
    super.initState();
    _usersStream = FirebaseFirestore.instance
        .collection('users')
        .orderBy('displayName')
        .snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _visible(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    if (_search.isEmpty) return docs;
    final q = _search.toLowerCase();
    return docs.where((d) {
      final data = d.data();
      final name = (data['displayName'] ?? '').toString().toLowerCase();
      final username = (data['username'] ?? '').toString().toLowerCase();
      final employeeId = (data['employeeId'] ?? '').toString().toLowerCase();
      return name.contains(q) ||
          username.contains(q) ||
          employeeId.contains(q);
    }).toList();
  }

  int _docCount(Map<String, dynamic> data) =>
      DocumentTypes.filled(data['documents'] as Map<String, dynamic>?).length;

  /// Builds one PDF holding every document image the person has uploaded.
  Future<Uint8List?> _buildPdf(Map<String, dynamic> data) async {
    final documents = data['documents'] as Map<String, dynamic>?;
    final slots = DocumentTypes.filled(documents);
    if (slots.isEmpty) return null;

    final displayName = (data['displayName'] ?? data['username'] ?? 'Unknown')
        .toString();
    final employeeId = (data['employeeId'] ?? '').toString();
    final department = (data['department'] ?? '').toString();

    final pdf = pw.Document(title: '$displayName - Documents');

    for (final slot in slots) {
      final url = documents![slot.fieldPath].toString();

      Uint8List bytes;
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) continue;
        bytes = response.bodyBytes;
      } catch (_) {
        continue;
      }

      final image = pw.MemoryImage(bytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  displayName,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  [
                    if (employeeId.isNotEmpty) employeeId,
                    if (department.isNotEmpty) department,
                    slot.label,
                  ].join('  -  '),
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Image(image, fit: pw.BoxFit.contain),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    if (pdf.document.pdfPageList.pages.isEmpty) return null;
    return Uint8List.fromList(await pdf.save());
  }

  String _fileName(Map<String, dynamic> data) {
    final raw = (data['displayName'] ?? data['username'] ?? 'staff').toString();
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim();
    final employeeId = (data['employeeId'] ?? '').toString().trim();
    final base = safe.isEmpty ? 'staff' : safe.replaceAll(' ', '_');
    return employeeId.isEmpty ? '$base.pdf' : '${base}_$employeeId.pdf';
  }

  Future<void> _download(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document export works from the web app.'),
        ),
      );
      return;
    }

    final chosen = docs.where((d) => _selected.contains(d.id)).toList();
    if (chosen.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Preparing...';
    });

    final files = <String, Uint8List>{};
    final skipped = <String>[];

    for (var i = 0; i < chosen.length; i++) {
      final data = chosen[i].data();
      final name = (data['displayName'] ?? data['username'] ?? '?').toString();

      setState(() => _status = '${i + 1}/${chosen.length}  $name');

      final bytes = await _buildPdf(data);
      if (bytes == null) {
        skipped.add(name);
        continue;
      }

      // Two people can share a name; keep both files.
      var fileName = _fileName(data);
      var suffix = 2;
      while (files.containsKey(fileName)) {
        fileName = _fileName(data).replaceAll('.pdf', '_$suffix.pdf');
        suffix++;
      }
      files[fileName] = bytes;
    }

    if (files.isEmpty) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No documents to export')),
        );
      }
      return;
    }

    if (files.length == 1) {
      downloadFile(files.values.first, files.keys.first);
    } else {
      // Several people at once come down as one zip of individual PDFs.
      setState(() => _status = 'Packing ${files.length} files...');
      final archive = Archive();
      files.forEach((name, bytes) {
        archive.addFile(ArchiveFile(name, bytes.length, bytes));
      });
      final zip = ZipEncoder().encode(archive) ?? <int>[];
      final stamp = DateTime.now();
      downloadFile(
        Uint8List.fromList(zip),
        'staff_documents_'
        '${stamp.year}${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}.zip',
      );
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped.isEmpty
              ? 'Exported ${files.length} file(s)'
              : 'Exported ${files.length} file(s). '
                  'No documents for: ${skipped.join(", ")}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        ),
        title: const Text('Download Documents'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _usersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final all = snapshot.data?.docs ?? [];
          final withDocs =
              all.where((d) => _docCount(d.data()) > 0).toList();
          final visible = _visible(withDocs);

          final allVisibleSelected = visible.isNotEmpty &&
              visible.every((d) => _selected.contains(d.id));

          return Column(
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _search = v.trim()),
                      decoration: InputDecoration(
                        hintText: 'Search name, username or ID',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Checkbox(
                          value: allVisibleSelected,
                          onChanged: _busy
                              ? null
                              : (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selected.addAll(visible.map((d) => d.id));
                                    } else {
                                      _selected.removeWhere((id) =>
                                          visible.any((d) => d.id == id));
                                    }
                                  });
                                },
                        ),
                        const Text('Select all',
                            style: TextStyle(fontSize: 13.5)),
                        const Spacer(),
                        Text(
                          '${_selected.length} selected',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _status,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? const Center(
                        child: Text(
                          'No staff with uploaded documents',
                          style: TextStyle(color: AppTheme.textTertiary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppTheme.border),
                        itemBuilder: (_, i) {
                          final doc = visible[i];
                          final data = doc.data();
                          final count = _docCount(data);
                          final selected = _selected.contains(doc.id);

                          return CheckboxListTile(
                            value: selected,
                            onChanged: _busy
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(doc.id);
                                      } else {
                                        _selected.remove(doc.id);
                                      }
                                    });
                                  },
                            title: Text(
                              (data['displayName'] ?? data['username'] ?? '-')
                                  .toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '@${data['username'] ?? '-'}  -  '
                              '$count document${count == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _usersStream,
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          return FloatingActionButton.extended(
            onPressed:
                _busy || _selected.isEmpty ? null : () => _download(docs),
            backgroundColor:
                _selected.isEmpty ? AppTheme.textTertiary : AppTheme.primary,
            icon: const Icon(Icons.download, color: Colors.white),
            label: Text(
              _selected.isEmpty ? 'Download' : 'Download (${_selected.length})',
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      ),
    );
  }
}
