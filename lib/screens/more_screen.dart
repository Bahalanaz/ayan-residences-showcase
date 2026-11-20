import 'package:flutter/material.dart';

import '../admin/admin_state.dart' show DocState, adminState, tenantDocs;
import '../state/app_state.dart';
import '../state/backend.dart';
import '../state/demo.dart';
import '../state/session.dart';
import '../theme.dart';
import '../widgets/chat_view.dart' show chooseDocument;
import '../widgets/common.dart';
import 'chat_screen.dart';
import 'contract_screen.dart';
import 'home_screen.dart' show push;
import 'login_screen.dart';
import 'shell.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final s = appState;
        return TabBody(children: [
          const ScreenHeader('Tenant Account & Records'),
          // Deposit summary
          if (adminState.hasDeposit(s.currentTenant)) AppCard(
            onTap: () => push(context, const DepositScreen()),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Expanded(
                  child: Text('SECURITY DEPOSIT',
                      style: TextStyle(
                          fontSize: 12,
                          letterSpacing: .4,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800)),
                ),
                Pill.info('HELD IN ESCROW'),
              ]),
              const SizedBox(height: 6),
              Text(peso(s.deposit),
                  style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold600)),
              const SizedBox(height: 4),
              const Text(
                  'Equal to 1 month\'s rent. Refunded on move-out once your last utility bills are paid and there is no damage, as stated in your lease.',
                  style: TextStyle(fontSize: 12, color: AppColors.slate500, height: 1.4)),
              const SizedBox(height: 8),
              const Row(children: [
                Text('View deposit record',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.gold600)),
                Icon(Icons.chevron_right, size: 16, color: AppColors.gold600),
              ]),
            ]),
          ),
          // The documents management needs from the tenant.
          const _DocumentsCard(),
          // Shortcuts
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(children: [
              _MenuTile(Icons.description_outlined, 'My Contract',
                  'Lease, expiry & renewal', () => push(context, const ContractScreen())),
              _MenuTile(Icons.chat_bubble_outline_rounded, 'Contact Management',
                  'Private messages & feedback', () => openChat(context)),
              if (adminState.hasDeposit(s.currentTenant)) _MenuTile(Icons.savings_outlined, 'Security Deposit',
                  'Deposit, refunds & deductions', () => push(context, const DepositScreen())),
              // Inspection records are not kept on the server yet (demo only).
              if (demoData)
                _MenuTile(Icons.rule_folder_outlined, 'Inspection Records',
                  'Move-in & move-out reports', () => push(context, const InspectionScreen())),
            ]),
          ),
          // Profile
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
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
                      const Text('Tenant Profile Details',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800)),
                      Text(s.unit,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.slate500)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => showContactSheet(context),
                  child: const Text('Edit',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: AppColors.gold600)),
                ),
              ]),
              const SizedBox(height: 8),
              KeyValueRow('Full Name', s.name),
              KeyValueRow('Registered Email', s.email),
              KeyValueRow('Contact Number', s.phone),
              KeyValueRow('Emergency Contact', s.emergencyContact),
              KeyValueRow('Declared Occupants', '${s.occupants} ${s.occupants == 1 ? 'person' : 'people'}', last: true),
            ]),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.gold400,
              backgroundColor: AppColors.greenDeep,
              side: BorderSide(color: AppColors.gold500.withValues(alpha: .5)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  (_) => false);
            },
            icon: const Icon(Icons.logout, size: 16),
            label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]);
      },
    );
  }
}

/// The documents management needs from the tenant (valid ID, ID picture and
/// clearances), each with an Upload button. Management sees the same status.
class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard();

  static const _icons = {
    'Valid ID': Icons.badge_outlined,
    'ID picture': Icons.account_box_outlined,
    'Barangay clearance': Icons.verified_user_outlined,
    'Police clearance': Icons.local_police_outlined,
    'NBI clearance': Icons.gpp_good_outlined,
    'Passport': Icons.menu_book_outlined,
    'Visa': Icons.flight_land_outlined,
    'EID': Icons.credit_card_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final t = adminState.tenants
            .where((x) => x.name == appState.currentTenant)
            .firstOrNull;
        final docs = t == null ? tenantDocs : adminState.requiredDocs(t);
        final done = docs.where((d) => t?.docs[d] ?? false).length;
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text('My Documents',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green800)),
              ),
              Pill(done == docs.length ? 'COMPLETE' : '$done/${docs.length}',
                  fg: done == docs.length ? AppColors.emerald : AppColors.amber,
                  bg: done == docs.length ? AppColors.emeraldBg : AppColors.amberBg),
            ]),
            const SizedBox(height: 2),
            const Text('Upload a clear photo or PDF of each one.',
                style: TextStyle(fontSize: 12, color: AppColors.slate500)),
            const SizedBox(height: 10),
            for (final d in docs)
              _DocUploadRow(
                label: d,
                icon: _icons[d] ?? Icons.description_outlined,
                state: t == null ? DocState.missing : adminState.docState(t, d),
                reason: t?.docRejected[d],
                fileName: t?.docFiles[d]?.name,
                onUpload: t == null
                    ? null
                    : () async {
                        final file = await chooseDocument(context);
                        if (file == null || !context.mounted) return;
                        adminState.uploadDocument(t.name, d, file.$1, file.$2);
                        toast(context, '$d uploaded.');
                      },
              ),
          ]),
        );
      },
    );
  }
}

class _DocUploadRow extends StatelessWidget {
  const _DocUploadRow({
    required this.label,
    required this.icon,
    required this.state,
    required this.onUpload,
    this.fileName,
    this.reason,
  });
  final String label;
  final IconData icon;
  final DocState state;

  /// Why management asked for it again.
  final String? reason;
  bool get uploaded => state == DocState.toReview || state == DocState.verified;
  final String? fileName;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final rejected = state == DocState.rejected;
    final color = switch (state) {
      DocState.verified => AppColors.emerald,
      DocState.toReview => AppColors.gold600,
      DocState.rejected => AppColors.red,
      DocState.missing => AppColors.slate400,
    };
    final status = switch (state) {
      DocState.verified => 'Verified',
      DocState.toReview => 'Sent · waiting for management to check',
      DocState.rejected => 'Please upload again',
      DocState.missing => 'Not uploaded yet',
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: state == DocState.missing ? AppColors.slate200 : color.withValues(alpha: .4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(switch (state) { DocState.verified => Icons.verified_rounded, DocState.toReview => Icons.hourglass_top_rounded, DocState.rejected => Icons.error_outline_rounded, DocState.missing => icon }, size: 22, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.green800)),
            Text(status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: state == DocState.missing ? FontWeight.w500 : FontWeight.w600,
                    color: state == DocState.missing ? AppColors.slate500 : color)),
          ]),
        ),
        PressScale(
          child: TextButton.icon(
            onPressed: onUpload,
            style: TextButton.styleFrom(
              backgroundColor: uploaded ? Colors.white : AppColors.gold500,
              foregroundColor: AppColors.green900,
              side: uploaded ? const BorderSide(color: AppColors.gold500) : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              visualDensity: VisualDensity.compact,
            ),
            icon: Icon(uploaded ? Icons.swap_horiz_rounded : Icons.upload_rounded, size: 15),
            label: Text(uploaded ? 'Replace' : rejected ? 'Upload again' : 'Upload',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
      // Why it was sent back, in full, under the row.
      if (rejected && (reason ?? '').trim().isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 10, right: 4),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: AppColors.red.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 14, color: AppColors.red.withValues(alpha: .8)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(reason!.trim(),
                  style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.slate600)),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(this.icon, this.title, this.sub, this.onTap);
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: IconBadge(icon, size: 34),
        title: Text(title,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.green800)),
        subtitle: Text(sub,
            style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
        trailing:
            const Icon(Icons.chevron_right, size: 20, color: AppColors.slate400),
      );
}

// ---------------------------------------------------------------- Deposit

class DepositScreen extends StatelessWidget {
  const DepositScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = appState;
    final deductions = s.depositLedger
        .where((e) => e.amount < 0)
        .fold<double>(0, (a, e) => a + e.amount);
    return SubPage(title: 'Security Deposit', children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: goldGradient,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('RECORDED DEPOSIT',
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800)),
          const SizedBox(height: 4),
          Text(peso(s.deposit),
              style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green900)),
          const SizedBox(height: 8),
          Text('Held in escrow for ${s.unit}',
              style: const TextStyle(fontSize: 12, color: AppColors.green800)),
        ]),
      ),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Deposit Summary',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800)),
          const SizedBox(height: 6),
          KeyValueRow('Amount received', peso(s.deposit)),
          KeyValueRow('Deductions recorded', peso(deductions.abs())),
          KeyValueRow('Refund status', 'Pending move-out', last: true),
        ]),
      ),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Documented Transactions',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800)),
          const SizedBox(height: 10),
          for (final e in s.depositLedger)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.emeraldBg,
                  child: Icon(Icons.south_west, size: 15, color: AppColors.emerald),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.label,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.green800)),
                        Text(e.date,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.slate400)),
                      ]),
                ),
                Text(peso(e.amount),
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800)),
              ]),
            ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.blueBg.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(12)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.blue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Any deduction (damages, unpaid bills) or refund will appear here with its documented reason after your move-out inspection.',
                    style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.blue)),
              ),
            ]),
          ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------- Inspections

class InspectionScreen extends StatelessWidget {
  const InspectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => SubPage(title: 'Inspection Records', children: [
        for (final i in appState.inspections)
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(i.signed ? Icons.fact_check : Icons.pending_actions_outlined,
                    color: i.signed ? AppColors.emerald : AppColors.slate400),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(i.title,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.green800)),
                        Text(i.date,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.slate500)),
                      ]),
                ),
                i.signed ? Pill.verified('SIGNED') : Pill.neutral('UPCOMING'),
              ]),
              if (i.photos > 0) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 6,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, n) => Container(
                      width: 64,
                      decoration: BoxDecoration(
                          color: AppColors.green800.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(
                          [Icons.bed, Icons.kitchen, Icons.bathtub_outlined,
                            Icons.weekend_outlined, Icons.window, Icons.door_front_door_outlined][n],
                          color: AppColors.gold600),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text('${i.photos} photos documented by management',
                    style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
              ],
              if (!i.signed) ...[
                const SizedBox(height: 10),
                const Text(
                    'Management will schedule this closer to your lease end date. You will be notified here.',
                    style: TextStyle(fontSize: 12, color: AppColors.slate500)),
              ],
            ]),
          ),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Condition Photos',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800)),
            const SizedBox(height: 4),
            Text(
                appState.interimPhotos == 0
                    ? 'Submit photos of your unit’s condition when management requests or permits it.'
                    : '${appState.interimPhotos} photo(s) submitted for review.',
                style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
            const SizedBox(height: 12),
            GoldButton(
                label: 'Submit Condition Photos',
                icon: Icons.photo_camera_outlined,
                onPressed: () => showInterimSheet(context)),
          ]),
        ),
      ]),
    );
  }
}

void showInterimSheet(BuildContext context) {
  showAppSheet(context,
      title: 'Submit Condition Photos', builder: (_) => const _InterimForm());
}

class _InterimForm extends StatefulWidget {
  const _InterimForm();
  @override
  State<_InterimForm> createState() => _InterimFormState();
}

class _InterimFormState extends State<_InterimForm> {
  final _files = <String>[];
  String _room = 'Living Room';
  static const _rooms = ['Living Room', 'Bedroom', 'Kitchen', 'Bathroom', 'Balcony'];

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const FieldLabel('Room / Area'),
      DropdownField(
          value: _room, items: _rooms, onChanged: (v) => setState(() => _room = v)),
      const SizedBox(height: 12),
      const FieldLabel('Photos'),
      AttachmentPicker(
        title: 'Take photo or select from gallery',
        hint: 'Capture all walls, floors and fixtures',
        files: _files,
        onAdd: () => setState(() => _files.add('${_room.split(' ').first.toLowerCase()}_${_files.length + 1}.jpg')),
        onRemove: (i) => setState(() => _files.removeAt(i)),
      ),
      const SizedBox(height: 16),
      GoldButton(
        label: 'Submit Photos',
        onPressed: _files.isEmpty
            ? null
            : () {
                appState.addInterimPhotos(_files.length);
                popOnce(context);
                toast(context, 'Condition photos submitted for management review.');
              },
      ),
    ]);
  }
}

// ---------------------------------------------------------------- Contact

void showContactSheet(BuildContext context) {
  showAppSheet(context,
      title: 'Update Contact Information', builder: (_) => const _ContactForm());
}

class _ContactForm extends StatefulWidget {
  const _ContactForm();
  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _key = GlobalKey<FormState>();
  late final _email = TextEditingController(text: appState.email);
  late final _phone = TextEditingController(text: appState.phone);
  late final _emergency = TextEditingController(text: appState.emergencyContact);
  late final _people = TextEditingController(text: '${appState.occupants}');

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _emergency.dispose();
    _people.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const FieldLabel('Email'),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          validator: (v) => (v ?? '').contains('@') ? null : 'Enter a valid email',
        ),
        const SizedBox(height: 12),
        const FieldLabel('Contact Number'),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          validator: (v) =>
              (v ?? '').trim().length < 7 ? 'Enter a valid phone number' : null,
        ),
        const SizedBox(height: 12),
        const FieldLabel('Emergency Contact'),
        TextFormField(controller: _emergency),
        const SizedBox(height: 12),
        const FieldLabel('Declared number of people'),
        TextFormField(
          controller: _people,
          keyboardType: TextInputType.number,
          validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? 'Enter at least 1' : null,
        ),
        const SizedBox(height: 16),
        GoldButton(
          label: 'Save Changes',
          onPressed: () {
            if (!_key.currentState!.validate()) return;
            appState.updateContact(
                _email.text.trim(), _phone.text.trim(), _emergency.text.trim(), int.tryParse(_people.text.trim()));
            popOnce(context);
            toast(context, 'Contact information updated.');
          },
        ),
      ]),
    );
  }
}
