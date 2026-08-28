import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';

import 'user_access.dart';

/// Unread counters for the navigation badges.
///
/// These streams stay open for as long as the app is running, so they are
/// written to read as few documents as possible:
///  * group chat  -> only messages newer than the user's `groupLastReadAt`
///  * private chat -> only messages still flagged `isRead == false`
///  * announcements -> only the newest [_announcementWindow] posts
class NavBadges {
  static const int _messageWindow = 50;
  static const int _announcementWindow = 30;

  static String get _username =>
      FirebaseAuth.instance.currentUser?.email?.split('@').first ?? '';

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Marks a group chat as read up to now.
  static Future<void> markGroupRead({String field = 'groupLastReadAt'}) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        field: FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Legacy profiles are not keyed by uid; the badge simply falls back
      // to the newest-messages window.
    }
  }

  static Stream<int> groupUnreadStream({
    String groupId = 'general',
    String lastReadField = 'groupLastReadAt',
  }) {
    final me = _username;
    final uid = _uid;
    if (me.isEmpty || uid == null) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .switchMap((userSnap) {
      final lastRead = userSnap.data()?[lastReadField] as Timestamp?;

      Query<Map<String, dynamic>> q = FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .orderBy('sentAt');

      if (lastRead != null) {
        q = q.where('sentAt', isGreaterThan: lastRead);
      }

      return q.limit(_messageWindow).snapshots().map((snap) {
        return snap.docs
            .where((d) => (d.data()['senderId'] ?? '') != me)
            .length;
      });
    });
  }

  static Stream<int> privateUnreadStream() {
    final me = _username;
    if (me.isEmpty) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: me)
        .snapshots()
        .asyncMap((chatsSnap) async {
      int total = 0;
      for (final chatDoc in chatsSnap.docs) {
        final msgs = await chatDoc.reference
            .collection('messages')
            .where('isRead', isEqualTo: false)
            .limit(_messageWindow)
            .get();
        total += msgs.docs
            .where((m) => (m.data()['senderId'] ?? '') != me)
            .length;
      }
      return total;
    });
  }

  static Stream<int> managementUnreadStream() {
    if (!UserAccess.canUseManagementGroup) return Stream.value(0);
    return groupUnreadStream(
      groupId: UserAccess.managementGroupId,
      lastReadField: 'managementLastReadAt',
    );
  }

  static Stream<int> chatUnreadStream() {
    return Rx.combineLatest3<int, int, int, int>(
      groupUnreadStream(),
      managementUnreadStream(),
      privateUnreadStream(),
      (a, b, c) => a + b + c,
    );
  }

  static Stream<int> announcementUnreadStream() {
    final me = _username;
    if (me.isEmpty) return Stream.value(0);

    return FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .limit(_announcementWindow)
        .snapshots()
        .map((snap) {
      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        if ((data['title'] ?? '').toString().isEmpty) continue;
        final readBy = (data['readBy'] as List?) ?? [];
        if (!readBy.contains(me)) count++;
      }
      return count;
    });
  }
}
