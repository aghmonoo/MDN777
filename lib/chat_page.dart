import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _sectionLabel('Group'),
            _buildGroupChatCard(context, username),
            const SizedBox(height: 20),
            _sectionLabel('Direct Messages'),
            if (adminDocs.isEmpty)
              _emptyState('No admins available')
            else
              ...adminDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final adminUsername = data['username'] ?? '';
                final adminName = data['displayName'] ?? 'Admin';

                final ids = [username, adminUsername]..sort();
                final chatId = ids.join('_');

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PrivateChatTile(
                    chatId: chatId,
                    username: username,
                    adminUsername: adminUsername,
                    adminName: adminName,
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }

  Widget _emptyState(String text) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border, width: 0.5),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 13,
          ),
        ),
      ),
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
              if (senderId != username && !readBy.contains(username)) {
                unreadCount++;
              }
            }
          }
        }

        final isUnread = unreadCount > 0;

        String previewText = lastMessage;
        if (lastSender.isNotEmpty) {
          if (lastSenderId == username) {
            previewText = 'You: $lastMessage';
          } else {
            previewText = '$lastSender: $lastMessage';
          }
        }

        return _chatTile(
          context: context,
          isGroup: true,
          isUnread: isUnread,
          unreadCount: unreadCount,
          title: 'Group Chat',
          subtitle: previewText,
          time: _formatTime(lastTime),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GroupChatPage()),
          ),
        );
      },
    );
  }

  Widget _chatTile({
    required BuildContext context,
    required bool isGroup,
    required bool isUnread,
    required int unreadCount,
    required String title,
    required String subtitle,
    required String time,
    required VoidCallback onTap,
    String? initial,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
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
              width: isUnread ? 1 : 0.5,
            ),
            boxShadow: isUnread
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withOpacity(0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : AppTheme.cardShadow,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: isGroup
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryLight,
                            AppTheme.primary,
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.pinkStart,
                            AppTheme.pinkEnd,
                          ],
                        ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: (isGroup
                              ? AppTheme.primary
                              : AppTheme.pinkIcon)
                          .withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: isGroup
                    ? const Icon(Icons.groups,
                        color: Colors.white, size: 26)
                    : Text(
                        (initial ?? '?'),
                        style: TextStyle(
                          color: AppTheme.pinkIcon,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (time.isNotEmpty)
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 11,
                              color: isUnread
                                  ? AppTheme.primary
                                  : AppTheme.textTertiary,
                              fontWeight: isUnread
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isUnread
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontWeight: isUnread
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isUnread && unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEF4444)
                                      .withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
        int unreadCount = 0;
        if (unreadSnap.hasData) {
          unreadCount = unreadSnap.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['senderId'] != widget.username;
          }).length;
        }
        final bool isUnread = unreadCount > 0;

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .get(),
          builder: (context, chatSnap) {
            final chatData =
                chatSnap.data?.data() as Map<String, dynamic>?;

            String previewText = chatData?['lastMessage'] ?? 'Tap to chat';
            final lastSenderId = chatData?['lastSenderId'];
            if (lastSenderId == widget.username &&
                previewText.isNotEmpty &&
                previewText != 'Tap to chat') {
              previewText = 'You: $previewText';
            }

            final time =
                _formatTime(chatData?['lastMessageAt'] as Timestamp?);
            final initial =
                widget.adminName.substring(0, 1).toUpperCase();

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrivateChatPage(
                      chatId: widget.chatId,
                      otherUsername: widget.adminUsername,
                      otherDisplayName: widget.adminName,
                    ),
                  ),
                ),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
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
                      color:
                          isUnread ? AppTheme.primarySoft : AppTheme.border,
                      width: isUnread ? 1 : 0.5,
                    ),
                    boxShadow: isUnread
                        ? [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.06),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : AppTheme.cardShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.pinkStart,
                              AppTheme.pinkEnd,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.pinkIcon.withOpacity(0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: AppTheme.pinkIcon,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.adminName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isUnread
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (time.isNotEmpty)
                                  Text(
                                    time,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isUnread
                                          ? AppTheme.primary
                                          : AppTheme.textTertiary,
                                      fontWeight: isUnread
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    previewText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isUnread
                                          ? AppTheme.textPrimary
                                          : AppTheme.textSecondary,
                                      fontWeight: isUnread
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isUnread) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFEF4444)
                                              .withOpacity(0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      unreadCount > 9 ? '9+' : '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
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
    );
  }
}