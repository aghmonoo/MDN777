import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' hide Border;
import 'dart:typed_data';
import '../file_download_helper.dart';
import '../theme.dart';

class AdminPayslipBatchDetailPage extends StatefulWidget {
  final String batchId;

  const AdminPayslipBatchDetailPage({super.key, required this.batchId});

  @override
  State<AdminPayslipBatchDetailPage> createState() =>
      _AdminPayslipBatchDetailPageState();
}

class _AdminPayslipBatchDetailPageState
    extends State<AdminPayslipBatchDetailPage> {
  bool _isDownloading = false;

  late final Stream<QuerySnapshot> _payslipsStream;

  @override
  void initState() {
    super.initState();
    _payslipsStream = FirebaseFirestore.instance
        .collection('payslips')
        .where('batchId', isEqualTo: widget.batchId)
        .snapshots();
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

  

  Future<void> _downloadBatchExcel(String batchMonth) async {
    setState(() => _isDownloading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('payslips')
          .where('batchId', isEqualTo: widget.batchId)
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No data to download')),
          );
          setState(() => _isDownloading = false);
        }
        return;
      }

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
        'otHours',
        'otAmount',
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

      for (var i = 0; i < snapshot.docs.length; i++) {
        final data = snapshot.docs[i].data();
        final rowIndex = i + 1;

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
            .value = TextCellValue(data['month']?.toString() ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex))
            .value = DoubleCellValue((data['basicSalary'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex))
            .value = DoubleCellValue((data['allowance'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIndex))
            .value = DoubleCellValue((data['kpiBonus'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIndex))
            .value = DoubleCellValue((data['otHours'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIndex))
            .value = DoubleCellValue((data['otAmount'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIndex))
            .value = DoubleCellValue((data['socialSecurity'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: rowIndex))
            .value = DoubleCellValue((data['leaveDeduction'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIndex))
            .value = DoubleCellValue((data['lateMinutes'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: rowIndex))
            .value = DoubleCellValue((data['lateAmount'] ?? 0).toDouble());
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 17, rowIndex: rowIndex))
            .value = DoubleCellValue((data['netSalary'] ?? 0).toDouble());
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel');

      downloadFile(
        Uint8List.fromList(bytes),
        'payslips_${batchMonth.replaceAll(' ', '_')}.xlsx',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Downloaded successfully'),
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

    if (mounted) setState(() => _isDownloading = false);
  }

  Future<void> _deleteBatch(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Batch'),
        content: const Text(
          'Delete entire batch and all payslips in it?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final payslipsSnapshot = await FirebaseFirestore.instance
          .collection('payslips')
          .where('batchId', isEqualTo: widget.batchId)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in payslipsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(FirebaseFirestore.instance
          .collection('payslip_batches')
          .doc(widget.batchId));

      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Batch deleted'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('payslip_batches')
            .doc(widget.batchId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Batch not found'));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final batchMonth = data['month'] ?? '';
          final totalEmployees = (data['totalEmployees'] ?? 0) as int;
          final totalNetSalary = (data['totalNetSalary'] ?? 0).toDouble();
          final departmentBreakdown =
              (data['departmentBreakdown'] as Map<String, dynamic>?) ?? {};
          final importedBy = data['importedBy'] ?? 'admin';
          final importedAt = data['importedAt'] as Timestamp?;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 200,
                pinned: true,
                backgroundColor: const Color(0xFF3730A3),
                foregroundColor: Colors.white,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteBatch(context),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _buildHero(
                    batchMonth,
                    importedAt,
                    importedBy.toString(),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDownloadCard(batchMonth),
                      const SizedBox(height: 16),
                      _buildStatsRow(totalEmployees, totalNetSalary),
                      const SizedBox(height: 20),
                      if (departmentBreakdown.isNotEmpty) ...[
                        _sectionLabel('DEPARTMENT BREAKDOWN'),
                        const SizedBox(height: 8),
                        _buildDepartmentList(departmentBreakdown),
                        const SizedBox(height: 20),
                      ],
                      _sectionLabel('EMPLOYEES'),
                      const SizedBox(height: 8),
                      _buildEmployeesList(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHero(String month, Timestamp? importedAt, String importedBy) {
    return Container(
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
      child: Stack(
        children: [
          Positioned(
            top: -40,
            right: -50,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'PAY SLIP BATCH',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    month,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 12,
                          color: Colors.white.withOpacity(0.85)),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(importedAt),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.person_outline,
                          size: 12,
                          color: Colors.white.withOpacity(0.85)),
                      const SizedBox(width: 4),
                      Text(
                        importedBy,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadCard(String batchMonth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isDownloading ? null : () => _downloadBatchExcel(batchMonth),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _isDownloading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.file_download_outlined,
                          color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isDownloading ? 'Downloading...' : 'Download Excel',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Export full batch data',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward,
                    color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(int totalEmployees, double totalNetSalary) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _statCard(
              icon: Icons.people_outline,
              label: 'Total Staff',
              value: '$totalEmployees',
              gradStart: AppTheme.blueStart,
              gradEnd: AppTheme.blueEnd,
              iconColor: AppTheme.blueIcon,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _statCard(
              icon: Icons.payments_outlined,
              label: 'Total Net',
              value: '฿ ${_formatNumber(totalNetSalary)}',
              gradStart: AppTheme.greenStart,
              gradEnd: AppTheme.greenEnd,
              iconColor: AppTheme.greenIcon,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color gradStart,
    required Color gradEnd,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 0.5),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [gradStart, gradEnd]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }

  Widget _buildDepartmentList(Map<String, dynamic> departments) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border, width: 0.5),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          children: departments.entries.toList().asMap().entries.map((e) {
            final isLast = e.key == departments.length - 1;
            final entry = e.value;
            final count = entry.value as int;
            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: isLast
                      ? BorderSide.none
                      : const BorderSide(color: AppTheme.border, width: 0.5),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3730A3), AppTheme.primary],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.business_outlined,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      entry.key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primarySurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count ${count == 1 ? 'person' : 'people'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmployeesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _payslipsStream,
      builder: (context, payslipSnapshot) {
        if (payslipSnapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = payslipSnapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No payslips in this batch'),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: docs.map((doc) {
              final pData = doc.data() as Map<String, dynamic>;
              final netSalary = (pData['netSalary'] ?? 0).toDouble();
              final displayName = pData['displayName'] ?? '-';
              final initial = displayName.toString().isNotEmpty
                  ? displayName.toString().substring(0, 1).toUpperCase()
                  : '?';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border, width: 0.5),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.pinkStart, AppTheme.pinkEnd],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: AppTheme.pinkIcon,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${pData['employeeId'] ?? '-'} · ${pData['department'] ?? '-'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '฿ ${_formatNumber(netSalary)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}