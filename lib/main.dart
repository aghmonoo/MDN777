import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'login_page.dart';
import 'admin/admin_main_screen.dart';
import 'theme.dart';
import 'home_screen.dart';
import 'version_gate.dart';
import 'push_notifications.dart';
import 'user_access.dart';
import 'group_members.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  PushNotifications.registerBackgroundHandler();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Staff Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      home: const VersionGate(child: AuthWrapper()),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const RoleRouter();
        }
        // Signed out: drop anything cached about the previous account.
        UserAccess.clear();
        GroupMembers.clear();
        return const LoginPage();
      },
    );
  }
}

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});

  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  late final Future<Map<String, dynamic>?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _resolveProfile();
  }

  /// Loads the signed-in user's profile.
  ///
  /// Profiles are keyed by the Firebase Auth uid so that security rules can
  /// look them up directly. Older profiles used a random document id — those
  /// are re-keyed once, the first time the user signs in.
  Future<Map<String, dynamic>?> _resolveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final db = FirebaseFirestore.instance;
    final uid = user.uid;
    final username = user.email?.split('@').first ?? '';

    final byUid = await db.collection('users').doc(uid).get();
    if (byUid.exists) {
      UserAccess.loadFrom(byUid.data());
      unawaited(PushNotifications.start());
      return byUid.data();
    }

    final legacyQuery = await db
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    if (legacyQuery.docs.isEmpty) return null;

    final legacy = legacyQuery.docs.first;
    final data = Map<String, dynamic>.from(legacy.data());
    data['uid'] = uid;

    try {
      final writeBatch = db.batch();
      writeBatch.set(db.collection('users').doc(uid), data);
      writeBatch.delete(legacy.reference);
      await writeBatch.commit();
    } catch (_) {
      // Security rules may block the re-key for non-admins; the app still
      // works from the legacy document.
    }

    UserAccess.loadFrom(data);
    unawaited(PushNotifications.start());
    return data;
  }

  @override
  Widget build(BuildContext context) {
    final username =
        FirebaseAuth.instance.currentUser?.email?.split('@').first ?? '';

    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return _blockedScreen(username);
        }

        final role = data['role'] ?? 'employee';
        if (role == 'admin') {
          return const AdminMainScreen();
        }
        return const MainScreen();
      },
    );
  }

  Widget _blockedScreen(String username) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.person_off_outlined,
                    size: 36, color: Color(0xFFDC2626)),
              ),
              const SizedBox(height: 18),
              const Text(
                'Account not active',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No staff profile is linked to @$username.\n'
                'Please contact your administrator.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              ElevatedButton.icon(
                onPressed: () async {
                  await PushNotifications.stop();
                  UserAccess.clear();
                  await FirebaseAuth.instance.signOut();
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      body: HomeScreen(),
    );
  }
}