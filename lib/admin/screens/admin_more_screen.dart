import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../screens/login_screen.dart';
import '../../screens/shell.dart' show TabBody;
import '../../state/backend.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/common.dart';
import 'admin_info_screens.dart';
import 'storage_screen.dart';

/// Settings, help and legal pages, and sign out.
class AdminMoreScreen extends StatelessWidget {
  const AdminMoreScreen({super.key});

  static const version = '1.0.0 (build 1)';

  @override
  Widget build(BuildContext context) {
    return TabBody(
      children: [
        const ScreenHeader('More'),
        // Who is signed in.
        AppCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.gold500,
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: AppColors.green900,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Administrator',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                    Text(
                      'Ayan Residences management',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.slate500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _Group('Account', [
          _Row(
            Icons.lock_outline_rounded,
            'Change password',
            'Keep your admin login safe',
            () => showAppSheet(
              context,
              title: 'Change password',
              builder: (_) => const ChangePasswordForm(),
            ),
          ),
          _Row(
            Icons.notifications_none_rounded,
            'Notifications',
            'Choose which alerts you get',
            () => push(context, const NotificationSettingsScreen()),
          ),
          _Row(
            Icons.history_rounded,
            'Activity log',
            'Everything that was changed, and when',
            () => push(context, const ActivityLogScreen()),
          ),
          _Row(
            Icons.storage_rounded,
            'Storage & cleanup',
            'How full the file storage is',
            () => push(context, const StorageScreen()),
          ),
        ]),
        _Group('Legal', [
          _Row(
            Icons.privacy_tip_outlined,
            'Privacy policy',
            'How tenant data is handled',
            () => push(context, TextPageScreen.privacy),
          ),
          _Row(
            Icons.gavel_rounded,
            'Terms of use',
            'Rules for using the app',
            () => push(context, TextPageScreen.terms),
          ),
        ]),
        _Group('About', [
          const _Row(
            Icons.info_outline_rounded,
            'Ayan Residences',
            'Rental management · version $version',
            null,
          ),
        ]),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.gold400,
            backgroundColor: AppColors.greenDeep,
            side: BorderSide(color: AppColors.gold500.withValues(alpha: .5)),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () async {
            final nav = Navigator.of(context);
            final done = await runBusy(context, 'Signing out…', () async {
              await Session.clear();
              await backendSignOut();
            });
            if (!done) return;
            nav.pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout, size: 16),
          label: const Text(
            'Sign Out',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const Center(child: Opacity(opacity: .7, child: AppLogo(size: 30))),
      ],
    );
  }
}

/// A titled card holding a few tappable rows.
class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
              color: AppColors.gold400,
            ),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.title, this.sub, this.onTap);
  final IconData icon;
  final String title, sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    leading: IconBadge(icon, size: 36),
    title: Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: AppColors.green800,
      ),
    ),
    subtitle: Text(
      sub,
      style: const TextStyle(fontSize: 12, color: AppColors.slate500),
    ),
    trailing: onTap == null
        ? null
        : const Icon(Icons.chevron_right, size: 20, color: AppColors.slate400),
  );
}
