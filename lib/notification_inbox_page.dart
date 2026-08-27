import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
import 'announcement_detail_page.dart';
import 'group_chat_page.dart';
import 'private_chat_page.dart';

class NotifItem {
  final String type;
  final String id;
  final String title;
  final String subtitle;
  final Timestamp? timestamp;
  final String? chatId;

  NotifItem({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    this.chatId,
  });
}

class NotificationInboxPage extends StatefulWidget {
  const NotificationInboxPage({super.key});

  @override
  State<NotificationInboxPage> createState() =>
      _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage> {
  String get _username =>
      FirebaseAuth.instance.currentUser?.email?.split('@').first ?? '';

  String _timeAgo(Timestamp? ts) {
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final dt = ts.toDate();
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Future<List<NotifItem>> _loadAll() async {
    final items = <NotifItem>[];

    try {
      final annSnap = await FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();
      for (final doc in annSnap.docs) {
        final data = doc.data();
        final readBy = (data['readBy'] as List?) ?? [];
        if (readBy.contains(_username)) continue;
        items.add(NotifItem(
          type: 'announcement',
          id: doc.id,
          title: data['title'] ?? 'New announcement',
          subtitle: data['createdBy'] ?? 'Unknown',
          timestamp: data['createdAt'] as Timestamp?,
        ));
      }
    } catch (_) {}

    try {
      final grpSnap = await FirebaseFirestore.instance
          .collection('groups')
          .doc('general')
          .collection('messages')
          .orderBy('sentAt', descending: true)
          .limit(50)
          .get();
      for (final doc in grpSnap.docs) {
        final data = doc.data();
        final senderId = data['senderId'] ?? '';
        if (senderId == _username) continue;
        final readBy = (data['readBy'] as List?) ?? [];
        if (readBy.contains(_username)) continue;

        final text = (data['text'] ?? '').toString();
        String preview = text;
        if (preview.isEmpty) {
          if (data['imageUrl'] != null) {
            preview = 'Photo';
          } else if (data['fileUrl'] != null) {
            preview = data['fileName'] ?? 'File';
          }
        }

        items.add(NotifItem(
          type: 'group_chat',
          id: doc.id,
          title: data['senderName'] ?? 'Unknown',
          subtitle: preview,
          timestamp: data['sentAt'] as Timestamp?,
        ));
      }
    } catch (_) {}

    try {
      final chatsSnap = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: _username)
          .get();
      for (final chatDoc in chatsSnap.docs) {
        final msgsSnap = await chatDoc.reference
            .collection('messages')
            .where('isRead', isEqualTo: false)
            .get();
        for (final doc in msgsSnap.docs) {
          final data = doc.data();
          final senderId = data['senderId'] ?? '';
          if (senderId == _username) continue;

          final text = (data['text'] ?? '').toString();
          String preview = text;
          if (preview.isEmpty) {
            if (data['imageUrl'] != null) {
              preview = 'Photo';
            } else if (data['fileUrl'] != null) {
              preview = data['fileName'] ?? 'File';
            }
          }

          items.add(NotifItem(
            type: 'private_chat',
            id: doc.id,
            title: data['senderName'] ?? 'Unknown',
            subtitle: preview,
            timestamp: data['sentAt'] as Timestamp?,
            chatId: chatDoc.id,
          ));
        }
      }
    } catch (_) {}

    items.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.heroGradient),
        ),
        title: const Text('Notifications'),
      ),
      body: FutureBuilder<List<NotifItem>>(
        future: _loadAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) return _emptyState();

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: items.length,
              itemBuilder: (context, index) => _buildItem(items[index]),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
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
            child: const Icon(
              Icons.notifications_none,
              size: 44,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'You are all caught up',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'No new notifications',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(NotifItem item) {
    final isAnn = item.type == 'announcement';
    final isGroup = item.type == 'group_chat';
    final iconData = isAnn
        ? Icons.campaign
        : isGroup
            ? Icons.groups
            : Icons.chat_bubble;
    final typeLabel = isAnn
        ? 'ANNOUNCEMENT'
        : isGroup
            ? 'GROUP CHAT'
            : 'DIRECT MESSAGE';
    final List<Color> gradColors = isAnn
        ? [AppTheme.amberStart, AppTheme.amberEnd]
        : isGroup
            ? [AppTheme.primaryLight, AppTheme.primary]
            : [AppTheme.pinkStart, AppTheme.pinkEnd];
    final iconColor = isAnn
        ? AppTheme.amberIcon
        : isGroup
            ? Colors.white
            : AppTheme.pinkIcon;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, AppTheme.primarySurface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primarySoft, width: 0.8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _navigate(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradColors,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(iconData, size: 22, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primarySurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              typeLabel,
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _timeAgo(item.timestamp),
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(NotifItem item) {
    if (item.type == 'announcement') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AnnouncementDetailPage(announcementId: item.id),
        ),
      );
    } else if (item.type == 'group_chat') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GroupChatPage()),
      );
    } else if (item.type == 'private_chat' && item.chatId != null) {
      _openPrivateChat(item.chatId!, item.title);
    }
  }

  Future<void> _openPrivateChat(String chatId, String senderName) async {
    final parts = chatId.split('_');
    final other = parts.firstWhere((p) => p != _username, orElse: () => '');
    if (other.isEmpty) return;

    String displayName = senderName;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: other)
          .where('role', isEqualTo: 'admin')
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        displayName = snap.docs.first.data()['displayName'] ?? senderName;
      }
    } catch (_) {}

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateChatPage(
          chatId: chatId,
          otherUsername: other,
          otherDisplayName: displayName,
        ),
      ),
    );
  }
}