import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import '../file_download_helper.dart';
import '../theme.dart';
import 'admin_user_edit_page.dart';
import 'recycle_bin.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  String _filter = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isImporting = false;
  String _importStatus = '';

  bool _selectionMode = false;
  bool _isDeleting = false;
  final Set<String> _selectedIds = {};
  List<String> _selectableVisibleIds = [];
  String _myUsername = '';

  late final Stream<QuerySnapshot> _usersStream;
  final ScrollController _listController = ScrollController();

  @override
  void initState() {
    super.initState();
    _myUsername =
        FirebaseAuth.instance.currentUser?.email?.split('@').first ?? '';
    _usersStream = FirebaseFirestore.instance.collection('users').snapshots();
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
        title: Text('Delete ${ids.length} user(s)'),
        content: const Text(
          'Selected user profiles are moved to the Recycle Bin and can be '
          'restored within 30 days.\n\n'
          'Note: Login (auth) accounts must still be deleted manually from '
          'Firebase Console.',
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
        final chunk = ids.sublist(i, end);
        final writeBatch = db.batch();
        for (final id in chunk) {
          final ref = db.collection('users').doc(id);
          final snap = await ref.get();
          if (!snap.exists) continue;
          final data = snap.data() ?? <String, dynamic>{};
          writeBatch.set(
            RecycleBin.newRef(),
            RecycleBin.entry(
              type: 'user',
              originalPath: 'users/$id',
              data: data,
              label: (data['displayName'] ?? id).toString(),
              sublabel: '@${data['username'] ?? '-'} - ${data['role'] ?? '-'}',
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
          content: Text('$deleted user(s) moved to Recycle Bin'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteUser(String docId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete User'),
        content: Text(
          'Delete $displayName?\n\nNote: This only deletes the Firestore profile. The auth account must be deleted manually from Firebase Console.',
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

    try {
      final db = FirebaseFirestore.instance;
      final ref = db.collection('users').doc(docId);
      final snap = await ref.get();
      final data = snap.data() ?? <String, dynamic>{};

      final writeBatch = db.batch();
      writeBatch.set(
        RecycleBin.newRef(),
        RecycleBin.entry(
          type: 'user',
          originalPath: 'users/$docId',
          data: data,
          label: (data['displayName'] ?? displayName).toString(),
          sublabel: '@${data['username'] ?? '-'} - ${data['role'] ?? '-'}',
        ),
      );
      writeBatch.delete(ref);
      await writeBatch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User moved to Recycle Bin'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _resetPassword(String username) async {
    if (username.isEmpty) return;

    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscure = true;
    bool busy = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;
              setDialogState(() => busy = true);
              try {
                final callable = FirebaseFunctions.instanceFor(
                  region: 'asia-southeast1',
                ).httpsCallable('adminSetPassword');
                await callable.call<Map<String, dynamic>>({
                  'username': username,
                  'newPassword': controller.text,
                });
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Password updated for @$username'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } on FirebaseFunctionsException catch (e) {
                setDialogState(() => busy = false);
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(e.message ?? e.code)),
                  );
                }
              } catch (e) {
                setDialogState(() => busy = false);
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            }

            return AlertDialog(
              title: Text('Reset password - @$username'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    helperText: 'At least 6 characters',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility : Icons.visibility_off,
                        size: 20,
                      ),
                      onPressed: () =>
                          setDialogState(() => obscure = !obscure),
                    ),
                  ),
                  validator: (v) => (v ?? '').length < 6
                      ? 'At least 6 characters'
                      : null,
                  onFieldSubmitted: (_) => busy ? null : submit(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      busy ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  

  DateTime? _parseDate(String raw) {
    if (raw.isEmpty) return null;
    final direct = DateTime.tryParse(raw);
    if (direct != null) return direct;
    final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(raw);
    if (m != null) {
      return DateTime(
        int.parse(m.group(3)!),
        int.parse(m.group(2)!),
        int.parse(m.group(1)!),
      );
    }
    return null;
  }

  Future<void> _downloadTemplate() async {
    try {
      final data = await rootBundle.load('assets/users_template.xlsx');
      final bytes = data.buffer.asUint8List();
      downloadFile(bytes, 'users_template.xlsx');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Template downloaded — fill rows then Import'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _importUsers() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final fileBytes = result.files.first.bytes;
    if (fileBytes == null) return;

    setState(() {
      _isImporting = true;
      _importStatus = 'Reading file...';
    });

    int success = 0;
    int failed = 0;
    final errors = <String>[];
    FirebaseApp? secondaryApp;

    try {
      final excel = Excel.decodeBytes(fileBytes);
      final sheet = excel.tables[excel.tables.keys.first]!;

      try {
        secondaryApp = await Firebase.initializeApp(
          name: 'SecondaryUserCreator',
          options: Firebase.app().options,
        );
      } catch (_) {
        secondaryApp = Firebase.app('SecondaryUserCreator');
      }

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty) continue;

        String cellAt(int i) =>
            (i < row.length ? row[i]?.value?.toString() ?? '' : '').trim();

        final email = cellAt(0);
        final usernameCell = cellAt(1);

        // username is derived from the company email when one is given;
        // the template keeps a preview formula in that column.
        final username = email.contains('@')
            ? email.split('@').first.trim().toLowerCase()
            : (usernameCell.startsWith('=') ? '' : usernameCell);

        final password = cellAt(2);
        final displayName = cellAt(3);
        final employeeId = cellAt(4);
        final role = cellAt(5).isEmpty ? 'employee' : cellAt(5);
        final department = cellAt(6);
        final position = cellAt(7);
        final batch = cellAt(8);
        final joinDate = cellAt(9);
        final bankName = cellAt(10);
        final accountNumber = cellAt(11);
        final accountHolderName = cellAt(12);

        // Skip blank template rows (the username column holds a preview
        // formula down to row 500, so "empty" rows are not really empty).
        final hasAnyData = email.isNotEmpty ||
            password.isNotEmpty ||
            displayName.isNotEmpty ||
            employeeId.isNotEmpty ||
            (usernameCell.isNotEmpty && !usernameCell.startsWith('='));
        if (!hasAnyData) continue;

        if (username.isEmpty || password.isEmpty) {
          failed++;
          errors.add('Row ${i + 1}: username/password missing');
          continue;
        }

        setState(() {
          _importStatus = 'Creating: $username';
        });

        try {
          final loginEmail = '$username@staffconnect.app';
          String uid;
          bool repaired = false;

          try {
            final cred = await secondaryAuth.createUserWithEmailAndPassword(
              email: loginEmail,
              password: password,
            );
            uid = cred.user!.uid;
          } on FirebaseAuthException catch (e) {
            if (e.code != 'email-already-in-use') rethrow;
            // The login account already exists (usually because an earlier
            // import created it but failed before writing the profile).
            // Sign in to recover the uid and rewrite the profile.
            final cred = await secondaryAuth.signInWithEmailAndPassword(
              email: loginEmail,
              password: password,
            );
            uid = cred.user!.uid;
            repaired = true;
          }

          final userData = <String, dynamic>{
            'username': username,
            'email': email,
            'displayName': displayName,
            'employeeId': employeeId,
            'role': role,
            'department': role == 'admin' ? 'Admin' : department,
            'createdAt': FieldValue.serverTimestamp(),
          };

          if (role != 'admin') {
            userData['batch'] = int.tryParse(batch) ?? 0;
            final parsedJoinDate = _parseDate(joinDate);
            if (parsedJoinDate != null) {
              userData['joinDate'] = Timestamp.fromDate(parsedJoinDate);
            }
            if (department == 'Management' && position.isNotEmpty) {
              userData['position'] = position;
            }
            userData['bankName'] = bankName;
            userData['accountNumber'] = accountNumber;
            userData['accountHolderName'] = accountHolderName;
          }

          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set(userData);

          await secondaryAuth.signOut();
          success++;
          if (repaired) {
            errors.add('Row ${i + 1}: $username login existed - profile fixed');
          }
        } on FirebaseAuthException catch (e) {
          failed++;
          if (e.code == 'weak-password') {
            errors.add('Row ${i + 1}: $username - password too weak');
          } else if (e.code == 'wrong-password' ||
              e.code == 'invalid-credential') {
            errors.add(
                'Row ${i + 1}: $username exists with a different password');
          } else {
            errors.add('Row ${i + 1}: ${e.code}');
          }
        } catch (e) {
          failed++;
          errors.add('Row ${i + 1}: $e');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }

    try {
      await secondaryApp?.delete();
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isImporting = false;
        _importStatus = '';
      });
      _showImportResult(success, failed, errors);
    }
  }

  void _showImportResult(int success, int failed, List<String> errors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                  Text('Created: $success'),
                ],
              ),
              if (failed > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Text('Failed: $failed'),
                  ],
                ),
              ],
              if (errors.isNotEmpty) ...[
                const Divider(),
                const Text('Details:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                ...errors.take(10).map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('• $e',
                          style: const TextStyle(fontSize: 12)),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listController.dispose();
    super.dispose();
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
          _selectionMode ? '${_selectedIds.length} selected' : 'Manage Users',
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
                              ..addAll(_selectableVisibleIds);
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
                  tooltip: 'Select users',
                  onPressed: _isImporting
                      ? null
                      : () => setState(() => _selectionMode = true),
                ),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: 'Download Excel Template',
                  onPressed: _isImporting ? null : _downloadTemplate,
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined),
                  tooltip: 'Bulk Import from Excel',
                  onPressed: _isImporting ? null : _importUsers,
                ),
              ],
      ),
      body: Column(
        children: [
          if (_isImporting)
            Container(
              padding: const EdgeInsets.all(12),
              color: AppTheme.primarySurface,
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _importStatus,
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
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search by name or ID...',
                      hintStyle: const TextStyle(
                        color: AppTheme.textTertiary,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(Icons.search,
                          size: 20, color: AppTheme.textSecondary),
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value.toLowerCase());
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _filterChip('All', 'all'),
                    const SizedBox(width: 8),
                    _filterChip('Admin', 'admin'),
                    const SizedBox(width: 8),
                    _filterChip('Employee', 'employee'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _usersStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _emptyState('No users found',
                      'Tap + to create the first user');
                }

                var docs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final role = data['role'] ?? 'employee';
                  final displayName =
                      (data['displayName'] ?? '').toString().toLowerCase();
                  final employeeId =
                      (data['employeeId'] ?? '').toString().toLowerCase();
                  final username =
                      (data['username'] ?? '').toString().toLowerCase();

                  if (_filter != 'all' && role != _filter) return false;

                  if (_searchQuery.isNotEmpty) {
                    if (!displayName.contains(_searchQuery) &&
                        !employeeId.contains(_searchQuery) &&
                        !username.contains(_searchQuery)) {
                      return false;
                    }
                  }
                  return true;
                }).toList();

                docs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aRole = aData['role'] == 'admin' ? 0 : 1;
                  final bRole = bData['role'] == 'admin' ? 0 : 1;
                  if (aRole != bRole) return aRole.compareTo(bRole);
                  final aName = (aData['displayName'] ?? '').toString();
                  final bName = (bData['displayName'] ?? '').toString();
                  return aName.compareTo(bName);
                });

                if (docs.isEmpty) {
                  return _emptyState(
                      'No matches', 'Try a different search or filter');
                }

                _selectableVisibleIds = docs
                    .where((d) =>
                        ((d.data() as Map<String, dynamic>)['username'] ?? '')
                            .toString() !=
                        _myUsername)
                    .map((d) => d.id)
                    .toList();

                return ListView.builder(
                  key: const PageStorageKey('usersList'),
                  controller: _listController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _userCard(doc.id, data);
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton.extended(
        backgroundColor: const Color(0xFF3730A3),
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add User',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AdminUserEditPage(),
            ),
          );
        },
      ),
    );
  }

  Widget _userCard(String docId, Map<String, dynamic> data) {
    final isAdmin = data['role'] == 'admin';
    final displayName = data['displayName'] ?? '-';
    final isSelf = (data['username'] ?? '').toString() == _myUsername;
    final isSelected = _selectedIds.contains(docId);
    final initial = displayName.toString().isNotEmpty
        ? displayName.toString().substring(0, 1).toUpperCase()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primarySurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppTheme.primary : AppTheme.border,
          width: isSelected ? 1.2 : 0.5,
        ),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: isSelf
              ? null
              : () {
                  setState(() {
                    _selectionMode = true;
                    _selectedIds.add(docId);
                  });
                },
          onTap: (_selectionMode && !isSelf && !_isDeleting)
              ? () => _toggleSelect(docId)
              : null,
          child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if (_selectionMode)
              SizedBox(
                width: 34,
                child: isSelf
                    ? const Icon(Icons.lock_outline,
                        size: 18, color: AppTheme.textTertiary)
                    : Checkbox(
                        value: isSelected,
                        activeColor: AppTheme.primary,
                        onChanged: _isDeleting
                            ? null
                            : (_) => _toggleSelect(docId),
                      ),
              ),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isAdmin
                      ? const [Color(0xFF1E3A8A), Color(0xFF3730A3)]
                      : [AppTheme.pinkStart, AppTheme.pinkEnd],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: TextStyle(
                  color: isAdmin ? Colors.white : AppTheme.pinkIcon,
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3730A3).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield,
                                  size: 10, color: Color(0xFF3730A3)),
                              SizedBox(width: 3),
                              Text(
                                'ADMIN',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF3730A3),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '@${data['username'] ?? '-'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  if (!isAdmin) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${data['employeeId'] ?? '-'} · ${data['department'] ?? '-'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              enabled: !_selectionMode,
              icon: const Icon(Icons.more_vert,
                  color: AppTheme.textSecondary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) {
                if (value == 'edit') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminUserEditPage(userId: docId),
                    ),
                  );
                } else if (value == 'reset') {
                  _resetPassword(data['username'] ?? '');
                } else if (value == 'delete') {
                  _deleteUser(docId, data['displayName'] ?? 'user');
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined,
                          size: 17, color: Color(0xFF3730A3)),
                      SizedBox(width: 10),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'reset',
                  child: Row(
                    children: [
                      Icon(Icons.lock_reset,
                          size: 17, color: AppTheme.textSecondary),
                      SizedBox(width: 10),
                      Text('Reset Password'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          size: 17, color: Colors.red),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primarySoft, AppTheme.primaryLight],
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.people_outline,
                size: 44, color: Colors.white),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filter == value;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF3730A3), AppTheme.primary],
                  )
                : null,
            color: isSelected ? null : AppTheme.background,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.transparent : AppTheme.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppTheme.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}