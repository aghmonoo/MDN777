import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:html' as html;
import 'admin_user_edit_page.dart';

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

  Future<void> _deleteUser(String docId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text(
          'Delete $displayName?\n\nNote: This only deletes the Firestore profile. The auth account must be deleted manually from Firebase Console.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(docId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User deleted'),
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Password reset for @$username must be done in Firebase Console → Authentication',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
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

  Future<void> _downloadTemplate() async {
    try {
      final data = await rootBundle.load('assets/users_template.xlsx');
      final bytes = data.buffer.asUint8List();
      _downloadFile(bytes, 'users_template.xlsx');

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

      // Initialize secondary Firebase app to avoid logging out current admin
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

        final username = (row[0]?.value?.toString() ?? '').trim();
        final password = (row[1]?.value?.toString() ?? '').trim();
        final displayName = (row[2]?.value?.toString() ?? '').trim();
        final employeeId = (row[3]?.value?.toString() ?? '').trim();
        final role = (row[4]?.value?.toString() ?? 'employee').trim();
        final department = (row[5]?.value?.toString() ?? '').trim();
        final batch = (row[6]?.value?.toString() ?? '').trim();
        final joinDate = (row[7]?.value?.toString() ?? '').trim();

        if (username.isEmpty || password.isEmpty) {
          failed++;
          errors.add('Row ${i + 1}: username/password missing');
          continue;
        }

        setState(() {
          _importStatus = 'Creating ${i}/${sheet.rows.length - 1}: $username';
        });

        try {
          // Create Firebase Auth account on secondary app
          final email = '$username@staffconnect.app';
          final cred = await secondaryAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          final uid = cred.user!.uid;

          // Create Firestore document with same id as auth uid
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'username': username,
            'displayName': displayName,
            'employeeId': employeeId,
            'role': role,
            'department': department,
            'batch': batch,
            'joinDate': joinDate,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Sign out from secondary to keep it clean
          await secondaryAuth.signOut();

          success++;
        } on FirebaseAuthException catch (e) {
          failed++;
          if (e.code == 'email-already-in-use') {
            errors.add('Row ${i + 1}: $username already exists');
          } else if (e.code == 'weak-password') {
            errors.add('Row ${i + 1}: $username — password too weak');
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

    // Cleanup secondary app
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
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
                const Text('Errors:',
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
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: const Text('Manage Users'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'Download Excel Template',
            onPressed: _isImporting ? null : _downloadTemplate,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
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
              color: Colors.amber.shade50,
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_importStatus)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.indigo.shade50,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or ID...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
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
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildFilterChip('All', 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Admin', 'admin'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Employee', 'employee'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No users found'));
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
                  return const Center(
                    child: Text('No users match your filter'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isAdmin = data['role'] == 'admin';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isAdmin ? Colors.indigo : Colors.deepPurple,
                          child: Text(
                            (data['displayName'] ?? 'U')
                                .toString()
                                .substring(0, 1)
                                .toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                data['displayName'] ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isAdmin)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'ADMIN',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.indigo.shade700,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '@${data['username'] ?? '-'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (!isAdmin)
                              Text(
                                '${data['employeeId'] ?? '-'} • ${data['department'] ?? '-'}${data['position'] != null ? ' (${data['position']})' : ''}',
                                style: const TextStyle(fontSize: 11),
                              ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == 'edit') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => AdminUserEditPage(
                                    userId: doc.id,
                                  ),
                                ),
                              );
                            } else if (value == 'reset') {
                              _resetPassword(data['username'] ?? '');
                            } else if (value == 'delete') {
                              _deleteUser(
                                doc.id,
                                data['displayName'] ?? 'user',
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'reset',
                              child: Row(
                                children: [
                                  Icon(Icons.lock_reset, size: 18),
                                  SizedBox(width: 8),
                                  Text('Reset Password'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete,
                                      size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add),
        label: const Text('Add User'),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AdminUserEditPage(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.indigo : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}