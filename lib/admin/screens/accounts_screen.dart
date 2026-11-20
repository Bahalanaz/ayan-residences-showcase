import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../screens/home_screen.dart' show push;
import '../../screens/shell.dart' show SubPage, TabBody;
import '../../state/demo.dart';
import '../../state/sync.dart' show EditingGuard, Sync;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';
import 'doc_review.dart';
import 'tenants_screen.dart';

// ------------------------------------------------------------------ List

/// Tenant accounts: create a login, assign a unit, keep every detail editable.
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final all = adminState.tenants;
        // Search by name, unit, username, phone or email.
        final list = all
            .where(
              (t) => matchesSearch(_q, [
                t.name,
                t.unitLabel,
                t.username,
                t.phone,
                t.email,
                adminState.unitTypeOf(t),
              ]),
            )
            .toList();
        return TabBody(
          children: [
            ScreenHeader(
              'Accounts',
              subtitle:
                  '${all.length} tenant ${all.length == 1 ? 'account' : 'accounts'}',
              action: GoldButton(
                label: 'New',
                icon: Icons.add,
                compact: true,
                expand: false,
                onPressed: () => push(context, const AccountFormScreen()),
              ),
            ),
            if (all.length > 1)
              SearchField(
                hint: 'Search name, unit, phone',
                onChanged: (v) => setState(() => _q = v),
              ),
            LoadingSwitch(
              skeleton: const SkeletonCards(count: 4),
              child: list.isEmpty && all.isNotEmpty
                  ? EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No match',
                      message: 'No account matches "$_q".',
                    )
                  : list.isEmpty
                  ? EmptyState(
                      icon: Icons.person_add_alt_1_outlined,
                      title: 'No accounts yet',
                      message: 'Create an account once a tenant has paid, then send them the login.',
                      actionLabel: 'Create account',
                      onAction: () => push(context, const AccountFormScreen()),
                    )
                  : Column(
                      children: [
                        for (final t in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _AccountCard(t),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard(this.t);
  final TenantRec t;

  @override
  Widget build(BuildContext context) {
    final required = adminState.requiredDocs(t);
    final docs = required.where((d) => t.docs[d] ?? false).length;
    return AppCard(
      radius: 18,
      onTap: () => push(context, AccountDetailScreen(t)),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.gold500,
            child: Icon(Icons.person, color: AppColors.green900),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                Text(
                  '${t.unitLabel} · ${t.stayType}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.slate500,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (adminState.unitTypeOf(t).isNotEmpty)
                      _Chip(Icons.home_work_outlined, adminState.unitTypeOf(t)),
                    _Chip(
                      Icons.folder_open_outlined,
                      '$docs/${required.length} docs',
                      ok: docs == required.length,
                    ),
                    _Chip(
                      Icons.description_outlined,
                      !t.hasSignedLease && !t.hasContract
                          ? 'No lease'
                          : 'Lease uploaded',
                      ok: t.hasSignedLease || t.hasContract,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.slate400),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.icon, this.text, {this.ok});
  final IconData icon;
  final String text;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final color = ok == null
        ? AppColors.slate600
        : ok!
        ? AppColors.emerald
        : AppColors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Create / edit

/// Choice in the unit dropdown for a ready account with no unit assigned yet.
const _availableLabel = 'Available (no unit yet)';

/// Create a new account, or edit it. Rent, stay type and lease dates follow
/// from the unit and from what the tenant pays, so they are not entered here.
class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({super.key, this.existing, this.presetUnit});
  final TenantRec? existing;
  final String? presetUnit;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen>
    with EditingGuard {
  final _key = GlobalKey<FormState>();
  late final TenantRec? _t = widget.existing;
  late final _name = TextEditingController(text: _t?.name ?? '');
  late final _deposit = TextEditingController(
    text: _t?.deposit.toStringAsFixed(0) ?? '',
  );
  late final _username = TextEditingController(text: _t?.username ?? '');
  late final _password = TextEditingController(text: _t?.password ?? '');
  late String _unit = _t != null
      ? (_t.unit.isEmpty ? _availableLabel : _t.unit)
      : (widget.presetUnit ?? _availableLabel);
  bool _show = false;

  /// "Available" first (a ready account with no unit yet), then the units
  /// that can be chosen, grouped by property: empty ones plus this tenant's own.
  List<PickerOption> _unitOptions() {
    final units = [
      for (final u in adminState.units)
        // Condos are tracked by hand (no guest accounts), so they aren't offered.
        if (u.type != 'Condo' &&
            (u.status == UnitStatus.vacant ||
                u.name == _t?.unit ||
                u.name == widget.presetUnit))
          u,
    ];
    return [
      const PickerOption(
        value: _availableLabel,
        label: _availableLabel,
        subtitle: 'Create the account now and assign a unit later',
        icon: Icons.person_add_alt_1_rounded,
      ),
      for (final u in units)
        PickerOption(
          value: u.name,
          label: u.name,
          subtitle:
              '${u.type} · ${peso(u.rate, dhs: u.type == 'Villa')} per ${u.rateUnit}',
          icon: switch (u.type) {
            'Villa' => Icons.house_rounded,
            'Condo' => Icons.domain_rounded,
            _ => Icons.meeting_room_rounded,
          },
          group: u.property,
          badge: u.name == _t?.unit ? 'Current' : 'Vacant',
          badgeColor: u.name == _t?.unit
              ? AppColors.gold700
              : AppColors.emerald,
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    if (_t == null) _fillFromUnit(_unit);
  }

  UnitRec? get _unitRec =>
      adminState.units.where((u) => u.name == _unit).firstOrNull;

  /// The security deposit starts equal to the unit's rate.
  void _fillFromUnit(String unit) {
    if (unit == _availableLabel) {
      _deposit.text = '';
      return;
    }
    _deposit.text = adminState.units
        .firstWhere((u) => u.name == unit)
        .rate
        .toStringAsFixed(0);
  }

  @override
  void dispose() {
    for (final c in [_name, _deposit, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  void _generate() {
    setState(() {
      _username.text = adminState.generateUsername(
        _name.text,
        _unitRec?.name ?? '',
      );
      _password.text = adminState.generatePassword();
      _show = true;
    });
  }

  /// Errors stay up to date while typing once the admin tried to save.
  AutovalidateMode _check = AutovalidateMode.disabled;

  void _save() {
    if (!_key.currentState!.validate()) {
      setState(() => _check = AutovalidateMode.onUserInteraction);
      toast(context, 'Please fix the fields marked in red.');
      return;
    }
    final deposit =
        double.tryParse(_deposit.text.trim().replaceAll(',', '')) ?? 0;
    if (_t == null) {
      final u = _unitRec;
      final created = TenantRec(
        name: _name.text.trim(),
        unit: u?.name ?? '',
        phone: '',
        email: '',
        stayType: u == null ? 'Not assigned' : stayTypeFor(u.type),
        rent: u?.rate ?? 0,
        deposit: deposit,
        leaseStart: '',
        leaseEnd: '',
        username: _username.text.trim(),
        password: _password.text,
      );
      adminState.createAccount(created);
      popOnce(context);
      push(context, AccountDetailScreen(created));
      toast(context, 'Account created. Send the login details to the tenant.');
    } else {
      adminState.updateAccount(
        _t,
        name: _name.text.trim(),
        unit: _unitRec?.name ?? '',
        deposit: deposit,
        username: _username.text.trim(),
        password: _password.text,
      );
      popOnce(context);
      toast(context, 'Account updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = _t != null;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          editing ? 'Edit account' : 'Create account',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _key,
              autovalidateMode: _check,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _Section('Tenant', [
                    const FieldLabel('Full name'),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _Section('Unit', [
                    const FieldLabel('Assigned unit'),
                    DropdownField(
                      value: _unit,
                      title: 'Assign a unit',
                      options: _unitOptions(),
                      onChanged: (v) => setState(() {
                        _unit = v;
                        if (!editing) _fillFromUnit(v);
                      }),
                    ),
                    const SizedBox(height: 12),
                    FieldLabel(
                      'Security deposit (${currencySign(adminState.isVillaUnit(_unit))})',
                    ),
                    TextFormField(
                      controller: _deposit,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        final t = (v ?? '').trim();
                        if (t.isEmpty) return null;
                        final n = double.tryParse(t.replaceAll(',', ''));
                        return n == null || n < 0
                            ? 'Enter an amount (numbers only)'
                            : null;
                      },
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _Section('Login', [
                    const FieldLabel('Username'),
                    TextFormField(
                      controller: _username,
                      autocorrect: false,
                      validator: (v) {
                        final name = (v ?? '').trim();
                        if (name.length < 3) return 'At least 3 characters';
                        if (name.length > 40) return 'At most 40 characters';
                        // The login server only takes these (no spaces).
                        if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
                          return 'Only letters, numbers, dots, dashes or underscores (no spaces)';
                        }
                        if (adminState.usernameTaken(name, except: _t)) {
                          return 'Already taken';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    const FieldLabel('Password'),
                    TextFormField(
                      controller: _password,
                      obscureText: !_show,
                      autocorrect: false,
                      validator: (v) {
                        final p = v ?? '';
                        // Saved passwords are never shown again, so an empty
                        // box when editing keeps the current one.
                        if (editing && p.isEmpty && !demoData) return null;
                        final min = demoData ? 3 : 6;
                        if (p.length < min) return 'At least $min characters';
                        if (p.contains(' ')) return 'No spaces';
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: editing && !demoData
                            ? 'Leave empty to keep the current password'
                            : null,
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _show = !_show),
                          icon: Icon(
                            _show
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: AppColors.slate400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _generate,
                      icon: const Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: AppColors.gold700,
                      ),
                      label: const Text(
                        'Generate username and password',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.gold700,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  GoldButton(
                    label: editing ? 'Save changes' : 'Create account',
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.green800,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Detail

class AccountDetailScreen extends StatefulWidget {
  const AccountDetailScreen(this.t, {super.key});
  final TenantRec t;
  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  bool _show = false;

  /// The tenant as loaded now: a live update from the server replaces the
  /// records, so look them up again by their id.
  TenantRec get _current =>
      adminState.tenants
          .where(
            (x) =>
                identical(x, widget.t) ||
                (widget.t.id != null && x.id == widget.t.id),
          )
          .firstOrNull ??
      widget.t;

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Sets a new password (generated, can be changed) and shows it.
  Future<void> _newPassword(TenantRec t) async {
    final ctrl = TextEditingController(text: adminState.generatePassword());
    final p = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${t.name} will log in with this from now on.',
              style: const TextStyle(fontSize: 13, color: AppColors.slate600),
            ),
            const SizedBox(height: 10),
            TextField(controller: ctrl, autocorrect: false),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => popOnce(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold500,
              foregroundColor: AppColors.green900,
            ),
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.length < 6 || v.contains(' ')) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('At least 6 characters, no spaces.'),
                  ),
                );
                return;
              }
              popOnce(ctx, v);
            },
            child: const Text(
              'Save',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (p == null || !mounted) return;
    adminState.setTenantPassword(t, p);
    setState(() => _show = true);
    toast(context, 'Password changed. Tap Copy WhatsApp message to send it.');
  }

  @override
  void initState() {
    super.initState();
    adminState.addListener(_changed);
    // Their documents, contract and signed lease download now.
    Sync.fetchTenant(_current);
  }

  @override
  void dispose() {
    adminState.removeListener(_changed);
    super.dispose();
  }

  Future<void> _pickLease() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const IconBadge(Icons.photo_camera_outlined, size: 34),
              title: const Text(
                'Take a photo',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.green800,
                ),
              ),
              onTap: () => popOnce(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const IconBadge(Icons.photo_library_outlined, size: 34),
              title: const Text(
                'Choose from gallery',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.green800,
                ),
              ),
              onTap: () => popOnce(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (file == null) return;
      adminState.setSignedLease(_current, await file.readAsBytes());
      if (mounted) {
        toast(context, 'Signed lease uploaded. The tenant can see it.');
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not open the photo picker.');
    }
  }

  void _confirmDelete() {
    final why = adminState.whyKeepAccount(_current);
    if (why != null) {
      toast(context, why);
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Text(
          '${_current.name} will no longer be able to log in, and ${_current.unit.isEmpty ? 'no unit is affected' : '${_current.unit} becomes vacant'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => popOnce(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              adminState.deleteAccount(_current);
              popOnce(ctx);
              popOnce(context);
              toast(context, 'Account deleted');
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _current;
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) => SubPage(
        title: t.name,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Account',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () =>
                          push(context, AccountFormScreen(existing: t)),
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: AppColors.gold700,
                      ),
                      label: const Text(
                        'Edit',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.gold700,
                        ),
                      ),
                    ),
                  ],
                ),
                KeyValueRow('Unit', t.unitLabel),
                KeyValueRow(
                  'Security deposit',
                  peso(t.deposit, dhs: adminState.isVilla(t.name)),
                  last: true,
                ),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Login',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                const SizedBox(height: 4),
                KeyValueRow('Username', t.username),
                KeyValueRow(
                  'Password',
                  _show ? t.password : '••••••••',
                  last: true,
                ),
                // Saved passwords are never kept (only the server can check them),
                // so after a reload there is nothing to show: set a new one.
                if (t.password.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'This password was set before passwords were saved. Tap Reset to set one you can see and send.',
                      style: TextStyle(fontSize: 12, color: AppColors.slate500),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.green800,
                          side: const BorderSide(color: AppColors.slate300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: t.password.isEmpty
                            ? () => _newPassword(t)
                            : () => setState(() => _show = !_show),
                        icon: Icon(
                          t.password.isEmpty
                              ? Icons.lock_reset_rounded
                              : _show
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 16,
                        ),
                        label: Text(
                          t.password.isEmpty
                              ? 'Reset'
                              : (_show ? 'Hide' : 'Show'),
                          maxLines: 1,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: GoldButton(
                        label: 'Copy WhatsApp message',
                        icon: Icons.copy_rounded,
                        onPressed: () {
                          if (t.password.isEmpty) {
                            toast(
                              context,
                              'Set a new password first (saved ones can\'t be shown).',
                            );
                            return;
                          }
                          Clipboard.setData(
                            ClipboardData(
                              text:
                                  'Welcome to Ayan Residences! Your login - Username: ${t.username}  Password: ${t.password}',
                            ),
                          );
                          toast(
                            context,
                            'Message copied. Paste it in WhatsApp.',
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Documents from the tenant',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                const Text(
                  'The tenant uploads these in their app.',
                  style: TextStyle(fontSize: 12, color: AppColors.slate500),
                ),
                const SizedBox(height: 4),
                for (final d in adminState.requiredDocs(t)) DocReviewRow(t, d),
              ],
            ),
          ),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Signed lease',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                const Text(
                  'You upload a photo of the signed lease.',
                  style: TextStyle(fontSize: 12, color: AppColors.slate500),
                ),
                const SizedBox(height: 10),
                if (!t.hasSignedLease)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _pickLease,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        color: AppColors.slate50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.slate200),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 30,
                            color: AppColors.gold500,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Upload signed lease',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.green800,
                            ),
                          ),
                          Text(
                            'Camera or gallery',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.slate500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: t.signedLease == null
                        ? Container(
                            height: 200,
                            color: AppColors.slate100,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.gold600,
                            ),
                          )
                        : Image.memory(
                            t.signedLease!,
                            fit: BoxFit.cover,
                            height: 200,
                            width: double.infinity,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.red,
                            side: const BorderSide(color: AppColors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => adminState.setSignedLease(t, null),
                          child: const Text(
                            'Remove',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GoldButton(
                          label: 'Replace',
                          onPressed: _pickLease,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          NavyButton(
            label: 'Payments, balance and deposit',
            icon: Icons.account_balance_wallet_outlined,
            onPressed: () => push(context, TenantDetailScreen(t)),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.redBg,
              side: const BorderSide(color: AppColors.redBg),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _confirmDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text(
              'Delete account',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}
