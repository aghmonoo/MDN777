import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';

/// Soft-delete store. Deleted users / messages / chats are copied here
/// before the original document is removed, so they can be restored.
/// Entries older than [retentionDays] are purged automatically the next
/// time an admin opens the Recycle Bin page.
class RecycleBin {
  RecycleBin._();

  static const int retentionDays = 30;
  static const String collection = 'recycle_bin';

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(collection);

  static DocumentReference<Map<String, dynamic>> newRef() => _col.doc();

  static String get _me =>
      FirebaseAuth.instance.currentUser?.email?.split('@').first ?? '';

  /// Builds the payload stored in the recycle bin.
  static Map<String, dynamic> entry({
    required String type, // 'user' | 'message' | 'chat'
    required String originalPath,
    required Map<String, dynamic> data,
    required String label,
    String sublabel = '',
    String? groupId,
    String? groupLabel,
  }) {
    final now = DateTime.now();
    return {
      'type': type,
      'originalPath': originalPath,
      'data': data,
      'label': label,
      'sublabel': sublabel,
      if (groupId != null) 'groupId': groupId,
      if (groupLabel != null) 'groupLabel': groupLabel,
      'deletedBy': _me,
      'deletedAt': Timestamp.fromDate(now),
      'expiresAt':
          Timestamp.fromDate(now.add(const Duration(days: retentionDays))),
    };
  }

  static Future<void> addOne({
    required String type,
    required String originalPath,
    required Map<String, dynamic> data,
    required String label,
    String sublabel = '',
  }) async {
    await newRef().set(entry(
      type: type,
      originalPath: originalPath,
      data: data,
      label: label,
      sublabel: sublabel,
    ));
  }

  /// Restores every document in [items] to its original path and removes
  /// the bin entries.
  static Future<void> restore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  ) async {
    final db = FirebaseFirestore.instance;
    for (var i = 0; i < items.length; i += 200) {
      final end = (i + 200 > items.length) ? items.length : i + 200;
      final writeBatch = db.batch();
      for (final d in items.sublist(i, end)) {
        final m = d.data();
        final path = (m['originalPath'] ?? '').toString();
        if (path.isEmpty) continue;
        writeBatch.set(
          db.doc(path),
          Map<String, dynamic>.from(m['data'] as Map? ?? {}),
        );
        writeBatch.delete(d.reference);
      }
      await writeBatch.commit();
    }
  }

  static Future<void> purge(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
  ) async {
    final db = FirebaseFirestore.instance;
    for (var i = 0; i < items.length; i += 300) {
      final end = (i + 300 > items.length) ? items.length : i + 300;
      final writeBatch = db.batch();
      for (final d in items.sublist(i, end)) {
        writeBatch.delete(d.reference);
      }
      await writeBatch.commit();
    }
  }

  /// Deletes bin entries whose retention window has passed.
  static Future<int> purgeExpired() async {
    final db = FirebaseFirestore.instance;
    int total = 0;
    while (true) {
      final snap = await _col
          .where('expiresAt', isLessThanOrEqualTo: Timestamp.now())
          .limit(300)
          .get();
      if (snap.docs.isEmpty) break;
      final writeBatch = db.batch();
      for (final d in snap.docs) {
        writeBatch.delete(d.reference);
      }
      await writeBatch.commit();
      total += snap.docs.length;
      if (snap.docs.length < 300) break;
    }
    return total;
  }
}

class AdminRecycleBinPage extends StatefulWidget {
  const AdminRecycleBinPage({super.key});

  @override
  State<AdminRecycleBinPage> createState() => _AdminRecycleBinPageState();
}

class _AdminRecycleBinPageState extends State<AdminRecycleBinPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _binStream;
  String _filter = 'all';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _binStream = FirebaseFirestore.instance
        .collection(RecycleBin.collection)
        .orderBy('deletedAt', descending: true)
        .snapshots();
    RecycleBin.purgeExpired();
  }

  String _ago(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays}d ago';
  }

  int _daysLeft(Timestamp? ts) {
    if (ts == null) return RecycleBin.retentionDays;
    final d = ts.toDate().difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  Future<void> _run(
    String verb,
    String message,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> items,
    Future<void> Function(List<QueryDocumentSnapshot<Map<String, dynamic>>>) fn,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(verb),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  verb == 'Restore' ? AppTheme.success : Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(verb),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await fn(items);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(verb == 'Restore' ? 'Restored' : 'Deleted forever'),
            backgroundColor:
                verb == 'Restore' ? AppTheme.success : Colors.red,
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
    if (mounted) setState(() => _busy = false);
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
        title: const Text('Recycle Bin'),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: AppTheme.primarySurface,
            child: Row(
              children: [
                const Icon(Icons.schedule,
                    size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Items are deleted forever after '
                    '${RecycleBin.retentionDays} days.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _chip('All', 'all'),
                const SizedBox(width: 8),
                _chip('Users', 'user'),
                const SizedBox(width: 8),
                _chip('Messages', 'message'),
                const SizedBox(width: 8),
                _chip('Chats', 'chat'),
                const SizedBox(width: 8),
                _chip('Bank', 'banklog'),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _binStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final docs = (snapshot.data?.docs ?? []).where((d) {
                  if (_filter == 'all') return true;
                  return (d.data()['type'] ?? '') == _filter;
                }).toList();

                if (docs.isEmpty) return _empty();

                // Group entries that were deleted together.
                final groups =
                    <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
                final order = <String>[];
                for (final d in docs) {
                  final key = (d.data()['groupId'] ?? d.id).toString();
                  if (!groups.containsKey(key)) {
                    groups[key] = [];
                    order.add(key);
                  }
                  groups[key]!.add(d);
                }

                return ListView.builder(
                  key: const PageStorageKey('recycleBin'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: order.length,
                  itemBuilder: (context, index) {
                    final items = groups[order[index]]!;
                    return _card(items);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _card(List<QueryDocumentSnapshot<Map<String, dynamic>>> items) {
    final first = items.first.data();
    final type = (first['type'] ?? '').toString();
    final isGroup = items.length > 1;

    final title = isGroup
        ? (first['groupLabel'] ?? '${items.length} items').toString()
        : (first['label'] ?? '-').toString();
    final subtitle = isGroup
        ? '${items.length} items'
        : (first['sublabel'] ?? '').toString();

    final icon = type == 'user'
        ? Icons.person_outline
        : type == 'chat'
            ? Icons.forum_outlined
            : type == 'banklog'
                ? Icons.account_balance_outlined
                : Icons.chat_bubble_outline;
    final color = type == 'user'
        ? AppTheme.blueIcon
        : type == 'chat'
            ? AppTheme.pinkIcon
            : type == 'banklog'
                ? const Color(0xFFDC2626)
                : AppTheme.amberIcon;

    final daysLeft = _daysLeft(first['expiresAt'] as Timestamp?);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 0.5),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'by @${first['deletedBy'] ?? '-'} · '
                      '${_ago(first['deletedAt'] as Timestamp?)} · '
                      '$daysLeft days left',
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                          'Restore',
                          isGroup
                              ? 'Restore ${items.length} items?'
                              : 'Restore "$title"?',
                          items,
                          RecycleBin.restore,
                        ),
                icon: const Icon(Icons.restore, size: 16),
                label: const Text('Restore', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.success,
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                          'Delete forever',
                          isGroup
                              ? '${items.length} items will be gone for good.'
                              : '"$title" will be gone for good.',
                          items,
                          RecycleBin.purge,
                        ),
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text('Delete', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primarySurface,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(Icons.delete_outline,
                size: 38, color: AppTheme.primary),
          ),
          const SizedBox(height: 16),
          const Text(
            'Recycle bin is empty',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Deleted users and messages appear here',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
