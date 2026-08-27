import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'cloudinary_config.dart';

class DocumentsSection extends StatefulWidget {
  final String userId;
  final bool editable;

  const DocumentsSection({
    super.key,
    required this.userId,
    this.editable = true,
  });

  @override
  State<DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends State<DocumentsSection> {
  late final CloudinaryPublic _cloudinary;

  // Document definitions: key -> (label, pages)
  static const List<Map<String, dynamic>> _docTypes = [
    {'key': 'passportCi', 'label': 'Passport / CI Photo', 'pages': 1},
    {'key': 'visa', 'label': 'Visa Photo', 'pages': 1},
    {'key': 'workPermitPaper', 'label': 'Work Permit Paper', 'pages': 1},
    {'key': 'workPermitCard', 'label': 'Work Permit Card', 'pages': 2},
    {'key': 'days90Paper', 'label': '90 Days Paper', 'pages': 1},
    {'key': 'tm30', 'label': 'TM30', 'pages': 1},
    {'key': 'pinkCard', 'label': 'Pink Card', 'pages': 2},
  ];

  String? _uploadingKey;

  late final Stream<DocumentSnapshot> _userStream;

  @override
  void initState() {
    super.initState();
    _cloudinary = CloudinaryPublic(
      CloudinaryConfig.cloudName,
      CloudinaryConfig.uploadPreset,
    );
    _userStream = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .snapshots();
  }

  Future<void> _uploadDocument(String docKey, String fieldPath) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _uploadingKey = fieldPath);

    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          file.bytes!,
          identifier: file.name,
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .update({'documents.$fieldPath': response.secureUrl});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document uploaded'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }

    if (mounted) setState(() => _uploadingKey = null);
  }

  Future<void> _deleteDocument(String fieldPath, String label) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Delete $label?'),
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
          .doc(widget.userId)
          .update({'documents.$fieldPath': FieldValue.delete()});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Document deleted'),
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

  void _viewImage(String url, String label) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _userStream,
      builder: (context, snapshot) {
        Map<String, dynamic> documents = {};
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          documents = (data['documents'] as Map<String, dynamic>?) ?? {};
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _docTypes.map((docType) {
            final key = docType['key'] as String;
            final label = docType['label'] as String;
            final pages = docType['pages'] as int;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (pages == 1)
                      _buildSlot(documents, key, label, '')
                    else
                      Row(
                        children: [
                          Expanded(
                            child: _buildSlot(
                                documents, '${key}Front', '$label (Front)',
                                'Front'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildSlot(
                                documents, '${key}Back', '$label (Back)',
                                'Back'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildSlot(
    Map<String, dynamic> documents,
    String fieldPath,
    String fullLabel,
    String slotLabel,
  ) {
    final url = documents[fieldPath] as String?;
    final hasDoc = url != null && url.isNotEmpty;
    final isUploading = _uploadingKey == fieldPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (slotLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              slotLabel,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        Container(
          height: 120,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasDoc ? Colors.green.shade300 : Colors.grey.shade300,
            ),
          ),
          child: isUploading
              ? const Center(child: CircularProgressIndicator())
              : hasDoc
                  ? Stack(
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => _viewImage(url, fullLabel),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => const Center(
                                  child: Icon(Icons.broken_image),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_outlined,
                            color: Colors.grey.shade400,
                            size: 32,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'No document',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
        ),
        if (widget.editable) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isUploading
                      ? null
                      : () => _uploadDocument(fieldPath, fieldPath),
                  icon: Icon(
                    hasDoc ? Icons.refresh : Icons.upload,
                    size: 14,
                  ),
                  label: Text(
                    hasDoc ? 'Replace' : 'Upload',
                    style: const TextStyle(fontSize: 11),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ),
              if (hasDoc) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => _deleteDocument(fieldPath, fullLabel),
                  icon: const Icon(Icons.delete, size: 16),
                  color: Colors.red,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}