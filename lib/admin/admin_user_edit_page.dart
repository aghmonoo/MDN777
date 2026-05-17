import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final _batchController = TextEditingController();

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
        _batchController.text = (data['batch'] ?? '').toString();
        _role = data['role'] ?? 'employee';
        _department = data['department'] ?? 'Moderation';
        _position = data['position'] ?? 'QA';

        if (data['joinDate'] is Timestamp) {
          _joinDate = (data['joinDate'] as Timestamp).toDate();
        }

        // If admin, department should be Admin
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

    if (_role == 'employee' && _joinDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Join date is required for employee')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Check duplicate username (for create mode)
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
        'displayName': displayName,
        'employeeId': employeeId,
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
        // Initialize bank fields for new employee
        if (!_isEditing) {
          data['bankName'] = '';
          data['accountNumber'] = '';
          data['accountHolderName'] = '';
        }
      } else {
        // Admin: remove employee-only fields
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
        await FirebaseFirestore.instance.collection('users').add(data);

        if (mounted) {
          _showCreateSuccessDialog(username);
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
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700),
            const SizedBox(width: 8),
            const Text('Profile Created'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('User profile created in database.'),
            const SizedBox(height: 16),
            const Text(
              'Next Step:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create login account in Firebase Console:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text('1. Open Firebase Console',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                  Text('2. Go to Authentication → Users',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                  Text('3. Click "Add user"',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                  const SizedBox(height: 8),
                  Text(
                    'Email: $username@staffconnect.app',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Password: (set your password)',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // back to users list
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
    _batchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
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
            TextButton(
              onPressed: _save,
              child: const Text('SAVE', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Basic Info
                  const Text(
                    'Basic Information',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _usernameController,
                    enabled: !_isEditing,
                    decoration: InputDecoration(
                      labelText: 'Username *',
                      border: const OutlineInputBorder(),
                      helperText: _isEditing
                          ? 'Username cannot be changed'
                          : 'Login email: username@staffconnect.app',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _displayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Display Name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _employeeIdController,
                    decoration: const InputDecoration(
                      labelText: 'Employee ID',
                      border: OutlineInputBorder(),
                      helperText: 'e.g. EMP-001 or ADMIN-001',
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Role
                  const Text(
                    'Role',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _role,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'employee', child: Text('Employee')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _role = value!;
                        if (_role == 'admin') {
                          _department = 'Admin';
                        } else if (_department == 'Admin') {
                          _department = 'Moderation';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  // Department (Employee only)
                  if (_role == 'employee') ...[
                    const Text(
                      'Department & Position',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _department,
                      decoration: const InputDecoration(
                        labelText: 'Department',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Moderation', child: Text('Moderation')),
                        DropdownMenuItem(
                            value: 'Management', child: Text('Management')),
                      ],
                      onChanged: (value) {
                        setState(() => _department = value!);
                      },
                    ),
                    if (_department == 'Management') ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _position,
                        decoration: const InputDecoration(
                          labelText: 'Position',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'QA', child: Text('QA')),
                          DropdownMenuItem(value: 'TL', child: Text('TL')),
                        ],
                        onChanged: (value) {
                          setState(() => _position = value!);
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Batch & Join Date
                    const Text(
                      'Employment Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _batchController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Batch',
                        border: OutlineInputBorder(),
                        prefixText: 'Batch ',
                        helperText: 'e.g. 1, 2, 3...',
                      ),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: _pickJoinDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Join Date *',
                          border: OutlineInputBorder(),
                          suffixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          _joinDate == null
                              ? 'Select date'
                              : '${_joinDate!.day}/${_joinDate!.month}/${_joinDate!.year}',
                          style: TextStyle(
                            color: _joinDate == null
                                ? Colors.grey
                                : Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Documents Section (edit mode, employee only)
                  if (_isEditing && _role == 'employee') ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Documents',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DocumentsSection(
                      userId: widget.userId!,
                      editable: true,
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}