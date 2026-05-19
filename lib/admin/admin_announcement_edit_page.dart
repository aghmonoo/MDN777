import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import '../cloudinary_config.dart';
import '../theme.dart';

class AdminAnnouncementEditPage extends StatefulWidget {
  final String? announcementId;

  const AdminAnnouncementEditPage({super.key, this.announcementId});

  @override
  State<AdminAnnouncementEditPage> createState() =>
      _AdminAnnouncementEditPageState();
}

class _AdminAnnouncementEditPageState
    extends State<AdminAnnouncementEditPage> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  List<String> _imageUrls = [];
  List<Map<String, dynamic>> _pdfs = [];

  bool _isLoading = false;
  bool _isUploading = false;
  String _uploadingFileName = '';

  late final CloudinaryPublic _cloudinary;

  bool get _isEditing => widget.announcementId != null;

  @override
  void initState() {
    super.initState();
    _cloudinary = CloudinaryPublic(
      CloudinaryConfig.cloudName,
      CloudinaryConfig.uploadPreset,
    );
    if (_isEditing) {
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('announcements')
          .doc(widget.announcementId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _titleController.text = data['title'] ?? '';
        _bodyController.text = data['body'] ?? '';
        _imageUrls =
            (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];
        _pdfs = ((data['pdfs'] as List<dynamic>?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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

  Future<void> _pickAndUploadImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() => _isUploading = true);

    for (final file in result.files) {
      if (file.bytes == null) continue;
      setState(() => _uploadingFileName = file.name);

      try {
        final response = await _cloudinary.uploadFile(
          CloudinaryFile.fromBytesData(
            file.bytes!,
            identifier: file.name,
            resourceType: CloudinaryResourceType.Image,
          ),
        );

        setState(() {
          _imageUrls.add(response.secureUrl);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed for ${file.name}: $e')),
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadingFileName = '';
      });
    }
  }

  Future<void> _pickAndUploadPdfs() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() => _isUploading = true);

    for (final file in result.files) {
      if (file.bytes == null) continue;
      setState(() => _uploadingFileName = file.name);

      try {
        final response = await _cloudinary.uploadFile(
          CloudinaryFile.fromBytesData(
            file.bytes!,
            identifier: file.name,
            resourceType: CloudinaryResourceType.Raw,
          ),
        );

        setState(() {
          _pdfs.add({
            'name': file.name,
            'url': response.secureUrl,
          });
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload failed for ${file.name}: $e')),
          );
        }
      }
    }

    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadingFileName = '';
      });
    }
  }

  void _removeImage(int index) => setState(() => _imageUrls.removeAt(index));
  void _removePdf(int index) => setState(() => _pdfs.removeAt(index));

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final createdBy = user?.email?.split('@').first ?? 'admin';

      final data = {
        'title': title,
        'body': body,
        'imageUrls': _imageUrls,
        'pdfs': _pdfs,
        'createdBy': createdBy,
      };

      if (_isEditing) {
        data['updatedAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(widget.announcementId)
            .update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('announcements')
            .add(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Updated' : 'Created'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
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
        title: Text(_isEditing ? 'Edit Announcement' : 'New Announcement'),
        actions: [
          if (_isLoading)
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('CONTENT'),
            const SizedBox(height: 8),
            _card(
              child: Column(
                children: [
                  _textInput(
                    controller: _titleController,
                    hint: 'Title *',
                    icon: Icons.title,
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _textInput(
                    controller: _bodyController,
                    hint: 'Body',
                    icon: Icons.notes,
                    maxLines: 8,
                    minLines: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('PHOTOS'),
            const SizedBox(height: 8),
            _card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppTheme.blueStart,
                                    AppTheme.blueEnd
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.photo_outlined,
                                  size: 16, color: AppTheme.blueIcon),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_imageUrls.length} photo${_imageUrls.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        _addButton(
                          icon: Icons.add_photo_alternate_outlined,
                          label: 'Add',
                          onTap:
                              _isUploading ? null : _pickAndUploadImages,
                        ),
                      ],
                    ),
                    if (_imageUrls.isEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.border,
                            style: BorderStyle.solid,
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.image_outlined,
                                size: 32, color: AppTheme.textTertiary),
                            SizedBox(height: 6),
                            Text(
                              'No photos yet',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _imageUrls.length,
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  _imageUrls[index],
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _removeImage(index),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withOpacity(0.3),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('PDF ATTACHMENTS'),
            const SizedBox(height: 8),
            _card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.picture_as_pdf_outlined,
                                size: 16,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${_pdfs.length} file${_pdfs.length == 1 ? '' : 's'}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        _addButton(
                          icon: Icons.attach_file,
                          label: 'Add',
                          onTap: _isUploading ? null : _pickAndUploadPdfs,
                        ),
                      ],
                    ),
                    if (_pdfs.isEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: const Column(
                          children: [
                            Icon(Icons.description_outlined,
                                size: 32, color: AppTheme.textTertiary),
                            SizedBox(height: 6),
                            Text(
                              'No PDFs yet',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      ..._pdfs.asMap().entries.map((entry) {
                        final index = entry.key;
                        final pdf = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf,
                                  size: 18,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pdf['name'] ?? 'PDF',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                onPressed: () => _removePdf(index),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ),
            if (_isUploading) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppTheme.primarySoft, width: 0.5),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Uploading $_uploadingFileName...',
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

  Widget _textInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    int minLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      style: const TextStyle(
        fontSize: 14,
        color: AppTheme.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: AppTheme.textTertiary,
          fontSize: 14,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10, top: 12),
          child: Icon(icon, size: 18, color: AppTheme.textSecondary),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        border: InputBorder.none,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      ),
    );
  }

  Widget _addButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: isDisabled
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3730A3), AppTheme.primary],
                  ),
            color: isDisabled ? Colors.grey.shade300 : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isDisabled
                ? null
                : [
                    BoxShadow(
                      color: const Color(0xFF3730A3).withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}