import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// One person in a group chat, as returned by the `listGroupMembers` function.
class GroupMember {
  const GroupMember({
    required this.username,
    required this.displayName,
    required this.role,
    required this.department,
    required this.position,
  });

  final String username;
  final String displayName;
  final String role;
  final String department;
  final String position;

  bool get isAdmin => role == 'admin';

  /// What to show under the name in the member list.
  String get subtitle {
    if (isAdmin) return 'Admin';
    if (position.isNotEmpty) return '$department - $position';
    return department.isEmpty ? 'Employee' : department;
  }

  /// Matches a mention query against the name and the username.
  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    if (username.toLowerCase().startsWith(q)) return true;
    for (final word in displayName.toLowerCase().split(RegExp(r'\s+'))) {
      if (word.startsWith(q)) return true;
    }
    return false;
  }

  factory GroupMember.fromMap(Map<dynamic, dynamic> m) => GroupMember(
        username: (m['username'] ?? '').toString(),
        displayName: (m['displayName'] ?? m['username'] ?? '').toString(),
        role: (m['role'] ?? 'employee').toString(),
        department: (m['department'] ?? '').toString(),
        position: (m['position'] ?? '').toString(),
      );
}

/// Loads and caches group rosters for the lifetime of the app session.
class GroupMembers {
  GroupMembers._();

  static final Map<String, List<GroupMember>> _cache = {};

  static List<GroupMember>? cached(String groupId) => _cache[groupId];

  static Future<List<GroupMember>> load(
    String groupId, {
    bool refresh = false,
  }) async {
    if (!refresh && _cache.containsKey(groupId)) return _cache[groupId]!;

    try {
      final result = await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('listGroupMembers').call<Map<String, dynamic>>({
        'groupId': groupId,
      });

      final raw = (result.data['members'] as List?) ?? const [];
      final members = raw
          .whereType<Map>()
          .map(GroupMember.fromMap)
          .where((m) => m.username.isNotEmpty)
          .toList();

      _cache[groupId] = members;
      return members;
    } catch (e) {
      debugPrint('Could not load members for $groupId: $e');
      return _cache[groupId] ?? const [];
    }
  }

  static void clear() => _cache.clear();
}
