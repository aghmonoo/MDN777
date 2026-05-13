import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminBankLogsPage extends StatelessWidget {
  const AdminBankLogsPage({super.key});

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final logDay = DateTime(dt.year, dt.month, dt.day);
    final difference = today.difference(logDay).inDays;

    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $amPm';

    if (difference == 0) return 'Today, $timeStr';
    if (difference == 1) return 'Yesterday, $timeStr';
    return '${dt.day}/${dt.month}/${dt.year}, $timeStr';
  }

  Future<void> _markAllAsRead(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark all as read?'),
        content: const Text('This will mark all unread logs as read.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mark all'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bank_change_logs')
          .where('isRead', isEqualTo: false)
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Marked ${snapshot.docs.length} logs as read'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _markAsRead(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('bank_change_logs')
          .doc(docId)
          .update({'isRead': true});
    } catch (e) {
      // Silent fail
    }
  }

  void _showDetailDialog(BuildContext context, Map<String, dynamic> data,
      String docId) {
    // Mark as read when opened
    if (data['isRead'] != true) {
      _markAsRead(docId);
    }

    final oldData = (data['oldData'] as Map<String, dynamic>?) ?? {};
    final newData = (data['newData'] as Map<String, dynamic>?) ?? {};

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bank Change Detail'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Employee info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['displayName'] ?? '-',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${data['employeeId'] ?? '-'} • @${data['username'] ?? '-'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(data['changedAt'] as Timestamp?),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Old data
              const Text(
                'Previous',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 4),
              _buildDataBox(oldData, Colors.red.shade50),
              const SizedBox(height: 12),
              // Arrow
              const Center(
                child: Icon(Icons.arrow_downward, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              // New data
              const Text(
                'Updated to',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 4),
              _buildDataBox(newData, Colors.green.shade50),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDataBox(Map<String, dynamic> data, Color bgColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDataRow('Bank',
              data['bankName']?.toString().isEmpty ?? true
                  ? '(empty)'
                  : data['bankName']),
          const SizedBox(height: 4),
          _buildDataRow(
              'Account #',
              data['accountNumber']?.toString().isEmpty ?? true
                  ? '(empty)'
                  : data['accountNumber']),
          const SizedBox(height: 4),
          _buildDataRow(
              'Holder',
              data['accountHolderName']?.toString().isEmpty ?? true
                  ? '(empty)'
                  : data['accountHolderName']),
        ],
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: const Text('Bank Change Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all as read',
            onPressed: () => _markAllAsRead(context),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bank_change_logs')
            .orderBy('changedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.account_balance, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No bank changes yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final allDocs = snapshot.data!.docs.toList();
// Sort: unread first, then by date (newest first within each group)
allDocs.sort((a, b) {
  final aData = a.data() as Map<String, dynamic>;
  final bData = b.data() as Map<String, dynamic>;
  final aRead = aData['isRead'] == true ? 1 : 0;
  final bRead = bData['isRead'] == true ? 1 : 0;
  if (aRead != bRead) return aRead.compareTo(bRead);
  // Both same read status, sort by date (newest first)
  final aTime = aData['changedAt'] as Timestamp?;
  final bTime = bData['changedAt'] as Timestamp?;
  if (aTime == null) return 1;
  if (bTime == null) return -1;
  return bTime.compareTo(aTime);
});
final docs = allDocs;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['isRead'] == true;
              final newData =
                  (data['newData'] as Map<String, dynamic>?) ?? {};

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: isRead ? 1 : 3,
                color: isRead ? null : Colors.indigo.shade50,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showDetailDialog(context, data, doc.id),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.account_balance,
                                color: Colors.red.shade700,
                                size: 24,
                              ),
                            ),
                            if (!isRead)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      data['displayName'] ?? '-',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isRead
                                            ? FontWeight.w500
                                            : FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (!isRead)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${data['employeeId'] ?? '-'} updated bank info',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'New: ${newData['bankName'] ?? '-'} • ${newData['accountNumber'] ?? '-'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.indigo.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(data['changedAt'] as Timestamp?),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}