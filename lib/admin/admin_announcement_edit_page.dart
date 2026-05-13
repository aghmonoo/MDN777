import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import '../cloudinary_config.dart';

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
        _imageUrls = (data['imageUrls'] as List<dynamic>?)?.cast<String>() ?? [];
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

  void _removeImage(int index) {
    setState(() {
      _imageUrls.removeAt(index);
    });
  }

  void _removePdf(int index) {
    setState(() {
      _pdfs.removeAt(index);
    });
  }

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
        await FirebaseFirestore.instance.collection('announcements').add(data);
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
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
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
            TextButton(
              onPressed: _save,
              child: const Text(
                'SAVE',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bodyController,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: 'Body',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            // Photos Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Photos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isUploading ? null : _pickAndUploadImages,
                  icon: const Icon(Icons.add_photo_alternate, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_imageUrls.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No photos added',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _imageUrls.length,
                itemBuilder: (context, index) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
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
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 24),
            // PDFs Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PDF Attachments',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                TextButton.icon(
                  onPressed: _isUploading ? null : _pickAndUploadPdfs,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
            if (_pdfs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'No PDFs added',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ..._pdfs.asMap().entries.map((entry) {
                final index = entry.key;
                final pdf = entry.value;
                return Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.picture_as_pdf,
                        color: Colors.red.shade700,
                      ),
                    ),
                    title: Text(pdf['name'] ?? 'PDF'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _removePdf(index),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),
            if (_isUploading)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Uploading $_uploadingFileName...',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}