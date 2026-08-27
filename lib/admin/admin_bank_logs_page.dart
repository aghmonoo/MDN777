import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'recycle_bin.dart';

class AdminBankLogsPage extends StatefulWidget {
  const AdminBankLogsPage({super.key});

  @override
  State<AdminBankLogsPage> createState() => _AdminBankLogsPageState();
}

class _AdminBankLogsPageState extends State<AdminBankLogsPage> {
  late final Stream<QuerySnapshot> _logsStream;
  final ScrollController _listController = ScrollController();

  bool _selectionMode = false;
  bool _isDeleting = false;
  final Set<String> _selectedIds = {};
  List<String> _visibleIds = [];

  @override
  void initState() {
    super.initState();
    _logsStream = FirebaseFirestore.instance
        .collection('bank_change_logs')
        .orderBy('changedAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String docId) {
    setState(() {
      if (_selectedIds.contains(docId)) {
        _selectedIds.remove(docId);
      } else {
        _selectedIds.add(docId);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete ${ids.length} log(s)'),
        content: const Text(
          'Selected bank change logs are moved to the Recycle Bin and can be '
          'restored within 30 days.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isDeleting = true);

    int deleted = 0;
    try {
      final db = FirebaseFirestore.instance;
      for (var i = 0; i < ids.length; i += 200) {
        final end = (i + 200 > ids.length) ? ids.length : i + 200;
        final writeBatch = db.batch();
        for (final id in ids.sublist(i, end)) {
          final ref = db.collection('bank_change_logs').doc(id);
          final snap = await ref.get();
          if (!snap.exists) continue;
          final data = snap.data() ?? <String, dynamic>{};
          writeBatch.set(
            RecycleBin.newRef(),
            RecycleBin.entry(
              type: 'banklog',
              originalPath: 'bank_change_logs/$id',
              data: data,
              label: (data['displayName'] ?? '-').toString(),
              sublabel: 'Bank change - @${data['username'] ?? '-'}',
            ),
          );
          writeBatch.delete(ref);
          deleted++;
        }
        await writeBatch.commit();
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
        _isDeleting = false;
        _selectionMode = false;
        _selectedIds.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$deleted log(s) moved to Recycle Bin'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

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
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Mark all as read?'),
        content: const Text('This will mark all unread logs as read.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3730A3),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
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
    } catch (_) {}
  }

  void _showDetailDialog(
      BuildContext context, Map<String, dynamic> data, String docId) {
    if (data['isRead'] != true) {
      _markAsRead(docId);
    }

    final oldData = (data['oldData'] as Map<String, dynamic>?) ?? {};
    final newData = (data['newData'] as Map<String, dynamic>?) ?? {};
    final displayName = data['displayName'] ?? '-';
    final initial = displayName.toString().isNotEmpty
        ? displayName.toString().substring(0, 1).toUpperCase()
        : '?';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
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
                          fontSize: 17,
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
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${data['employeeId'] ?? '-'} · @${data['username'] ?? '-'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatDate(data['changedAt'] as Timestamp?),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _diffLabel('PREVIOUS', const Color(0xFFDC2626)),
                const SizedBox(height: 6),
                _diffBox(oldData, const Color(0xFFFEE2E2),
                    const Color(0xFFDC2626)),
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3730A3), AppTheme.primary],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_downward,
                        color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(height: 12),
                _diffLabel('UPDATED TO', const Color(0xFF059669)),
                const SizedBox(height: 6),
                _diffBox(newData, const Color(0xFFD1FAE5),
                    const Color(0xFF059669)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: AppTheme.background,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _diffLabel(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _diffBox(
      Map<String, dynamic> data, Color bgColor, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _diffRow(
            'Bank',
            (data['bankName']?.toString().isEmpty ?? true)
                ? '(empty)'
                : data['bankName'].toString(),
          ),
          const SizedBox(height: 6),
          _diffRow(
            'Account #',
            (data['accountNumber']?.toString().isEmpty ?? true)
                ? '(empty)'
                : data['accountNumber'].toString(),
          ),
          const SizedBox(height: 6),
          _diffRow(
            'Holder',
            (data['accountHolderName']?.toString().isEmpty ?? true)
                ? '(empty)'
                : data['accountHolderName'].toString(),
          ),
        ],
      ),
    );
  }

  Widget _diffRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: _isDeleting ? null : _exitSelection,
              )
            : null,
        title: Text(
          _selectionMode
              ? '${_selectedIds.length} selected'
              : 'Bank Change Logs',
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: 'Select all',
                  onPressed: _isDeleting
                      ? null
                      : () => setState(() {
                            _selectedIds
                              ..clear()
                              ..addAll(_visibleIds);
                          }),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete selected',
                  onPressed: (_selectedIds.isEmpty || _isDeleting)
                      ? null
                      : _deleteSelected,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.checklist_outlined),
                  tooltip: 'Select logs',
                  onPressed: () => setState(() => _selectionMode = true),
                ),
                IconButton(
                  icon: const Icon(Icons.done_all),
                  tooltip: 'Mark all as read',
                  onPressed: () => _markAllAsRead(context),
                ),
              ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _logsStream,
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

          final allDocs = snapshot.data!.docs.toList();
          allDocs.sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aRead = aData['isRead'] == true ? 1 : 0;
            final bRead = bData['isRead'] == true ? 1 : 0;
            if (aRead != bRead) return aRead.compareTo(bRead);
            final aTime = aData['changedAt'] as Timestamp?;
            final bTime = bData['changedAt'] as Timestamp?;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          final unreadCount =
              allDocs.where((d) => (d.data() as Map)['isRead'] != true).length;

          _visibleIds = allDocs.map((d) => d.id).toList();

          return ListView.builder(
            key: const PageStorageKey('bankLogs'),
            controller: _listController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: allDocs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildHeader(allDocs.length, unreadCount);
              final doc = allDocs[index - 1];
              final data = doc.data() as Map<String, dynamic>;
              return _logCard(context, doc.id, data);
            },
          );
        },
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
                colors: [Color(0xFFFECACA), Color(0xFFFEE2E2)],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.account_balance_outlined,
                size: 44, color: Color(0xFFDC2626)),
          ),
          const SizedBox(height: 20),
          const Text(
            'No bank changes yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Employee bank account updates will appear here',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int total, int unread) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, AppTheme.primarySurface],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primarySoft, width: 0.8),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFECACA), Color(0xFFFEE2E2)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.account_balance_outlined,
                size: 24, color: Color(0xFFDC2626)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Text(
                        'total',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unread NEW',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Employee bank account updates',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logCard(
      BuildContext context, String docId, Map<String, dynamic> data) {
    final isRead = data['isRead'] == true;
    final isSelected = _selectedIds.contains(docId);
    final newData = (data['newData'] as Map<String, dynamic>?) ?? {};
    final displayName = data['displayName'] ?? '-';
    final initial = displayName.toString().isNotEmpty
        ? displayName.toString().substring(0, 1).toUpperCase()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: isRead
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, AppTheme.primarySurface],
              ),
        color: isSelected
            ? AppTheme.primarySurface
            : (isRead ? Colors.white : null),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? AppTheme.primary
              : (isRead ? AppTheme.border : AppTheme.primarySoft),
          width: isSelected ? 1.2 : (isRead ? 0.5 : 0.8),
        ),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: _isDeleting
              ? null
              : () {
                  setState(() {
                    _selectionMode = true;
                    _selectedIds.add(docId);
                  });
                },
          onTap: _isDeleting
              ? null
              : (_selectionMode
                  ? () => _toggleSelect(docId)
                  : () => _showDetailDialog(context, data, docId)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_selectionMode)
                  SizedBox(
                    width: 34,
                    child: Checkbox(
                      value: isSelected,
                      activeColor: AppTheme.primary,
                      onChanged:
                          _isDeleting ? null : (_) => _toggleSelect(docId),
                    ),
                  ),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFECACA), Color(0xFFFEE2E2)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (!isRead)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white, width: 2),
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
                              displayName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: isRead
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isRead)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF92400E),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${data['employeeId'] ?? '-'} updated bank info',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.arrow_forward,
                                size: 10, color: AppTheme.primary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${newData['bankName'] ?? '-'} · ${newData['accountNumber'] ?? '-'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _formatDate(data['changedAt'] as Timestamp?),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textTertiary,
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