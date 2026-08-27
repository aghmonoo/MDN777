
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_version.dart';
import 'theme.dart';

/// Blocks the app when Firestore says the installed build is too old.
///
/// Firestore document: app_config/version
///   minBuild   (int)    -> below this the app is hard-blocked
///   latestBuild(int)    -> above current build shows a dismissible banner
///   androidUrl (string) -> Play Store / APK link
///   webUrl     (string) -> web app link
///   message    (string) -> optional custom text
class VersionGate extends StatefulWidget {
  const VersionGate({super.key, required this.child});

  final Widget child;

  @override
  State<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<VersionGate> {
  Map<String, dynamic>? _cfg;
  bool _checked = false;
  bool _softDismissed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get(const GetOptions(source: Source.server));
      if (mounted) setState(() => _cfg = snap.data());
    } catch (_) {
      // Offline or blocked -> never lock the user out.
    } finally {
      if (mounted) setState(() => _checked = true);
    }
  }

  String get _storeUrl {
    final cfg = _cfg ?? const {};
    if (kIsWeb) return (cfg['webUrl'] ?? '').toString();
    return (cfg['androidUrl'] ?? '').toString();
  }

  Future<void> _openStore() async {
    final url = _storeUrl;
    if (url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final cfg = _cfg ?? const {};
    final minBuild = (cfg['minBuild'] as num?)?.toInt() ?? 0;
    final latestBuild = (cfg['latestBuild'] as num?)?.toInt() ?? 0;

    if (AppVersion.build < minBuild) {
      return _blockScreen(cfg);
    }

    if (!_softDismissed && AppVersion.build < latestBuild) {
      return Stack(
        children: [
          widget.child,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _updateBanner(),
          ),
        ],
      );
    }

    return widget.child;
  }

  Widget _updateBanner() {
    return Material(
      color: AppTheme.primary,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              const Icon(Icons.system_update, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'A newer version is available.',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              if (_storeUrl.isNotEmpty)
                TextButton(
                  onPressed: _openStore,
                  child: const Text('UPDATE',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              IconButton(
                onPressed: () => setState(() => _softDismissed = true),
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blockScreen(Map<String, dynamic> cfg) {
    final message = (cfg['message'] ?? '').toString().isNotEmpty
        ? cfg['message'].toString()
        : 'This version of Staff Connect is no longer supported.\n'
            'Please install the latest version to continue.';

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
                  color: AppTheme.primarySurface,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.system_update,
                    size: 36, color: AppTheme.primary),
              ),
              const SizedBox(height: 18),
              const Text(
                'Update required',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Installed: v${AppVersion.name} (${AppVersion.build})',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textTertiary),
              ),
              const SizedBox(height: 26),
              if (_storeUrl.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _openStore,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Get the update'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
