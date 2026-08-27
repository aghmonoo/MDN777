import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'admin_announcements_page.dart';
import 'admin_payslips_page.dart';
import 'admin_bank_logs_page.dart';
import 'admin_users_page.dart';
import 'admin_chat_page.dart';
import 'admin_profile_page.dart';
import 'recycle_bin.dart';
import '../nav_badges.dart';

class AdminMainScreen extends StatefulWidget {
  const AdminMainScreen({super.key});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  String _displayName = 'Admin';
  String _username = '';

  late final Stream<QuerySnapshot> _usersStream;
  late final Stream<QuerySnapshot> _announcementsStream;
  late final Stream<QuerySnapshot> _bankLogsStream;
  Stream<int>? _chatUnreadStream;

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    _usersStream = db.collection('users').snapshots();
    _announcementsStream =
        db.collection('announcements').orderBy('createdAt', descending: true).limit(100).snapshots();
    _bankLogsStream = db
        .collection('bank_change_logs')
        .where('isRead', isEqualTo: false)
        .snapshots();
    _loadAdminInfo();
  }

  Future<void> _loadAdminInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    final username = user?.email?.split('@').first ?? '';

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final data = snapshot.docs.first.data();
      if (mounted) {
        setState(() {
          _username = username;
          _displayName = data['displayName'] ?? 'Admin';
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
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
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      await FirebaseAuth.instance.signOut();
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHero(),
            Transform.translate(
              offset: const Offset(0, -50),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryStats(),
                  const SizedBox(height: 20),
                  _buildQuickActionsLabel(),
                  const SizedBox(height: 8),
                  _buildActionsGrid(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    final initial = _displayName.isNotEmpty
        ? _displayName.substring(0, 1).toUpperCase()
        : 'A';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E3A8A), // indigo-900
            Color(0xFF3730A3), // indigo-800
            AppTheme.primary,  // sky blue
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -60,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Admin Panel',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.amber.withOpacity(0.5),
                              width: 0.5,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield,
                                  size: 12, color: Colors.amber),
                              SizedBox(width: 4),
                              Text(
                                'ADMIN',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _glassButton(
                          icon: Icons.logout_rounded,
                          onTap: _logout,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3730A3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_greeting()},',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _displayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text('👋',
                                  style: TextStyle(fontSize: 18)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate() {
    final dt = DateTime.now();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${days[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
  }

  Widget _glassButton({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.25),
              width: 0.5,
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Widget _buildSummaryStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppTheme.elevatedShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _usersStream,
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  return _statTile(
                    icon: Icons.people_outline,
                    gradStart: AppTheme.blueStart,
                    gradEnd: AppTheme.blueEnd,
                    iconColor: AppTheme.blueIcon,
                    count: '$count',
                    label: 'Total users',
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _announcementsStream,
                builder: (context, snap) {
                  final count = (snap.data?.docs ?? []).where((d) {
                    final title =
                        ((d.data() as Map<String, dynamic>)['title'] ?? '')
                            .toString();
                    return title.isNotEmpty;
                  }).length;
                  return _statTile(
                    icon: Icons.campaign_outlined,
                    gradStart: AppTheme.amberStart,
                    gradEnd: AppTheme.amberEnd,
                    iconColor: AppTheme.amberIcon,
                    count: '$count',
                    label: 'Posts',
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color gradStart,
    required Color gradEnd,
    required Color iconColor,
    required String count,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [gradStart, gradEnd]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsLabel() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        'Quick Actions',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildActionsGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.15,
        children: [
          _actionTile(
            icon: Icons.campaign_outlined,
            label: 'Announcements',
            gradStart: AppTheme.amberStart,
            gradEnd: AppTheme.amberEnd,
            iconColor: AppTheme.amberIcon,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminAnnouncementsPage(),
              ),
            ),
          ),
          _actionTile(
            icon: Icons.receipt_long_outlined,
            label: 'Pay Slips',
            gradStart: AppTheme.greenStart,
            gradEnd: AppTheme.greenEnd,
            iconColor: AppTheme.greenIcon,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminPayslipsPage(),
              ),
            ),
          ),
          _chatTile(),
          _bankLogsTile(),
          _actionTile(
            icon: Icons.people_outline,
            label: 'Users',
            gradStart: AppTheme.blueStart,
            gradEnd: AppTheme.blueEnd,
            iconColor: AppTheme.blueIcon,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminUsersPage(),
              ),
            ),
          ),
          _actionTile(
            icon: Icons.restore_from_trash_outlined,
            label: 'Recycle Bin',
            gradStart: const Color(0xFFE2E8F0),
            gradEnd: const Color(0xFFCBD5E1),
            iconColor: const Color(0xFF475569),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminRecycleBinPage(),
              ),
            ),
          ),
          _actionTile(
            icon: Icons.person_outline,
            label: 'Profile',
            gradStart: AppTheme.pinkStart,
            gradEnd: AppTheme.pinkEnd,
            iconColor: AppTheme.pinkIcon,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AdminProfilePage(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color gradStart,
    required Color gradEnd,
    required Color iconColor,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [gradStart, gradEnd],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: iconColor, size: 26),
                    ),
                    if (badge > 0)
                      Positioned(
                        top: -4,
                        right: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          constraints: const BoxConstraints(
                              minWidth: 20, minHeight: 20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.white, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF4444)
                                    .withOpacity(0.4),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Text(
                            badge > 9 ? '9+' : '$badge',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chatTile() {
    if (_username.isEmpty) {
      return _actionTile(
        icon: Icons.chat_bubble_outline,
        label: 'Chat',
        gradStart: AppTheme.primarySoft,
        gradEnd: AppTheme.primaryLight,
        iconColor: Colors.white,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminChatPage()),
        ),
      );
    }

    _chatUnreadStream ??= NavBadges.chatUnreadStream();

    return StreamBuilder<int>(
      stream: _chatUnreadStream,
      builder: (context, snap) {
        return _actionTile(
          icon: Icons.chat_bubble_outline,
          label: 'Chat',
          gradStart: AppTheme.primarySoft,
          gradEnd: AppTheme.primaryLight,
          iconColor: Colors.white,
          badge: snap.data ?? 0,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminChatPage()),
          ),
        );
      },
    );
  }

  Widget _bankLogsTile() {
    return StreamBuilder<QuerySnapshot>(
      stream: _bankLogsStream,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs.length ?? 0;
        return _actionTile(
          icon: Icons.account_balance_outlined,
          label: 'Bank Logs',
          gradStart: const Color(0xFFFECACA),
          gradEnd: const Color(0xFFFEE2E2),
          iconColor: const Color(0xFFDC2626),
          badge: unreadCount,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminBankLogsPage()),
          ),
        );
      },
    );
  }
}