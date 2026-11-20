import 'package:flutter/material.dart';

import '../../screens/shell.dart' show SubPage;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../config/supabase_config.dart';
import '../../state/backend.dart';
import '../admin_state.dart';

// ------------------------------------------------------------- Change password

/// Change the admin password (the demo keeps it until the app restarts).
class ChangePasswordForm extends StatefulWidget {
  const ChangePasswordForm({super.key});
  @override
  State<ChangePasswordForm> createState() => _ChangePasswordFormState();
}

class _ChangePasswordFormState extends State<ChangePasswordForm> {
  final _key = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Widget _field(
    String label,
    TextEditingController c,
    String? Function(String?) validator,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        TextFormField(controller: c, obscureText: !_show, validator: validator),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(
            'Current password',
            _current,
            // Online, Supabase checks it when saving.
            (v) => backendOn || v == adminPassword
                ? null
                : 'That is not your current password',
          ),
          _field(
            'New password',
            _new,
            (v) => (v ?? '').length < 6 ? 'Use at least 6 characters' : null,
          ),
          _field(
            'Confirm new password',
            _confirm,
            (v) => v == _new.text ? null : 'The passwords do not match',
          ),
          InkWell(
            onTap: () => setState(() => _show = !_show),
            child: Row(
              children: [
                Checkbox(
                  value: _show,
                  activeColor: AppColors.gold600,
                  onChanged: (v) => setState(() => _show = v ?? false),
                ),
                const Text(
                  'Show passwords',
                  style: TextStyle(fontSize: 13, color: AppColors.slate600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GoldButton(
            label: 'Update password',
            icon: Icons.lock_reset_rounded,
            onPressed: () async {
              if (!_key.currentState!.validate()) return;
              if (backendOn) {
                // Confirm the current password, then save the new one.
                final wrong = await backendSignIn(
                  SupabaseConfig.adminEmail,
                  _current.text,
                );
                if (!context.mounted) return;
                if (wrong != null) {
                  toast(context, 'That is not your current password.');
                  return;
                }
                final problem = await backendChangePassword(_new.text);
                if (!context.mounted) return;
                if (problem != null) {
                  toast(context, problem);
                  return;
                }
              } else {
                adminPassword = _new.text;
              }
              popOnce(context);
              toast(context, 'Password updated');
            },
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Notifications

/// Which alerts the admin wants. They apply once push notifications are on.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) => SubPage(
        title: 'Notifications',
        children: [
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            child: Column(
              children: [
                for (final e in adminState.alertPrefs.entries)
                  SwitchListTile(
                    value: e.value,
                    title: Text(
                      e.key,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.green800,
                      ),
                    ),
                    onChanged: (v) => adminState.setAlert(e.key, v),
                  ),
              ],
            ),
          ),
          const Text(
            'Turned-off items no longer show under Needs your attention or as gold dots on the dashboard. '
            'Once push notifications are connected, they also decide which alerts reach your phone.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.slate300,
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything the admin changed, newest first: payments, cheques, leases,
/// deposits, documents, bookings and settings.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});
  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  String _q = '';

  static const _months = [
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
    'Dec',
  ];

  String _when(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${_months[d.month - 1]} ${d.day}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  IconData _icon(String action) {
    final a = action.toLowerCase();
    if (a.contains('payment') || a.contains('charge')) {
      return Icons.payments_outlined;
    }
    if (a.contains('cheque')) return Icons.money_rounded;
    if (a.contains('lease') || a.contains('renewal')) {
      return Icons.description_outlined;
    }
    if (a.contains('moved')) return Icons.logout_rounded;
    if (a.contains('deposit')) return Icons.savings_outlined;
    if (a.contains('document')) return Icons.badge_outlined;
    if (a.contains('booking')) return Icons.luggage_outlined;
    if (a.contains('work') || a.contains('report')) {
      return Icons.handyman_outlined;
    }
    if (a.contains('account')) return Icons.person_outline_rounded;
    return Icons.history_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final all = adminState.activityLog;
        final shown = all
            .where((e) => matchesSearch(_q, [e.action, e.detail]))
            .toList();
        return SubPage(
          title: 'Activity log',
          children: [
            if (all.isNotEmpty)
              SearchField(
                hint: 'Search the log',
                onChanged: (v) => setState(() => _q = v),
              ),
            if (all.isEmpty)
              const EmptyState(
                icon: Icons.history_rounded,
                title: 'Nothing yet',
                message: 'What you change (payments, cheques, leases, deposits...) is listed here.',
              ),
            for (final e in shown)
              AppCard(
                radius: 18,
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBadge(_icon(e.action), size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  e.action,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.green800,
                                  ),
                                ),
                              ),
                              Text(
                                _when(e.at),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.slate400,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.detail,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: AppColors.slate600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (all.isNotEmpty)
              const Text(
                'Kept while the app is open. With the backend, each entry also records who made it.',
                style: TextStyle(fontSize: 12, color: AppColors.slate300),
              ),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------- Legal pages

/// A page of titled paragraphs (privacy policy, terms).
class TextPageScreen extends StatelessWidget {
  const TextPageScreen(this.title, this.sections, {super.key});
  final String title;
  final List<(String, String)> sections;

  static const privacy = TextPageScreen('Privacy policy', [
    (
      'What we keep',
      'Tenant names, contact details, ID and clearance documents, lease and payment records, damage reports, complaints and chat messages.',
    ),
    (
      'Why',
      'To manage tenancies, collect rent, handle repairs and keep the records the lease requires. We do not sell personal data or use it for advertising.',
    ),
    (
      'Who can see it',
      'Only management and the tenant it belongs to. Payments are processed by the payment provider; card details never pass through this app.',
    ),
    (
      'How long we keep it',
      'Tenant records are kept after a tenancy ends, for accounting and income reporting, and for as long as the law requires.',
    ),
    (
      'Your rights',
      'Under the Data Privacy Act of 2012 (RA 10173), tenants can ask to see, correct or request deletion of their data, and to withdraw consent where it applies. Contact management to make a request.',
    ),
    (
      'Draft notice',
      'This is draft wording. Have a lawyer review it before the app is used with real tenants.',
    ),
  ]);

  static const terms = TextPageScreen('Terms of use', [
    (
      'Private app',
      'This app is for Ayan Residences tenants and management only. Accounts are created by management; there is no public sign-up.',
    ),
    (
      'Your account',
      'Keep your login private. Management may suspend an account that is shared or misused.',
    ),
    (
      'Payments',
      'Rent recorded in the app follows your lease. A payment counts once management or the payment provider has confirmed it.',
    ),
    (
      'Messages and reports',
      'Use chat, reports and complaints honestly and respectfully. Photos and documents you upload must be your own.',
    ),
    (
      'Your lease',
      'The signed lease is the agreement between the owner and the tenant. This app is a tool to manage it and does not change its terms.',
    ),
    (
      'Draft notice',
      'This is draft wording. Have a lawyer review it before the app is used with real tenants.',
    ),
  ]);

  @override
  Widget build(BuildContext context) {
    return SubPage(
      title: title,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < sections.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                Text(
                  sections[i].$1,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sections[i].$2,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppColors.slate600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
