import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
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
      builder: (ctx) => _NewChatDialog(adminUsername: adminUsername),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final adminUsername = user?.email?.split('@').first ?? '';

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
        title: const Text('Chats'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          _sectionLabel('GROUP'),
          const SizedBox(height: 8),
          _buildGroupChatCard(context, adminUsername),
          const SizedBox(height: 20),
          _sectionLabel('DIRECT MESSAGES'),
          const SizedBox(height: 8),
          _buildPrivateChatsList(context, adminUsername),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF3730A3),
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.chat_outlined),
        label: const Text('New Chat',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () => _showNewChatDialog(context, adminUsername),
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
        String lastMessage = 'All staff conversation';
        String lastSender = '';
        String lastSenderId = '';
        Timestamp? lastTime;
        int unreadCount = 0;

        if (snapshot.hasData) {
          final docs = snapshot.data!.docs;
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
        }

        final isUnread = unreadCount > 0;

        String previewText = lastMessage;
        if (lastSender.isNotEmpty && lastTime != null) {
          if (lastSenderId == adminUsername) {
            previewText = 'You: $lastMessage';
          } else {
            previewText = '$lastSender: $lastMessage';
          }
        }

        return Container(
          decoration: BoxDecoration(
            gradient: isUnread
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, AppTheme.primarySurface],
                  )
                : null,
            color: isUnread ? null : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnread ? AppTheme.primarySoft : AppTheme.border,
              width: isUnread ? 0.8 : 0.5,
            ),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GroupChatPage()),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AppTheme.primaryLight, AppTheme.primary],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.25),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.groups,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Group Chat',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isUnread
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontWeight: isUnread
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(lastTime),
                          style: TextStyle(
                            fontSize: 10,
                            color: isUnread
                                ? AppTheme.primary
                                : AppTheme.textTertiary,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (isUnread)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border, width: 0.5),
            ),
            child: const Column(
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 36, color: AppTheme.textTertiary),
                SizedBox(height: 8),
                Text(
                  'No direct messages yet',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap + to start a new chat',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
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
        int unreadCount = 0;
        if (unreadSnap.hasData) {
          unreadCount = unreadSnap.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['senderId'] != widget.adminUsername;
          }).length;
        }
        final isUnread = unreadCount > 0;

        String previewText = widget.chatData['lastMessage'] ?? '';
        final lastSenderId = widget.chatData['lastSenderId'];
        if (lastSenderId == widget.adminUsername && previewText.isNotEmpty) {
          previewText = 'You: $previewText';
        }

        final initial = _displayName.isNotEmpty
            ? _displayName.substring(0, 1).toUpperCase()
            : '?';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            gradient: isUnread
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, AppTheme.primarySurface],
                  )
                : null,
            color: isUnread ? null : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnread ? AppTheme.primarySoft : AppTheme.border,
              width: isUnread ? 0.8 : 0.5,
            ),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PrivateChatPage(
                    chatId: widget.chatId,
                    otherUsername: widget.otherUsername,
                    otherDisplayName: _displayName,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppTheme.pinkStart, AppTheme.pinkEnd],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: AppTheme.pinkIcon,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isUnread
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontWeight: isUnread
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatTime(
                              widget.chatData['lastMessageAt'] as Timestamp?),
                          style: TextStyle(
                            fontSize: 10,
                            color: isUnread
                                ? AppTheme.primary
                                : AppTheme.textTertiary,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (isUnread)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else
                          const SizedBox(height: 18),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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

  void _startChat(
      BuildContext context, String otherUsername, String otherDisplayName) {
    final ids = [widget.adminUsername, otherUsername]..sort();
    final chatId = ids.join('_');

    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateChatPage(
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3730A3), AppTheme.primary],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chat_outlined,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Start New Chat',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Search staff...',
                  hintStyle: TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 13,
                  ),
                  prefixIcon: Icon(Icons.search,
                      size: 20, color: AppTheme.textSecondary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value.toLowerCase());
                },
              ),
            ),
            const SizedBox(height: 14),
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
                    return const Center(
                      child: Text('No users found',
                          style: TextStyle(color: AppTheme.textTertiary)),
                    );
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
                      final initial = displayName.isNotEmpty
                          ? displayName.substring(0, 1).toUpperCase()
                          : '?';

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () =>
                              _startChat(context, username, displayName),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isAdmin
                                          ? const [
                                              Color(0xFF1E3A8A),
                                              Color(0xFF3730A3)
                                            ]
                                          : [
                                              AppTheme.pinkStart,
                                              AppTheme.pinkEnd
                                            ],
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    initial,
                                    style: TextStyle(
                                      color: isAdmin
                                          ? Colors.white
                                          : AppTheme.pinkIcon,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              displayName,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: AppTheme.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isAdmin) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 1,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF3730A3)
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(5),
                                              ),
                                              child: const Text(
                                                'ADMIN',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFF3730A3),
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '@$username${isAdmin ? '' : ' · ${data['department'] ?? '-'}'}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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