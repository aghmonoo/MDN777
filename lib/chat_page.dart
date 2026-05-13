import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'group_chat_page.dart';
import 'private_chat_page.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

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

    if (difference == 0) return '$hour:$minute $amPm';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final username = user?.email?.split('@').first ?? '';

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final adminDocs = snapshot.data?.docs ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildGroupChatCard(context, username),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                'Private Chat',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            ...adminDocs.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final adminUsername = data['username'] ?? '';
              final adminName = data['displayName'] ?? 'Admin';

              final ids = [username, adminUsername]..sort();
              final chatId = ids.join('_');

              return _PrivateChatTile(
                chatId: chatId,
                username: username,
                adminUsername: adminUsername,
                adminName: adminName,
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildGroupChatCard(BuildContext context, String username) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groups')
          .doc('general')
          .collection('messages')
          .orderBy('sentAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.deepPurple,
                child: Icon(Icons.groups, color: Colors.white),
              ),
              title: const Text('Group Chat',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('All staff conversation'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const GroupChatPage(),
                  ),
                );
              },
            ),
          );
        }

        final docs = snapshot.data!.docs;

        String lastMessage = 'All staff conversation';
        String lastSender = '';
        String lastSenderId = '';
        Timestamp? lastTime;
        int unreadCount = 0;

        if (docs.isNotEmpty) {
          final lastDoc = docs.first.data() as Map<String, dynamic>;
          final text = (lastDoc['text'] ?? '').toString();
          final imageUrl = lastDoc['imageUrl'];
          final fileUrl = lastDoc['fileUrl'];

          if (text.isNotEmpty) {
            lastMessage = text;
          } else if (imageUrl != null) {
            lastMessage = '📷 Photo';
          } else if (fileUrl != null) {
            lastMessage = '📎 ${lastDoc['fileName'] ?? 'File'}';
          }

          lastSender = lastDoc['senderName'] ?? '';
          lastSenderId = lastDoc['senderId'] ?? '';
          lastTime = lastDoc['sentAt'] as Timestamp?;

          for (final doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final senderId = data['senderId'] ?? '';
            final readBy = (data['readBy'] as List<dynamic>?) ?? [];
            if (senderId != username && !readBy.contains(username)) {
              unreadCount++;
            }
          }
        }

        final isUnread = unreadCount > 0;

        String previewText = lastMessage;
        if (lastSender.isNotEmpty && docs.isNotEmpty) {
          if (lastSenderId == username) {
            previewText = 'You: $lastMessage';
          } else {
            previewText = '$lastSender: $lastMessage';
          }
        }

        return Card(
          elevation: isUnread ? 3 : 1,
          color: isUnread ? Colors.deepPurple.shade50 : null,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.deepPurple,
              child: Icon(Icons.groups, color: Colors.white),
            ),
            title: Text(
              'Group Chat',
              style: TextStyle(
                fontWeight: isUnread ? FontWeight.bold : FontWeight.w500,
                color: isUnread ? Colors.black : Colors.grey.shade800,
              ),
            ),
            subtitle: Text(
              previewText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isUnread ? Colors.black : Colors.grey.shade500,
                fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatTime(lastTime),
                  style: TextStyle(
                    fontSize: 11,
                    color: isUnread ? Colors.deepPurple : Colors.grey.shade600,
                    fontWeight:
                        isUnread ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                if (isUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const GroupChatPage(),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PrivateChatTile extends StatefulWidget {
  final String chatId;
  final String username;
  final String adminUsername;
  final String adminName;

  const _PrivateChatTile({
    required this.chatId,
    required this.username,
    required this.adminUsername,
    required this.adminName,
  });

  @override
  State<_PrivateChatTile> createState() => _PrivateChatTileState();
}

class _PrivateChatTileState extends State<_PrivateChatTile> {
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

    if (difference == 0) return '$hour:$minute $amPm';
    if (difference == 1) return 'Yesterday';
    if (difference < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, unreadSnap) {
        int? unreadCountRaw;
        if (unreadSnap.hasData) {
          unreadCountRaw = unreadSnap.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['senderId'] != widget.username;
          }).length;
        }
        final unreadCount = unreadCountRaw ?? 0;
        final bool isUnread = unreadCountRaw != null && unreadCountRaw > 0;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .snapshots(),
          builder: (context, chatSnap) {
            final chatData = chatSnap.data?.data() as Map<String, dynamic>?;

            String previewText = chatData?['lastMessage'] ?? 'Admin';
            final lastSenderId = chatData?['lastSenderId'];
            if (lastSenderId == widget.username &&
                previewText.isNotEmpty &&
                previewText != 'Admin') {
              previewText = 'You: $previewText';
            }

            return Card(
              elevation: isUnread ? 3 : 1,
              color: isUnread ? Colors.deepPurple.shade50 : null,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.deepPurple.shade300,
                  child: Text(
                    widget.adminName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(
                  widget.adminName,
                  style: TextStyle(
                    fontWeight:
                        isUnread ? FontWeight.bold : FontWeight.w500,
                    color: isUnread ? Colors.black : Colors.grey.shade800,
                  ),
                ),
                subtitle: Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isUnread ? Colors.black : Colors.grey.shade500,
                    fontWeight:
                        isUnread ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (chatData?['lastMessageAt'] != null)
                      Text(
                        _formatTime(
                            chatData!['lastMessageAt'] as Timestamp?),
                        style: TextStyle(
                          fontSize: 11,
                          color: isUnread
                              ? Colors.deepPurple
                              : Colors.grey.shade600,
                          fontWeight: isUnread
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    const SizedBox(height: 4),
                    if (isUnread)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PrivateChatPage(
                        chatId: widget.chatId,
                        otherUsername: widget.adminUsername,
                        otherDisplayName: widget.adminName,
                      ),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}