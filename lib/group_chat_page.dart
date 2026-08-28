import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'push_notifications.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:url_launcher/url_launcher.dart';
import 'cloudinary_config.dart';
import 'theme.dart';
import 'admin/recycle_bin.dart';
import 'nav_badges.dart';
import 'group_members.dart';

class GroupChatPage extends StatefulWidget {
  const GroupChatPage({
    super.key,
    this.groupId = 'general',
    this.title = 'Group Chat',
    this.subtitle = 'All staff',
    this.lastReadField = 'groupLastReadAt',
  });

  /// Document id under `groups/`.
  final String groupId;

  /// Shown in the app bar.
  final String title;

  /// Shown under the title.
  final String subtitle;

  /// Field on the user profile holding this group's last-read timestamp.
  final String lastReadField;

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  final _messageController = TextEditingController();
  final _messageFocus = FocusNode();
  final _scrollController = ScrollController();
  String _displayName = '';
  String _username = '';
  bool _isAdmin = false;
  bool _isClearing = false;

  static const int _messageWindow = 100;
  DateTime? _lastGroupReadTouch;
  bool _isUploading = false;
  String _uploadStatus = '';

  // Reply state
  Map<String, dynamic>? _replyTo;
  String? _replyToId;

  // Roster + @mention state
  List<GroupMember> _members = [];
  List<GroupMember> _mentionMatches = [];
  int _mentionStart = -1;

  late final CloudinaryPublic _cloudinary;
  late final Stream<QuerySnapshot> _messagesStream;

  @override
  void initState() {
    super.initState();
    _cloudinary = CloudinaryPublic(
      CloudinaryConfig.cloudName,
      CloudinaryConfig.uploadPreset,
    );
    // Only the most recent messages are streamed. Older history stays in
    // Firestore but is not read on every app start.
    _messagesStream = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.groupId)
        .collection('messages')
        .orderBy('sentAt', descending: false)
        .limitToLast(_messageWindow)
        .snapshots();
    _loadUserInfo();
    _loadMembers();
    _messageController.addListener(_onInputChanged);
  }

  Future<void> _loadMembers() async {
    final cached = GroupMembers.cached(widget.groupId);
    if (cached != null && mounted) setState(() => _members = cached);

    final members = await GroupMembers.load(widget.groupId, refresh: true);
    if (mounted) setState(() => _members = members);
  }

  /// Watches the composer for an `@` mention being typed.
  void _onInputChanged() {
    final selection = _messageController.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      _clearMentions();
      return;
    }

    final cursor = selection.baseOffset;
    final before = _messageController.text.substring(0, cursor);

    // `@` must start the message or follow whitespace, and the query itself
    // carries no spaces - so picking a name with spaces ends the lookup.
    final match = RegExp(r'(?:^|\s)@([^\s@]*)$').firstMatch(before);
    if (match == null) {
      _clearMentions();
      return;
    }

    final query = match.group(1) ?? '';
    final matches = _members
        .where((m) => m.username != _username && m.matches(query))
        .take(6)
        .toList();

    if (matches.isEmpty) {
      _clearMentions();
      return;
    }

    setState(() {
      _mentionStart = cursor - query.length - 1;
      _mentionMatches = matches;
    });
  }

  void _clearMentions() {
    if (_mentionMatches.isEmpty && _mentionStart < 0) return;
    setState(() {
      _mentionMatches = [];
      _mentionStart = -1;
    });
  }

  void _insertMention(GroupMember member) {
    if (_mentionStart < 0) return;

    final text = _messageController.text;
    final cursor = _messageController.selection.baseOffset;
    final replacement = '@${member.displayName} ';
    final updated =
        text.replaceRange(_mentionStart, cursor, replacement);

    final caret = _mentionStart + replacement.length;

    _messageController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: caret),
      composing: TextRange.empty,
    );
    _clearMentions();

    // Tapping the list blurs the field on mobile browsers, which drops the
    // keyboard - put focus straight back so typing can continue.
    _messageFocus.requestFocus();

    // Re-focusing makes the browser select the whole field, which would wipe
    // the name on the next keystroke. Put the caret back after the rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _messageController.selection =
          TextSelection.collapsed(offset: caret);
    });
  }

  void _showMembersSheet() {
    if (_members.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.groups,
                          size: 18, color: AppTheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '${_members.length} members',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.border),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _members.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppTheme.border),
                    itemBuilder: (_, i) {
                      final m = _members[i];
                      final initial = m.displayName.isNotEmpty
                          ? m.displayName[0].toUpperCase()
                          : '?';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: m.isAdmin
                              ? AppTheme.primary
                              : AppTheme.primarySurface,
                          child: Text(
                            initial,
                            style: TextStyle(
                              color: m.isAdmin
                                  ? Colors.white
                                  : AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        title: Text(
                          m.displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '@${m.username} - ${m.subtitle}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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
        _isAdmin = role == 'admin';
        final baseName = data['displayName'] ?? username;
        _displayName = role == 'admin' ? '${baseName}_admin' : baseName;
      });
    }

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
        'edited': false,
        'editHistory': [],
      };

      if (imageUrl != null) messageData['imageUrl'] = imageUrl;
      if (fileUrl != null) {
        messageData['fileUrl'] = fileUrl;
        messageData['fileName'] = fileName ?? 'file';
      }

      // Reply data
      if (_replyTo != null && _replyToId != null) {
        final replyText = (_replyTo!['text'] ?? '').toString();
        String replyPreview = replyText;
        if (replyPreview.isEmpty) {
          if (_replyTo!['imageUrl'] != null) {
            replyPreview = '📷 Photo';
          } else if (_replyTo!['fileUrl'] != null) {
            replyPreview = '📎 ${_replyTo!['fileName'] ?? 'File'}';
          }
        }
        messageData['replyTo'] = {
          'messageId': _replyToId,
          'senderName': _replyTo!['senderName'] ?? '',
          'preview': replyPreview.length > 100
              ? '${replyPreview.substring(0, 100)}...'
              : replyPreview,
        };
      }

      final msgRef = await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('messages')
          .add(messageData);

      unawaited(PushNotifications.notify({
        'type': 'group',
        'groupId': widget.groupId,
        'msgId': msgRef.id,
      }));

      setState(() {
        _replyTo = null;
        _replyToId = null;
      });

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

  Future<void> _editMessage(
      String messageId, String oldText, String newText) async {
    if (newText.trim().isEmpty || newText.trim() == oldText) return;
    try {
      final msgRef = FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.groupId)
          .collection('messages')
          .doc(messageId);

      await msgRef.update({
        'text': newText.trim(),
        'edited': true,
        'editHistory': FieldValue.arrayUnion([
          {
            'text': oldText,
            'editedAt': Timestamp.now(),
          }
        ]),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Edit failed: $e')),
        );
      }
    }
  }

  void _showEditDialog(String messageId, String currentText) {
    final controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Edit Message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Edit your message',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _editMessage(messageId, currentText, controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showEditHistory(List<dynamic> history, String currentText) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Icon(Icons.history, size: 18, color: AppTheme.primary),
                SizedBox(width: 8),
                Text(
                  'Edit History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _historyItem('Current', currentText, null, isCurrent: true),
                    ...history.reversed.map((entry) {
                      final map = entry as Map<String, dynamic>;
                      return _historyItem(
                        'Previous',
                        map['text'] ?? '',
                        map['editedAt'] as Timestamp?,
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _historyItem(String label, String text, Timestamp? time,
      {bool isCurrent = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.primarySurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? AppTheme.primarySoft : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.primary
                      : AppTheme.textTertiary,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (time != null)
                Text(
                  _formatTime(time),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  bool _canEdit(Map<String, dynamic> data) {
    if (data['senderId'] != _username) return false;
    if (data['imageUrl'] != null || data['fileUrl'] != null) return false;
    final text = (data['text'] ?? '').toString();
    if (text.isEmpty) return false;
    final sentAt = data['sentAt'] as Timestamp?;
    if (sentAt == null) return false;
    final diff = DateTime.now().difference(sentAt.toDate());
    return diff.inMinutes < 15;
  }

  String _msgLabel(Map<String, dynamic> d) {
    final t = (d['text'] ?? '').toString();
    if (t.isNotEmpty) return t;
    if (d['imageUrl'] != null) return 'Photo';
    if (d['fileUrl'] != null) return (d['fileName'] ?? 'File').toString();
    return 'Message';
  }

  Future<void> _clearAllMessages() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear all messages'),
        content: const Text(
          'ALL messages in the group chat will be removed for everyone and '
          'moved to the Recycle Bin.\n\n'
          'They can be restored within 30 days.',
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
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isClearing = true);

    int deleted = 0;
    try {
      final db = FirebaseFirestore.instance;
      final messages =
          db.collection('groups').doc(widget.groupId).collection('messages');

      final groupId = RecycleBin.newRef().id;

      while (true) {
        final snap = await messages.limit(200).get();
        if (snap.docs.isEmpty) break;
        final writeBatch = db.batch();
        for (final d in snap.docs) {
          final data = d.data();
          writeBatch.set(
            RecycleBin.newRef(),
            RecycleBin.entry(
              type: 'message',
              originalPath: 'groups/general/messages/${d.id}',
              data: data,
              label: _msgLabel(data),
              sublabel: '${widget.title} - ${data['senderName'] ?? '-'}',
              groupId: groupId,
              groupLabel: '${widget.title} - cleared by admin',
            ),
          );
          writeBatch.delete(d.reference);
        }
        await writeBatch.commit();
        deleted += snap.docs.length;
        if (snap.docs.length < 200) break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$deleted message(s) moved to Recycle Bin'),
            backgroundColor: Colors.green,
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

    if (mounted) setState(() => _isClearing = false);
  }

  Future<void> _confirmDeleteMessage(String messageId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete message'),
        content: const Text(
          'This message will be permanently deleted for everyone.',
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
      final ref = db
          .collection('groups')
          .doc(widget.groupId)
          .collection('messages')
          .doc(messageId);
      final snap = await ref.get();
      final data = snap.data() ?? <String, dynamic>{};

      final writeBatch = db.batch();
      writeBatch.set(
        RecycleBin.newRef(),
        RecycleBin.entry(
          type: 'message',
          originalPath: 'groups/general/messages/$messageId',
          data: data,
          label: _msgLabel(data),
          sublabel: '${widget.title} - ${data['senderName'] ?? '-'}',
        ),
      );
      writeBatch.delete(ref);
      await writeBatch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message moved to Recycle Bin'),
            backgroundColor: Colors.green,
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
  }

  void _showMessageOptions(
      String messageId, Map<String, dynamic> data, bool isMe) {
    final canEdit = _canEdit(data);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.reply,
                    color: AppTheme.primary, size: 18),
              ),
              title: const Text('Reply',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _replyTo = data;
                  _replyToId = messageId;
                });
              },
            ),
            if (canEdit)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.edit_outlined,
                      color: AppTheme.primary, size: 18),
                ),
                title: const Text('Edit',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                subtitle: const Text(
                  'Within 15 minutes only',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(messageId, data['text'] ?? '');
                },
              ),
            if (_isAdmin)
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.delete_outline,
                      color: Color(0xFFDC2626), size: 18),
                ),
                title: const Text(
                  'Delete message',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Color(0xFFDC2626),
                  ),
                ),
                subtitle: const Text(
                  'Admin only - permanent',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteMessage(messageId);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
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

  /// Records "the group is read up to now" on the user profile so the
  /// navigation badge does not have to scan the whole message history.
  void _touchGroupRead() {
    final now = DateTime.now();
    if (_lastGroupReadTouch != null &&
        now.difference(_lastGroupReadTouch!).inSeconds < 10) {
      return;
    }
    _lastGroupReadTouch = now;
    NavBadges.markGroupRead(field: widget.lastReadField);
  }

  // ---- older message pagination ----
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _olderDocs = [];
  bool _loadingOlder = false;
  bool _noMoreOlder = false;
  bool _skipAutoScroll = false;

  Future<void> _loadOlder(
      QueryDocumentSnapshot<Map<String, dynamic>>? oldestShown) async {
    if (_loadingOlder || _noMoreOlder || oldestShown == null) return;
    setState(() {
      _loadingOlder = true;
      _skipAutoScroll = true;
    });
    try {
      final snap = await FirebaseFirestore.instance
              .collection('groups')
              .doc(widget.groupId)
              .collection('messages')
          .orderBy('sentAt', descending: true)
          .startAfterDocument(oldestShown)
          .limit(50)
          .get();

      if (snap.docs.isEmpty) {
        _noMoreOlder = true;
      } else {
        _olderDocs.insertAll(0, snap.docs.reversed);
        if (snap.docs.length < 50) _noMoreOlder = true;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    if (mounted) {
      setState(() {
        _loadingOlder = false;
        _skipAutoScroll = true;
      });
    }
  }

  Widget _loadOlderButton(
      QueryDocumentSnapshot<Map<String, dynamic>>? oldestShown) {
    if (_noMoreOlder) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: Center(
          child: Text(
            'Beginning of conversation',
            style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Center(
        child: _loadingOlder
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: () => _loadOlder(oldestShown),
                icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                label: const Text('Load earlier messages',
                    style: TextStyle(fontSize: 12)),
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
          .doc(widget.groupId)
          .collection('messages')
          .doc(messageId)
          .update({
        'readBy': FieldValue.arrayUnion([_username]),
      });
    } catch (_) {}
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
    if (readers == 0) return 'Sent';
    if (readers == 1) return '1 Read';
    return '$readers Read';
  }

  @override
  void dispose() {
    _messageController.removeListener(_onInputChanged);
    _messageController.dispose();
    _messageFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        ),
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white,
              radius: 16,
              child: Icon(Icons.groups, color: AppTheme.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: _members.isEmpty ? null : _showMembersSheet,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    Row(
                      children: [
                        Text(
                          _members.isEmpty
                              ? widget.subtitle
                              : '${_members.length} members',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.normal),
                        ),
                        if (_members.isNotEmpty)
                          const Icon(Icons.chevron_right,
                              size: 14, color: Colors.white70),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_isAdmin)
            _isClearing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  )
                : PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (v) {
                      if (v == 'clear') _clearAllMessages();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'clear',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep_outlined,
                                size: 18, color: Colors.red),
                            SizedBox(width: 10),
                            Text('Clear all messages',
                                style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Be the first to say hi!',
                      style: TextStyle(color: AppTheme.textTertiary),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;

                _touchGroupRead();

                for (final doc in docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final readBy = (data['readBy'] as List<dynamic>?) ?? [];
                  if (data['senderId'] != _username &&
                      !readBy.contains(_username)) {
                    _markAsRead(doc.id, readBy);
                  }
                }

                if (_skipAutoScroll) {
                  _skipAutoScroll = false;
                } else {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) {
                      _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent,
                      );
                    }
                  });
                }

                final liveDocs = docs
                    .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
                final allDocs = [..._olderDocs, ...liveDocs];
                final oldestShown =
                    allDocs.isEmpty ? null : allDocs.first;

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(14),
                  itemCount: allDocs.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) return _loadOlderButton(oldestShown);
                    final doc = allDocs[index - 1];
                    final data = doc.data();
                    final isMe = data['senderId'] == _username;
                    return _buildMessageBubble(doc.id, data, isMe);
                  },
                );
              },
            ),
          ),
          if (_isUploading)
            Container(
              padding: const EdgeInsets.all(10),
              color: AppTheme.primarySurface,
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(_uploadStatus,
                          style: const TextStyle(fontSize: 12))),
                ],
              ),
            ),
          if (_mentionMatches.isNotEmpty) _buildMentionSuggestions(),
          if (_replyTo != null) _buildReplyPreview(),
          _buildMessageInput(),
        ],
      ),
    );
  }

  /// Renders message text with any @mention of a group member emphasised.
  Widget _messageText(String text, bool isMe) {
    final base = TextStyle(
      color: isMe ? Colors.white : AppTheme.textPrimary,
      fontSize: 14,
      height: 1.35,
    );

    if (_members.isEmpty || !text.contains('@')) {
      return Text(text, style: base);
    }

    // Longest names first, so "@Aung Su" never wins over "@Aung Su Su Tun".
    final names = _members.map((m) => m.displayName).toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    final spans = <TextSpan>[];
    var index = 0;

    while (index < text.length) {
      final at = text.indexOf('@', index);
      if (at < 0) {
        spans.add(TextSpan(text: text.substring(index), style: base));
        break;
      }

      if (at > index) {
        spans.add(TextSpan(text: text.substring(index, at), style: base));
      }

      String? hit;
      for (final name in names) {
        if (name.isEmpty) continue;
        if (text.startsWith(name, at + 1)) {
          hit = name;
          break;
        }
      }

      if (hit == null) {
        spans.add(TextSpan(text: '@', style: base));
        index = at + 1;
        continue;
      }

      spans.add(TextSpan(
        text: '@$hit',
        style: base.copyWith(
          fontWeight: FontWeight.w700,
          color: isMe ? Colors.white : AppTheme.primary,
        ),
      ));
      index = at + 1 + hit.length;
    }

    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildMentionSuggestions() {
    return ExcludeFocus(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 220),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: _mentionMatches.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppTheme.border),
          itemBuilder: (_, i) {
            final m = _mentionMatches[i];
            final initial = m.displayName.isNotEmpty
                ? m.displayName[0].toUpperCase()
                : '?';
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primarySurface,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              title: Text(
                m.displayName,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '@${m.username}',
                style: const TextStyle(
                    fontSize: 11.5, color: AppTheme.textSecondary),
              ),
              onTap: () => _insertMention(m),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    final preview = (_replyTo!['text'] ?? '').toString();
    String displayPreview = preview;
    if (displayPreview.isEmpty) {
      if (_replyTo!['imageUrl'] != null) {
        displayPreview = '📷 Photo';
      } else if (_replyTo!['fileUrl'] != null) {
        displayPreview = '📎 ${_replyTo!['fileName'] ?? 'File'}';
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppTheme.primarySurface,
        border: Border(
          top: BorderSide(color: AppTheme.primarySoft, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(width: 3, height: 36, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Replying to ${_replyTo!['senderName'] ?? 'Unknown'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayPreview,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: AppTheme.textSecondary,
            onPressed: () => setState(() {
              _replyTo = null;
              _replyToId = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
      String messageId, Map<String, dynamic> data, bool isMe) {
    final timeStr = _formatTime(data['sentAt'] as Timestamp?);
    final readBy = (data['readBy'] as List<dynamic>?) ?? [];
    final readStatus = isMe ? _formatReadStatus(readBy) : '';
    final text = (data['text'] ?? '').toString();
    final imageUrl = data['imageUrl'] as String?;
    final fileUrl = data['fileUrl'] as String?;
    final fileName = data['fileName'] as String?;
    final replyTo = data['replyTo'] as Map<String, dynamic>?;
    final edited = data['edited'] == true;
    final editHistory = (data['editHistory'] as List<dynamic>?) ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.pinkStart, AppTheme.pinkEnd],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                (data['senderName'] ?? 'U')
                    .toString()
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(
                  color: AppTheme.pinkIcon,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: () =>
                  _showMessageOptions(messageId, data, isMe),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 3),
                      child: Text(
                        data['senderName'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (replyTo != null) _buildReplyChip(replyTo, isMe),
                  if (imageUrl != null)
                    GestureDetector(
                      onTap: () => _showImageViewer(imageUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          imageUrl,
                          width: 220,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              width: 220,
                              height: 150,
                              color: AppTheme.primarySurface,
                              child: const Center(
                                child: CircularProgressIndicator(),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 220,
                              height: 100,
                              color: AppTheme.primarySurface,
                              child: const Icon(Icons.broken_image),
                            );
                          },
                        ),
                      ),
                    ),
                  if (fileUrl != null) ...[
                    if (imageUrl != null) const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _openFile(fileUrl),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        constraints: const BoxConstraints(maxWidth: 250),
                        decoration: BoxDecoration(
                          gradient: isMe
                              ? const LinearGradient(
                                  colors: [
                                    AppTheme.primaryLight,
                                    AppTheme.primary
                                  ],
                                )
                              : null,
                          color: isMe ? null : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: isMe
                              ? null
                              : Border.all(
                                  color: AppTheme.border, width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.insert_drive_file,
                              color: isMe ? Colors.white : AppTheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                fileName ?? 'File',
                                style: TextStyle(
                                  color: isMe
                                      ? Colors.white
                                      : AppTheme.textPrimary,
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.download,
                              size: 14,
                              color: isMe ? Colors.white : AppTheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (text.isNotEmpty) ...[
                    if (imageUrl != null || fileUrl != null)
                      const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: isMe
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppTheme.primaryLight,
                                  AppTheme.primary
                                ],
                              )
                            : null,
                        color: isMe ? null : Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                          bottomRight: Radius.circular(isMe ? 4 : 16),
                        ),
                        border: isMe
                            ? null
                            : Border.all(
                                color: AppTheme.border, width: 0.5),
                        boxShadow: [
                          BoxShadow(
                            color: isMe
                                ? AppTheme.primary.withOpacity(0.15)
                                : Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _messageText(text, isMe),
                    ),
                  ],
                  Padding(
                    padding:
                        const EdgeInsets.only(top: 3, left: 8, right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (timeStr.isNotEmpty)
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        if (edited) ...[
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () =>
                                _showEditHistory(editHistory, text),
                            child: const Text(
                              '· edited',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                        if (isMe && readStatus.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '• $readStatus',
                            style: TextStyle(
                              fontSize: 10,
                              color: readStatus == 'All read'
                                  ? AppTheme.primary
                                  : AppTheme.textTertiary,
                              fontWeight: readStatus == 'All read'
                                  ? FontWeight.w700
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
          ),
        ],
      ),
    );
  }

  Widget _buildReplyChip(Map<String, dynamic> replyTo, bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      constraints: const BoxConstraints(maxWidth: 260),
      decoration: BoxDecoration(
        color: isMe
            ? AppTheme.primary.withOpacity(0.15)
            : AppTheme.primarySurface,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(color: AppTheme.primary, width: 3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            replyTo['senderName'] ?? 'Unknown',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            replyTo['preview'] ?? '',
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image_outlined,
                  color: AppTheme.primary, size: 22),
              onPressed: _isUploading ? null : _pickAndSendImage,
            ),
            IconButton(
              icon: const Icon(Icons.attach_file,
                  color: AppTheme.primary, size: 22),
              onPressed: _isUploading ? null : _pickAndSendFile,
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                focusNode: _messageFocus,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppTheme.background,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _sendTextMessage(),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primaryLight, AppTheme.primary],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _sendTextMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}