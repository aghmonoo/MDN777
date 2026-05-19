import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:html' as html;
import '../theme.dart';
import 'admin_payslip_batch_detail_page.dart';

class AdminPayslipsPage extends StatefulWidget {
  const AdminPayslipsPage({super.key});

  @override
  State<AdminPayslipsPage> createState() => _AdminPayslipsPageState();
}

class _AdminPayslipsPageState extends State<AdminPayslipsPage> {
  bool _isExporting = false;
  bool _isImporting = false;
  String _statusMessage = '';

  String _getCurrentMonth() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[now.month - 1]} ${now.year}';
  }

  Future<void> _exportExcel() async {
    setState(() {
      _isExporting = true;
      _statusMessage = 'Loading employees...';
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'employee')
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No employees found')),
          );
          setState(() {
            _isExporting = false;
            _statusMessage = '';
          });
        }
        return;
      }

      setState(() => _statusMessage = 'Generating Excel...');

      final excel = Excel.createExcel();
      final sheet = excel['Payslips'];
      excel.delete('Sheet1');

      final headers = [
        'employeeId',
        'username',
        'displayName',
        'department',
        'bankName',
        'accountNumber',
        'accountHolderName',
        'month',
        'basicSalary',
        'allowance',
        'kpiBonus',
        'socialSecurity',
        'leaveDeduction',
        'lateMinutes',
        'lateAmount',
        'netSalary',
      ];

      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(
          columnIndex: i,
          rowIndex: 0,
        ));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = CellStyle(
          bold: true,
          backgroundColorHex: ExcelColor.fromHexString('#E0E0E0'),
        );
      }

      final currentMonth = _getCurrentMonth();
      for (var i = 0; i < snapshot.docs.length; i++) {
        final data = snapshot.docs[i].data();
        final rowIndex = i + 1;
        final excelRowNum = rowIndex + 1;

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
            .value = TextCellValue(data['employeeId']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
            .value = TextCellValue(data['username']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
            .value = TextCellValue(data['displayName']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
            .value = TextCellValue(data['department']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
            .value = TextCellValue(data['bankName']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
            .value = TextCellValue(data['accountNumber']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex))
            .value = TextCellValue(data['accountHolderName']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex))
            .value = TextCellValue(currentMonth);

        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIndex))
            .value = FormulaCellValue(
                'I$excelRowNum+J$excelRowNum+K$excelRowNum-L$excelRowNum-M$excelRowNum-O$excelRowNum');
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel');

      _downloadFile(
        Uint8List.fromList(bytes),
        'payslips_${currentMonth.replaceAll(' ', '_')}.xlsx',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported ${snapshot.docs.length} employees'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isExporting = false;
        _statusMessage = '';
      });
    }
  }

  void _downloadFile(Uint8List bytes, String filename) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _importExcel() async {
    setState(() {
      _isImporting = true;
      _statusMessage = 'Selecting file...';
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _isImporting = false;
          _statusMessage = '';
        });
        return;
      }

      final fileBytes = result.files.first.bytes;
      if (fileBytes == null) throw Exception('Could not read file');

      setState(() => _statusMessage = 'Reading Excel...');

      final excel = Excel.decodeBytes(fileBytes);
      final sheet = excel.tables[excel.tables.keys.first]!;

      String batchMonth = '';
      if (sheet.rows.length > 1) {
        batchMonth = sheet.rows[1][7]?.value?.toString() ?? '';
      }

      if (batchMonth.isEmpty) {
        throw Exception('Month column is empty in Excel');
      }

      final existingBatch = await FirebaseFirestore.instance
          .collection('payslip_batches')
          .where('month', isEqualTo: batchMonth)
          .get();

      if (existingBatch.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Batch "$batchMonth" already exists. Delete first.'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isImporting = false;
            _statusMessage = '';
          });
        }
        return;
      }

      setState(() => _statusMessage = 'Importing data...');

      final user = FirebaseAuth.instance.currentUser;
      final importedBy = user?.email?.split('@').first ?? 'admin';

      final batchRef = await FirebaseFirestore.instance
          .collection('payslip_batches')
          .add({
        'month': batchMonth,
        'importedAt': FieldValue.serverTimestamp(),
        'importedBy': importedBy,
        'totalEmployees': 0,
        'totalNetSalary': 0,
        'departmentBreakdown': {},
      });

      int successCount = 0;
      double totalNetSalary = 0;
      Map<String, int> departmentCount = {};
      List<String> errors = [];

      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        try {
          final employeeId = row[0]?.value?.toString() ?? '';
          final username = row[1]?.value?.toString() ?? '';
          final displayName = row[2]?.value?.toString() ?? '';
          final department = row[3]?.value?.toString() ?? '';
          final bankName = row[4]?.value?.toString() ?? '';
          final accountNumber = row[5]?.value?.toString() ?? '';
          final accountHolderName = row[6]?.value?.toString() ?? '';
          final month = row[7]?.value?.toString() ?? '';
          final basicSalary = _parseNumber(row[8]?.value);
          final allowance = _parseNumber(row[9]?.value);
          final kpiBonus = _parseNumber(row[10]?.value);
          final socialSecurity = _parseNumber(row[11]?.value);
          final leaveDeduction = _parseNumber(row[12]?.value);
          final lateMinutes = _parseNumber(row[13]?.value);
          final lateAmount = _parseNumber(row[14]?.value);

          if (employeeId.isEmpty || username.isEmpty || month.isEmpty) continue;

          final netSalary = basicSalary +
              allowance +
              kpiBonus -
              socialSecurity -
              leaveDeduction -
              lateAmount;

          await FirebaseFirestore.instance.collection('payslips').add({
            'batchId': batchRef.id,
            'employeeId': employeeId,
            'username': username,
            'displayName': displayName,
            'department': department,
            'bankName': bankName,
            'accountNumber': accountNumber,
            'accountHolderName': accountHolderName,
            'month': month,
            'basicSalary': basicSalary,
            'allowance': allowance,
            'kpiBonus': kpiBonus,
            'socialSecurity': socialSecurity,
            'leaveDeduction': leaveDeduction,
            'lateMinutes': lateMinutes,
            'lateAmount': lateAmount,
            'netSalary': netSalary,
            'issuedDate': FieldValue.serverTimestamp(),
          });

          successCount++;
          totalNetSalary += netSalary;
          departmentCount[department] = (departmentCount[department] ?? 0) + 1;
        } catch (e) {
          errors.add('Row ${i + 1}: $e');
        }
      }

      await batchRef.update({
        'totalEmployees': successCount,
        'totalNetSalary': totalNetSalary,
        'departmentBreakdown': departmentCount,
      });

      if (mounted) {
        _showImportResult(successCount, errors);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isImporting = false;
        _statusMessage = '';
      });
    }
  }

  double _parseNumber(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final str = value.toString();
    return double.tryParse(str.replaceAll(',', '')) ?? 0;
  }

  void _showImportResult(int success, List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Import Result'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('Imported: $success employees'),
                ],
              ),
              if (errors.isNotEmpty) ...[
                const Divider(),
                Text('Errors: ${errors.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...errors.take(5).map((e) => Text('• $e',
                    style: const TextStyle(fontSize: 12))),
              ],
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    return value.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isExporting || _isImporting;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E3A8A),
                Color(0xFF3730A3),
                AppTheme.primary,
              ],
            ),
          ),
        ),
        title: const Text('Pay Slips'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        icon: Icons.file_download_outlined,
                        label: 'Export Excel',
                        gradStart: const Color(0xFF10B981),
                        gradEnd: const Color(0xFF059669),
                        onTap: isLoading ? null : _exportExcel,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _actionButton(
                        icon: Icons.file_upload_outlined,
                        label: 'Import Excel',
                        gradStart: const Color(0xFF3730A3),
                        gradEnd: AppTheme.primary,
                        onTap: isLoading ? null : _importExcel,
                      ),
                    ),
                  ],
                ),
                if (_statusMessage.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('payslip_batches')
                  .orderBy('importedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _emptyState();
                }

                final docs = snapshot.data!.docs;
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _batchCard(doc.id, data);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color gradStart,
    required Color gradEnd,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: disabled
                ? null
                : LinearGradient(colors: [gradStart, gradEnd]),
            color: disabled ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: disabled
                ? null
                : [
                    BoxShadow(
                      color: gradEnd.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.greenStart, AppTheme.greenEnd],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.receipt_long_outlined,
                size: 44, color: AppTheme.greenIcon),
          ),
          const SizedBox(height: 20),
          const Text(
            'No payslip batches yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Export Excel → fill data → Import to create your first batch',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _batchCard(String docId, Map<String, dynamic> data) {
    final totalEmployees = (data['totalEmployees'] ?? 0) as int;
    final totalNetSalary = (data['totalNetSalary'] ?? 0).toDouble();
    final month = data['month'] ?? '-';
    final importedBy = data['importedBy'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border, width: 0.5),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AdminPayslipBatchDetailPage(batchId: docId),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            AppTheme.greenStart,
                            AppTheme.greenEnd,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.description_outlined,
                        color: AppTheme.greenIcon,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            month,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.access_time,
                                  size: 11, color: AppTheme.textTertiary),
                              const SizedBox(width: 3),
                              Text(
                                _formatDate(data['importedAt'] as Timestamp?),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textTertiary,
                                ),
                              ),
                              if (importedBy.toString().isNotEmpty) ...[
                                const Text(' · ',
                                    style: TextStyle(
                                        color: AppTheme.textTertiary,
                                        fontSize: 11)),
                                Text(
                                  importedBy,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textTertiary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppTheme.textTertiary),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'STAFF',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textTertiary,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$totalEmployees',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 36,
                        color: AppTheme.border,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TOTAL NET',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textTertiary,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '฿ ${_formatNumber(totalNetSalary)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                                height: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}