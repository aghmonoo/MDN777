import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../theme.dart';
import '../documents_section.dart';

class AdminUserEditPage extends StatefulWidget {
  final String? userId;

  const AdminUserEditPage({super.key, this.userId});

  @override
  State<AdminUserEditPage> createState() => _AdminUserEditPageState();
}

class _AdminUserEditPageState extends State<AdminUserEditPage> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _batchController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  String _role = 'employee';
  String _department = 'Moderation';
  String _position = 'QA';
  DateTime? _joinDate;

  bool _isLoading = false;
  bool _isSaving = false;

  bool get _isEditing => widget.userId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadUser();
    }
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _usernameController.text = data['username'] ?? '';
        _displayNameController.text = data['displayName'] ?? '';
        _employeeIdController.text = data['employeeId'] ?? '';
        _phoneController.text = (data['phone'] ?? '').toString();
        _emailController.text = data['email'] ?? '';
        _batchController.text = (data['batch'] ?? '').toString();
        _role = data['role'] ?? 'employee';
        _department = data['department'] ?? 'Moderation';
        final pos = (data['position'] ?? 'QA').toString();
        _position = const ['QA', 'TL', 'Mod'].contains(pos) ? pos : 'QA';

        if (data['joinDate'] is Timestamp) {
          _joinDate = (data['joinDate'] as Timestamp).toDate();
        }

        if (_role == 'admin') {
          _department = 'Admin';
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading: $e')),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickJoinDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _joinDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _joinDate = picked);
    }
  }

  void _emailToUsername(String value) {
    if (_isEditing) return;
    final v = value.trim();
    if (!v.contains('@')) return;
    _usernameController.text = v.split('@').first.toLowerCase();
    setState(() {});
  }

  Future<void> _save() async {
    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();
    final employeeId = _employeeIdController.text.trim();
    final batch = _batchController.text.trim();

    if (username.isEmpty || displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username and Display Name are required')),
      );
      return;
    }

    if (!_isEditing && _passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    if (_role == 'employee' && _joinDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join date is required for employee')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (!_isEditing) {
        final existing = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: username)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Username "$username" already exists'),
                backgroundColor: Colors.red,
              ),
            );
            setState(() => _isSaving = false);
          }
          return;
        }
      }

      final data = <String, dynamic>{
        'username': username,
        'email': _emailController.text.trim(),
        'displayName': displayName,
        'employeeId': employeeId,
        'phone': _phoneController.text.trim(),
        'role': _role,
        'department': _role == 'admin' ? 'Admin' : _department,
      };

      if (_role == 'employee') {
        data['batch'] = int.tryParse(batch) ?? 0;
        data['joinDate'] = _joinDate;
        if (_department == 'Management') {
          data['position'] = _position;
        } else {
          data['position'] = FieldValue.delete();
        }
        if (!_isEditing) {
          data['bankName'] = '';
          data['accountNumber'] = '';
          data['accountHolderName'] = '';
        }
      } else {
        data['batch'] = FieldValue.delete();
        data['joinDate'] = FieldValue.delete();
        data['position'] = FieldValue.delete();
      }

      if (_isEditing) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .update(data);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User updated'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      } else {
        FirebaseApp? secondaryApp;
        try {
          try {
            secondaryApp = await Firebase.initializeApp(
              name: 'SecondaryUserCreator',
              options: Firebase.app().options,
            );
          } catch (_) {
            secondaryApp = Firebase.app('SecondaryUserCreator');
          }

          final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
          final loginEmail = '$username@staffconnect.app';

          String uid;
          try {
            final cred = await secondaryAuth.createUserWithEmailAndPassword(
              email: loginEmail,
              password: _passwordController.text,
            );
            uid = cred.user!.uid;
            await secondaryAuth.signOut();
          } on FirebaseAuthException catch (e) {
            if (e.code != 'email-already-in-use') rethrow;
            // The login account outlived its profile - most often the staff
            // member was deleted and is now being re-added. Take it over by
            // setting the new password rather than blocking the username.
            final result = await FirebaseFunctions.instanceFor(
              region: 'asia-southeast1',
            ).httpsCallable('adminSetPassword').call<Map<String, dynamic>>({
              'username': username,
              'newPassword': _passwordController.text,
            });
            uid = (result.data['uid'] ?? '').toString();
            if (uid.isEmpty) rethrow;
          }

          final createData = Map<String, dynamic>.from(data)
            ..removeWhere((key, value) => value is FieldValue);
          createData['createdAt'] = FieldValue.serverTimestamp();

          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set(createData);

          if (mounted) {
            _showCreateSuccessDialog(username);
          }
        } on FirebaseAuthException catch (e) {
          final msg = e.code == 'email-already-in-use'
              ? 'Could not reuse the existing login for "$username"'
              : e.code == 'weak-password'
                  ? 'Password too weak'
                  : 'Auth error: ${e.code}';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg), backgroundColor: Colors.red),
            );
          }
        } finally {
          try {
            await secondaryApp?.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  void _showCreateSuccessDialog(String username) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check_circle,
                  color: Colors.green, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('User Created'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Login account and profile created.'),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primarySurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primarySoft),
              ),
              child: Text(
                'Email: $username@staffconnect.app',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _employeeIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _batchController.dispose();
    _passwordController.dispose();
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
        title: Text(_isEditing ? 'Edit User' : 'Add User'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: TextButton(
                onPressed: _save,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'SAVE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('BASIC INFORMATION'),
                  const SizedBox(height: 8),
                  _card(
                    child: Column(
                      children: [
                        _input(
                          controller: _usernameController,
                          label: 'Username *',
                          icon: Icons.alternate_email,
                          enabled: !_isEditing,
                          helper: _isEditing
                              ? 'Username cannot be changed'
                              : 'Login email: username@staffconnect.app',
                        ),
                        const Divider(height: 1, color: AppTheme.border),
                        _input(
                          controller: _displayNameController,
                          label: 'Display Name *',
                          icon: Icons.person_outline,
                        ),
                        const Divider(height: 1, color: AppTheme.border),
                        _input(
                          controller: _employeeIdController,
                          label: 'Employee ID',
                          icon: Icons.badge_outlined,
                          helper: 'e.g. EMP-001 or ADMIN-001',
                        ),
                        const Divider(height: 1, color: AppTheme.border),
                        _input(
                          controller: _phoneController,
                          label: 'Phone Number',
                          icon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          helper: 'Staff can update this themselves',
                        ),
                        const Divider(height: 1, color: AppTheme.border),
                        _input(
                          controller: _emailController,
                          label: 'Company Email',
                          icon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          helper: 'Optional - for records only',
                          onChanged: _isEditing ? null : _emailToUsername,
                        ),
                        if (!_isEditing) ...[
                          const Divider(height: 1, color: AppTheme.border),
                          _input(
                            controller: _passwordController,
                            label: 'Password *',
                            icon: Icons.lock_outline,
                            helper: 'Minimum 6 characters',
                            obscureText: _obscurePassword,
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 18,
                                color: AppTheme.textSecondary,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionLabel('ROLE'),
                  const SizedBox(height: 8),
                  _card(
                    child: _dropdown(
                      label: 'Role',
                      icon: Icons.shield_outlined,
                      value: _role,
                      items: const [
                        DropdownMenuItem(
                            value: 'employee', child: Text('Employee')),
                        DropdownMenuItem(
                            value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _role = v!;
                          if (_role == 'admin') {
                            _department = 'Admin';
                          } else if (_department == 'Admin') {
                            _department = 'Moderation';
                          }
                        });
                      },
                    ),
                  ),
                  if (_role == 'employee') ...[
                    const SizedBox(height: 20),
                    _sectionLabel('DEPARTMENT & POSITION'),
                    const SizedBox(height: 8),
                    _card(
                      child: Column(
                        children: [
                          _dropdown(
                            label: 'Department',
                            icon: Icons.business_outlined,
                            value: _department,
                            items: const [
                              DropdownMenuItem(
                                  value: 'Moderation',
                                  child: Text('Moderation')),
                              DropdownMenuItem(
                                  value: 'Management',
                                  child: Text('Management')),
                            ],
                            onChanged: (v) =>
                                setState(() => _department = v!),
                          ),
                          if (_department == 'Management') ...[
                            const Divider(
                                height: 1, color: AppTheme.border),
                            _dropdown(
                              label: 'Position',
                              icon: Icons.work_outline,
                              value: _position,
                              items: const [
                                DropdownMenuItem(
                                    value: 'QA', child: Text('QA')),
                                DropdownMenuItem(
                                    value: 'TL', child: Text('TL')),
                                DropdownMenuItem(
                                    value: 'Mod', child: Text('Mod')),
                              ],
                              onChanged: (v) =>
                                  setState(() => _position = v!),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('EMPLOYMENT DETAILS'),
                    const SizedBox(height: 8),
                    _card(
                      child: Column(
                        children: [
                          _input(
                            controller: _batchController,
                            label: 'Batch',
                            icon: Icons.numbers,
                            helper: 'e.g. 1, 2, 3...',
                            keyboardType: TextInputType.number,
                          ),
                          const Divider(height: 1, color: AppTheme.border),
                          _datePicker(),
                        ],
                      ),
                    ),
                  ],
                  if (_isEditing && _role == 'employee') ...[
                    const SizedBox(height: 20),
                    _sectionLabel('DOCUMENTS'),
                    const SizedBox(height: 8),
                    _card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: DocumentsSection(
                          userId: widget.userId!,
                          editable: true,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
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

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 0.5),
        boxShadow: AppTheme.cardShadow,
      ),
      child: child,
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? helper,
    bool enabled = true,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 14,
          color: enabled ? AppTheme.textPrimary : AppTheme.textTertiary,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
          helperText: helper,
          helperStyle: const TextStyle(
            fontSize: 11,
            color: AppTheme.textTertiary,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(icon, size: 18, color: AppTheme.textSecondary),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String label,
    required IconData icon,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Icon(icon, size: 18, color: AppTheme.textSecondary),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 0, minHeight: 0),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _datePicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _pickJoinDate,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Join Date *',
            labelStyle: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
            prefixIcon: Padding(
              padding: EdgeInsets.only(left: 12, right: 8),
              child: Icon(Icons.calendar_today_outlined,
                  size: 18, color: AppTheme.textSecondary),
            ),
            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: Icon(Icons.chevron_right,
                color: AppTheme.textTertiary),
            border: InputBorder.none,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          ),
          child: Text(
            _joinDate == null
                ? 'Select date'
                : '${_joinDate!.day}/${_joinDate!.month}/${_joinDate!.year}',
            style: TextStyle(
              fontSize: 14,
              color: _joinDate == null
                  ? AppTheme.textTertiary
                  : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}