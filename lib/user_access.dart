/// Who the signed-in user is, cached from their profile at sign-in.
///
/// Used to decide which chats are offered. The security rules enforce the
/// same conditions server-side; this only controls what is shown.
class UserAccess {
  static const String managementGroupId = 'management';
  static const String managementGroupTitle = 'Management';

  static bool isAdmin = false;
  static String department = '';
  static String position = '';

  static void loadFrom(Map<String, dynamic>? data) {
    final d = data ?? const {};
    isAdmin = (d['role'] ?? '') == 'admin';
    department = (d['department'] ?? '').toString();
    position = (d['position'] ?? '').toString();
  }

  static void clear() {
    isAdmin = false;
    department = '';
    position = '';
  }

  /// Admins, plus Management staff holding a TL or QA position.
  /// Moderation staff and Management/Mod are deliberately excluded.
  static bool get canUseManagementGroup =>
      isAdmin ||
      (department == 'Management' && (position == 'TL' || position == 'QA'));
}
