import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';

class NavBadges {
  static String get _username =>
      FirebaseAuth.instance.currentUser?.email?.split('@').first ?? '';

  // Chat unread — combine group + private chats (no collectionGroup)
  static Stream<int> chatUnreadStream() {
    final uid = _username;
    if (uid.isEmpty) return Stream.value(0);

    // Group chat unread
    final groupStream = FirebaseFirestore.instance
        .collection('groups')
        .doc('general')
        .collection('messages')
        .snapshots()
        .map((snap) {
      int count = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['senderId'] ?? '') == uid) continue;
        final readBy = (d['readBy'] as List?) ?? [];
        if (!readBy.contains(uid)) count++;
      }
      return count;
    });

    // Private chats unread
    final privateStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .asyncMap((chatsSnap) async {
      int total = 0;
      for (final chatDoc in chatsSnap.docs) {
        final msgsSnap = await chatDoc.reference
            .collection('messages')
            .where('isRead', isEqualTo: false)
            .get();
        for (final m in msgsSnap.docs) {
          if ((m.data()['senderId'] ?? '') == uid) continue;
          total++;
        }
      }
      return total;
    });

    return Rx.combineLatest2<int, int, int>(
      groupStream,
      privateStream,
      (a, b) => a + b,
    );
  }

  static Stream<int> announcementUnreadStream() {
    final uid = _username;
    if (uid.isEmpty) return Stream.value(0);
    return FirebaseFirestore.instance
        .collection('announcements')
        .snapshots()
        .map((snap) {
      int count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final readBy = (data['readBy'] as List?) ?? [];
        final unread = !readBy.contains(uid);
        if (unread) {
          count++;
          print('[NavBadges] UNREAD ann: id=${doc.id} title=${data['title']} readBy=$readBy');
        }
      }
      print('[NavBadges] Total ann unread: $count');
      return count;
    });
  }
}