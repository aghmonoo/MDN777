import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cloudinary_config.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String _displayName = '';
  String _username = '';
  int _totalStaffCount = 0;
  bool _isUploading = false;
  String _uploadStatus = '';

  late final CloudinaryPublic _cloudinary;

  @override
  void initState() {
    super.initState();
    _cloudinary = CloudinaryPublic(
      CloudinaryConfig.cloudName,
      CloudinaryConfig.uploadPreset,
    );
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    final username = user?.email?.split('@').first ?? '';

    final userSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();

    if (userSnapshot.docs.isNotEmpty) {
      final data = userSnapshot.docs.first.data();
      setState(() {
        _username = username;
        final role = data['role'] ?? 'employee';
final baseName = data['displayName'] ?? username;
_displayName = role == 'admin' ? '${baseName}_admin' : baseName;
      });
    }

    final allUsersSnapshot =
        await FirebaseFirestore.instance.collection('users').get();
    setState(() {
      _totalStaffCount = allUsersSnapshot.docs.length;
    });
  }

  Future<void> _sendMessage({
    String? text,
    String? imageUrl,
    String? fileUrl,
    String? fileName,
  }) async {
    if (_username.isEmpty) return;
    if ((text?.isEmpty ?? true) && imageUrl == null && fileUrl == null) return;

    try {
      final messageData = <String, dynamic>{
        'senderId': _username,
        'senderName': _displayName,
        'text': text ?? '',
        'sentAt': FieldValue.serverTimestamp(),
        'readBy': [_username],
      };

      if (imageUrl != null) messageData['imageUrl'] = imageUrl;
      if (fileUrl != null) {
        messageData['fileUrl'] = fileUrl;
        messageData['fileName'] = fileName ?? 'file';
      }

      await FirebaseFirestore.instance
          .collection('groups')
          .doc('general')
          .collection('messages')
          .add(messageData);

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await _sendMessage(text: text);
  }

  Future<void> _pickAndSendImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading ${file.name}...';
    });

    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          file.bytes!,
          identifier: file.name,
          resourceType: CloudinaryResourceType.Image,
        ),
      );

      await _sendMessage(imageUrl: response.secureUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() {
      _isUploading = true;
      _uploadStatus = 'Uploading ${file.name}...';
    });

    try {
      final response = await _cloudinary.uploadFile(
        CloudinaryFile.fromBytesData(
          file.bytes!,
          identifier: file.name,
          resourceType: CloudinaryResourceType.Raw,
        ),
      );

      await _sendMessage(fileUrl: response.secureUrl, fileName: file.name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadStatus = '';
      });
    }
  }

  Future<void> _openFile(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showImageViewer(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(8),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(
                child: Image.network(imageUrl, fit: BoxFit.contain),
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

  Future<void> _markAsRead(String messageId, List<dynamic> readBy) async {
    if (_username.isEmpty) return;
    if (readBy.contains(_username)) return;

    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc('general')
          .collection('messages')
          .doc(messageId)
          .update({
        'readBy': FieldValue.arrayUnion([_username]),
      });
    } catch (e) {
      // Silent fail
    }
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(dt.year, dt.month, dt.day);
    final difference = today.difference(messageDay).inDays;

    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$hour:$minute $amPm';

    if (difference == 0) return timeStr;
    if (difference == 1) return 'Yesterday, $timeStr';
    if (difference < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${weekdays[dt.weekday - 1]}, $timeStr';
    }
    return '${dt.day}/${dt.month}/${dt.year}, $timeStr';
  }

  String _formatReadStatus(List<dynamic> readBy) {
    final readers = readBy.where((u) => u != _username).length;
    final possibleReaders = _totalStaffCount - 1;

    if (possibleReaders <= 0) return '';
    if (readers == 0) return 'Sent';
    if (readers >= possibleReaders) return 'All read';
    return '$readers Read';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white,
              radius: 16,
              child: Icon(Icons.groups, color: Colors.deepPurple, size: 20),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Group Chat', style: TextStyle(fontSize: 16)),
                Text(
                  'All staff',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('groups')
                  .doc('general')
                  .collection('messages')
                  .orderBy('sentAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Be the first to say hi!',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final readBy = (data['readBy'] as List<dynamic>?) ?? [];
                  if (data['senderId'] != _username &&
                      !readBy.contains(_username)) {
                    _markAsRead(doc.id, readBy);
                  }
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == _username;
                    return _buildMessageBubble(data, isMe);
                  },
                );
              },
            ),
          ),
          if (_isUploading)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_uploadStatus)),
                ],
              ),
            ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> data, bool isMe) {
    final timeStr = _formatTime(data['sentAt'] as Timestamp?);
    final readBy = (data['readBy'] as List<dynamic>?) ?? [];
    final readStatus = isMe ? _formatReadStatus(readBy) : '';
    final text = (data['text'] ?? '').toString();
    final imageUrl = data['imageUrl'] as String?;
    final fileUrl = data['fileUrl'] as String?;
    final fileName = data['fileName'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.deepPurple.shade300,
              child: Text(
                (data['senderName'] ?? 'U')
                    .toString()
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Text(
                      data['senderName'] ?? 'Unknown',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                // Image
                if (imageUrl != null)
                  GestureDetector(
                    onTap: () => _showImageViewer(imageUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        imageUrl,
                        width: 220,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            width: 220,
                            height: 150,
                            color: Colors.grey.shade200,
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 220,
                            height: 100,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image),
                          );
                        },
                      ),
                    ),
                  ),
                // File
                if (fileUrl != null) ...[
                  if (imageUrl != null) const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _openFile(fileUrl),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxWidth: 250),
                      decoration: BoxDecoration(
                        color: isMe
                            ? Colors.deepPurple.shade400
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.insert_drive_file,
                            color: isMe ? Colors.white : Colors.deepPurple,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              fileName ?? 'File',
                              style: TextStyle(
                                color: isMe ? Colors.white : Colors.black87,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.download,
                            size: 16,
                            color: isMe ? Colors.white : Colors.deepPurple,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                // Text
                if (text.isNotEmpty) ...[
                  if (imageUrl != null || fileUrl != null)
                    const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.deepPurple : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        color: isMe ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 8, right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      if (isMe && readStatus.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '• $readStatus',
                          style: TextStyle(
                            fontSize: 10,
                            color: readStatus == 'All read'
                                ? Colors.deepPurple
                                : Colors.grey.shade600,
                            fontWeight: readStatus == 'All read'
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.image, color: Colors.deepPurple),
            onPressed: _isUploading ? null : _pickAndSendImage,
            tooltip: 'Send photo',
          ),
          IconButton(
            icon: const Icon(Icons.attach_file, color: Colors.deepPurple),
            onPressed: _isUploading ? null : _pickAndSendFile,
            tooltip: 'Send file',
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              onSubmitted: (_) => _sendTextMessage(),
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.deepPurple,
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendTextMessage,
            ),
          ),
        ],
      ),
    );
  }
}