import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'dart:typed_data';
import 'dart:html' as html;

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

  void _downloadFile(Uint8List bytes, String filename) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }

  Future<void> _downloadBatchExcel(String batchMonth) async {
    setState(() => _isDownloading = true);

    try {
      // Fetch all payslips in this batch
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
        'socialSecurity',
        'leaveDeduction',
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

        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
            .value = TextCellValue(data['employeeId']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
            .value = TextCellValue(data['username']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
            .value = TextCellValue(data['displayName']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
            .value = TextCellValue(data['department']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
            .value = TextCellValue(data['bankName']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
            .value = TextCellValue(data['accountNumber']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex))
            .value = TextCellValue(data['accountHolderName']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex))
            .value = TextCellValue(data['month']?.toString() ?? '');
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex))
            .value = DoubleCellValue((data['basicSalary'] ?? 0).toDouble());
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex))
            .value = DoubleCellValue((data['allowance'] ?? 0).toDouble());
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: rowIndex))
            .value = DoubleCellValue((data['kpiBonus'] ?? 0).toDouble());
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: rowIndex))
            .value = DoubleCellValue((data['socialSecurity'] ?? 0).toDouble());
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIndex))
            .value = DoubleCellValue((data['leaveDeduction'] ?? 0).toDouble());
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 13, rowIndex: rowIndex))
            .value = DoubleCellValue((data['netSalary'] ?? 0).toDouble());
      }

      final bytes = excel.save();
      if (bytes == null) throw Exception('Failed to generate Excel');

      _downloadFile(
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
      builder: (context) => AlertDialog(
        title: const Text('Delete Batch'),
        content: const Text(
          'This will delete the entire batch and all employee payslips in it. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
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
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: const Text('Batch Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Delete batch',
            onPressed: () => _deleteBatch(context),
          ),
        ],
      ),
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

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  color: Colors.indigo.shade50,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batchMonth,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 14, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'Imported: ${_formatDate(data['importedAt'] as Timestamp?)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.person,
                              size: 14, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text(
                            'By: ${data['importedBy'] ?? 'admin'}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Download Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isDownloading
                              ? null
                              : () => _downloadBatchExcel(batchMonth),
                          icon: _isDownloading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: Text(_isDownloading
                              ? 'Downloading...'
                              : 'Download Excel'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.people,
                          label: 'Total Staff',
                          value: '$totalEmployees',
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildStatCard(
                          icon: Icons.payments,
                          label: 'Total Salary',
                          value: '฿ ${_formatNumber(totalNetSalary)}',
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Department Breakdown',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    child: Column(
                      children: departmentBreakdown.entries.map((entry) {
                        return ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.business,
                              color: Colors.indigo.shade700,
                              size: 20,
                            ),
                          ),
                          title: Text(entry.key),
                          trailing: Text(
                            '${entry.value} ${entry.value == 1 ? 'person' : 'people'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.deepPurple,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Employees',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('payslips')
                      .where('batchId', isEqualTo: widget.batchId)
                      .snapshots(),
                  builder: (context, payslipSnapshot) {
                    if (payslipSnapshot.connectionState ==
                        ConnectionState.waiting) {
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
                          final netSalary =
                              (pData['netSalary'] ?? 0).toDouble();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(
                                pData['displayName'] ?? '-',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${pData['employeeId'] ?? '-'} • ${pData['department'] ?? '-'}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Text(
                                '฿ ${_formatNumber(netSalary)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepPurple,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}