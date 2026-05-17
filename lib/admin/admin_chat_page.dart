import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../group_chat_page.dart';
import '../private_chat_page.dart';

class AdminChatPage extends StatelessWidget {
  const AdminChatPage({super.key});

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

  void _showNewChatDialog(BuildContext context, String adminUsername) {
    showDialog(
      context: context,
      builder: (context) => _NewChatDialog(adminUsername: adminUsername),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final adminUsername = user?.email?.split('@').first ?? '';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        title: const Text('Chats'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildGroupChatCard(context, adminUsername),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              'Private Chats',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          _buildPrivateChatsList(context, adminUsername),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.chat),
        label: const Text('New Chat'),
        onPressed: () => _showNewChatDialog(context, adminUsername),
      ),
    );
  }

  Widget _buildGroupChatCard(BuildContext context, String adminUsername) {
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
            elevation: 2,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.indigo,
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
            if (senderId != adminUsername && !readBy.contains(adminUsername)) {
              unreadCount++;
            }
          }
        }

        final isUnread = unreadCount > 0;

        String previewText = lastMessage;
        if (lastSender.isNotEmpty && docs.isNotEmpty) {
          if (lastSenderId == adminUsername) {
            previewText = 'You: $lastMessage';
          } else {
            previewText = '$lastSender: $lastMessage';
          }
        }

        return Card(
          elevation: isUnread ? 3 : 2,
          color: isUnread ? Colors.indigo.shade50 : null,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.indigo,
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
                    color: isUnread ? Colors.indigo : Colors.grey.shade600,
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

  Widget _buildPrivateChatsList(BuildContext context, String adminUsername) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: adminUsername)
          .orderBy('lastMessageAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Error: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: Text(
                'No private chats yet.\nTap + to start a new chat.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final chats = snapshot.data!.docs;
        return Column(
          children: chats.map((chatDoc) {
            final chatData = chatDoc.data() as Map<String, dynamic>;
            final participants =
                (chatData['participants'] as List<dynamic>?)
                        ?.cast<String>() ??
                    [];
            final otherUsername = participants.firstWhere(
              (p) => p != adminUsername,
              orElse: () => '',
            );

            if (otherUsername.isEmpty) return const SizedBox.shrink();

            return _PrivateChatTile(
              chatId: chatDoc.id,
              chatData: chatData,
              otherUsername: otherUsername,
              adminUsername: adminUsername,
            );
          }).toList(),
        );
      },
    );
  }
}

class _PrivateChatTile extends StatefulWidget {
  final String chatId;
  final Map<String, dynamic> chatData;
  final String otherUsername;
  final String adminUsername;

  const _PrivateChatTile({
    required this.chatId,
    required this.chatData,
    required this.otherUsername,
    required this.adminUsername,
  });

  @override
  State<_PrivateChatTile> createState() => _PrivateChatTileState();
}

class _PrivateChatTileState extends State<_PrivateChatTile> {
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _displayName = widget.otherUsername;
    _loadDisplayName();
  }

  Future<void> _loadDisplayName() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: widget.otherUsername)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        if (mounted) {
          setState(() {
            _displayName = data['displayName'] ?? widget.otherUsername;
          });
        }
      }
    } catch (e) {
      // Keep username as fallback
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
            return data['senderId'] != widget.adminUsername;
          }).length;
        }
        final unreadCount = unreadCountRaw ?? 0;
        final bool isUnread = unreadCountRaw != null && unreadCountRaw > 0;

        String previewText = widget.chatData['lastMessage'] ?? '';
        final lastSenderId = widget.chatData['lastSenderId'];
        if (lastSenderId == widget.adminUsername && previewText.isNotEmpty) {
          previewText = 'You: $previewText';
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: isUnread ? 3 : 1,
          color: isUnread ? Colors.indigo.shade50 : null,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple,
              child: Text(
                _displayName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              _displayName,
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
                Text(
                  _formatTime(widget.chatData['lastMessageAt'] as Timestamp?),
                  style: TextStyle(
                    fontSize: 11,
                    color: isUnread ? Colors.indigo : Colors.grey.shade600,
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
                  builder: (context) => PrivateChatPage(
                    chatId: widget.chatId,
                    otherUsername: widget.otherUsername,
                    otherDisplayName: _displayName,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _NewChatDialog extends StatefulWidget {
  final String adminUsername;

  const _NewChatDialog({required this.adminUsername});

  @override
  State<_NewChatDialog> createState() => _NewChatDialogState();
}

class _NewChatDialogState extends State<_NewChatDialog> {
  String _searchQuery = '';

  void _startChat(BuildContext context, String otherUsername,
      String otherDisplayName) {
    final ids = [widget.adminUsername, otherUsername]..sort();
    final chatId = ids.join('_');

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PrivateChatPage(
          chatId: chatId,
          otherUsername: otherUsername,
          otherDisplayName: otherDisplayName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Start New Chat',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'Search staff...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value.toLowerCase());
              },
            ),
            const SizedBox(height: 16),
            Flexible(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: Text('No users'));
                  }

                  final users = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final username = data['username']?.toString() ?? '';
                    final displayName =
                        (data['displayName'] ?? '').toString().toLowerCase();

                    if (username == widget.adminUsername) return false;

                    if (_searchQuery.isNotEmpty) {
                      if (!displayName.contains(_searchQuery) &&
                          !username.toLowerCase().contains(_searchQuery)) {
                        return false;
                      }
                    }

                    return true;
                  }).toList();

                  users.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aName = (aData['displayName'] ?? '').toString();
                    final bName = (bData['displayName'] ?? '').toString();
                    return aName.compareTo(bName);
                  });

                  if (users.isEmpty) {
                    return const Center(child: Text('No users found'));
                  }

                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final data =
                          users[index].data() as Map<String, dynamic>;
                      final username = data['username']?.toString() ?? '';
                      final displayName =
                          data['displayName']?.toString() ?? username;
                      final isAdmin = data['role'] == 'admin';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isAdmin ? Colors.indigo : Colors.deepPurple,
                          child: Text(
                            displayName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(displayName),
                        subtitle: Text(
                          '@$username${isAdmin ? ' • ADMIN' : ' • ${data['department'] ?? '-'}'}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () =>
                            _startChat(context, username, displayName),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}