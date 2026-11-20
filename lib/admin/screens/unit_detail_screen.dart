import 'dart:async';

import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../state/chat_state.dart';
import '../../state/sync.dart' show Sync;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';
import 'doc_review.dart';
import 'unit_scheduling.dart';
import 'monthly_expenses_sheet.dart';
import '../../state/app_state.dart' show appState;
import 'accounts_screen.dart' show AccountDetailScreen, AccountFormScreen;
import 'admin_chat_screen.dart';
import 'complaints_admin_screen.dart';
import 'contract_admin_screen.dart';
import 'cheques_screen.dart';
import 'reports_admin_screen.dart' show ReportVerificationScreen;

/// The unit's own photo if one was added, otherwise a card in the app's
/// colours with a gold icon for its type.
Widget unitImage(UnitRec u, {BoxFit fit = BoxFit.cover}) {
  final art = UnitArt(u.type);
  if (u.photo != null) {
    return Image.memory(
      u.photo!,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => art,
    );
  }
  return art;
}

/// Shown when a unit has no photo: deep green with fine gold lines, a soft
/// glow and a gold icon for the kind of place (apartment, condo or villa).
/// The icon sits high, so the name written over the bottom stays clear.
class UnitArt extends StatelessWidget {
  const UnitArt(this.type, {super.key});

  /// "Apartment", "Condo" or "Villa".
  final String type;

  IconData get _icon => switch (type) {
    'Villa' => Icons.villa_rounded,
    'Condo' => Icons.location_city_rounded,
    _ => Icons.apartment_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final h = box.maxHeight.isFinite ? box.maxHeight : 200.0;
        final w = box.maxWidth.isFinite ? box.maxWidth : 200.0;
        final size = (h < w ? h : w) * .34;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.green700, AppColors.green900],
            ),
          ),
          child: CustomPaint(
            painter: const _UnitArtPainter(),
            child: Align(
              alignment: const Alignment(0, -.3),
              child: Container(
                width: size * 1.5,
                height: size * 1.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.greenDeep.withValues(alpha: .35),
                  border: Border.all(
                    color: AppColors.gold400.withValues(alpha: .55),
                    width: 1.2,
                  ),
                ),
                child: Icon(_icon, size: size * .8, color: AppColors.gold400),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fine diagonal gold lines and a soft glow behind the icon.
class _UnitArtPainter extends CustomPainter {
  const _UnitArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * .35);
    canvas.drawCircle(
      c,
      size.shortestSide * .6,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                AppColors.gold500.withValues(alpha: .22),
                AppColors.gold500.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: c, radius: size.shortestSide * .6),
            ),
    );
    final line = Paint()
      ..color = AppColors.gold400.withValues(alpha: .07)
      ..strokeWidth = 1;
    for (var x = -size.height; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
  }

  @override
  bool shouldRepaint(_UnitArtPainter old) => false;
}

/// Full page for one unit: the photo sits at the top, then Overview / Details /
/// Tenant tabs below it.
class UnitDetailScreen extends StatefulWidget {
  const UnitDetailScreen(this.u, {super.key});
  final UnitRec u;
  @override
  State<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends State<UnitDetailScreen> {
  int _tab = 0;
  static const _tabs = ['Overview', 'Scheduling', 'Tenant'];

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    adminState.addListener(_changed);
    // The tenant's documents (shown on the Tenant tab) download now.
    Sync.fetchTenant(adminState.tenantOfUnit(widget.u.name));
  }

  @override
  void dispose() {
    adminState.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A live update replaces the records: use the current copy.
    final u =
        adminState.units
            .where(
              (x) =>
                  identical(x, widget.u) ||
                  (widget.u.id != null && x.id == widget.u.id),
            )
            .firstOrNull ??
        widget.u;
    final photoH = (MediaQuery.sizeOf(context).height * .32).clamp(
      220.0,
      420.0,
    );
    return Scaffold(
      backgroundColor: AppColors.slate50,
      body: Column(
        children: [
          SizedBox(
            height: photoH,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                unitImage(u),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x66000000),
                        Color(0x00000000),
                        Color(0xB308251E),
                      ],
                      stops: [0, .4, 1],
                    ),
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: .35),
                        ),
                        onPressed: () => popOnce(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 40,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListenableBuilder(
                        listenable: adminState,
                        builder: (_, _) => Text(
                          u.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: IconButton.filled(
                        tooltip: 'Edit unit',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: .35),
                        ),
                        onPressed: () => showAppSheet(
                          context,
                          title: 'Edit unit',
                          builder: (_) => _EditUnitForm(u),
                        ),
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.slate50,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _TabBar(
                      labels: u.type == 'Condo'
                          ? const ['Overview', 'Scheduling']
                          : _tabs,
                      index: _tab,
                      onChanged: (i) => setState(() => _tab = i),
                    ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: adminState,
                        builder: (context, _) => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: KeyedSubtree(
                            key: ValueKey(_tab),
                            child: switch (_tab) {
                              0 => _Overview(u),
                              1 => UnitScheduling(u),
                              _ => _TenantTab(u),
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.labels,
    required this.index,
    required this.onChanged,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.slate200)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onChanged(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: i == index
                              ? AppColors.gold500
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: i == index
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: i == index
                            ? AppColors.green800
                            : AppColors.slate400,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lets the admin change everything about the unit in one place.
class _EditUnitForm extends StatefulWidget {
  const _EditUnitForm(this.u);
  final UnitRec u;
  @override
  State<_EditUnitForm> createState() => _EditUnitFormState();
}

class _EditUnitFormState extends State<_EditUnitForm> {
  static const _types = ['Apartment', 'Condo', 'Villa'];
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.u.name);
  late final _rate = TextEditingController(text: _plain(widget.u.rate));
  late final _deposit = TextEditingController(text: _plain(widget.u.deposit));
  late String _type = widget.u.type;

  /// Set by the type: condo per night, apartment per month, villa per year.
  String get _unit => ratePeriodFor(_type);
  late int _beds = widget.u.bedrooms;

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _deposit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Unit name'),
          TextFormField(
            controller: _name,
            validator: (v) => (v ?? '').trim().isEmpty
                ? 'Enter a unit name'
                : adminState.unitNameTaken(v!, except: widget.u)
                ? 'A unit with this name already exists'
                : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Type'),
          DropdownField(
            value: _type,
            items: _types,
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Bedrooms'),
          DropdownField(
            value: bedroomLabel(_beds),
            items: [for (var i = 0; i <= 6; i++) bedroomLabel(i)],
            onChanged: (v) => setState(() => _beds = bedroomCount(v)),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FieldLabel('Rate (${currencySign(_type == 'Villa')})'),
                    TextFormField(
                      controller: _rate,
                      keyboardType: TextInputType.number,
                      validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                          ? 'Enter a rate'
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Per'),
                    // Fixed by the type, so it is shown, not picked.
                    InputDecorator(
                      decoration: const InputDecoration(),
                      child: Text(
                        _unit,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.green800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // A unit saved before the lock may be priced another way: the
          // rate must be checked, since it now counts per night/month/year.
          if (widget.u.rateUnit != _unit)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This unit was priced per ${widget.u.rateUnit}. '
                'Make sure the rate above is the amount per $_unit.',
                style: const TextStyle(fontSize: 12, color: AppColors.amber),
              ),
            ),
          const SizedBox(height: 12),
          FieldLabel('Security deposit (${currencySign(_type == 'Villa')})'),
          TextFormField(
            controller: _deposit,
            keyboardType: TextInputType.number,
            validator: (v) =>
                (double.tryParse(v ?? '') ?? -1) < 0 ? 'Enter a deposit' : null,
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: 'Save changes',
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              adminState.updateUnit(
                widget.u,
                name: _name.text.trim(),
                type: _type,
                bedrooms: _beds,
                rate: double.parse(_rate.text),
                rateUnit: _unit,
                deposit: double.parse(_deposit.text),
              );
              popOnce(context);
              toast(context, 'Unit updated');
            },
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- Tenant

class _TenantTab extends StatelessWidget {
  const _TenantTab(this.u);
  final UnitRec u;

  @override
  Widget build(BuildContext context) {
    final t = adminState.tenants.where((t) => t.unit == u.name).firstOrNull;

    if (t != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.gold500,
                child: Icon(Icons.person, color: AppColors.green900),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  t.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow('Stay type', t.stayType),
          _InfoRow('Email', t.email),
          _InfoRow('Contact number', t.phone),
          _InfoRow(
            'Declared occupants',
            '${t.occupants} ${t.occupants == 1 ? 'person' : 'people'}',
          ),
          for (final d in adminState.requiredDocs(t)) DocReviewRow(t, d),
          const SizedBox(height: 14),
          // Lease dates and terms plus the contract PDF, as the tenant sees them.
          GoldButton(
            label: t.contractName == null
                ? 'Assign contract'
                : 'Contract & lease',
            icon: Icons.picture_as_pdf_outlined,
            onPressed: () => push(context, ContractAdminScreen(t)),
          ),
          const SizedBox(height: 10),
          GoldButton(
            label: 'Open account',
            icon: Icons.menu_book_outlined,
            onPressed: () => push(context, AccountDetailScreen(t)),
          ),
          const SizedBox(height: 10),
          if (adminState.isVilla(t.name)) ...[
            GoldButton(
              label: 'Cheques',
              icon: Icons.payments_outlined,
              onPressed: () =>
                  push(context, ChequesScreen(t.name, admin: true)),
            ),
            const SizedBox(height: 10),
          ],
          ListenableBuilder(
            listenable: chatState,
            builder: (_, _) {
              final unread = chatState.unread(ChatSender.admin, t.name);
              return GoldButton(
                label: unread > 0 ? 'Chats ($unread new)' : 'Chats',
                icon: Icons.chat_bubble_outline_rounded,
                onPressed: () => push(context, AdminChatScreen(t)),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _OutlineAction(
                  icon: Icons.notifications_active_outlined,
                  label: 'Notify pendings',
                  onTap: () => showAppSheet(
                    context,
                    title: 'Notify pendings',
                    builder: (_) => _PendingsSheet(t, u),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlineAction(
                  icon: Icons.edit_note_rounded,
                  label: 'Give notice',
                  onTap: () => showAppSheet(
                    context,
                    title: 'Give notice',
                    builder: (_) => _GiveNoticeSheet(t, u),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      children: [
        const Icon(
          Icons.person_off_outlined,
          size: 44,
          color: AppColors.slate300,
        ),
        const SizedBox(height: 10),
        const Text(
          'No tenant yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.green800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Assign a tenant who already has an account, or create a new one.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: AppColors.slate500),
        ),
        const SizedBox(height: 18),
        GoldButton(
          label: 'Assign tenant',
          icon: Icons.person_add_alt_1_outlined,
          onPressed: () => _assign(context),
        ),
      ],
    );
  }

  static const _newAccount = '\u0000new';

  /// Pick one of the accounts that has no unit yet, or start a new account.
  Future<void> _assign(BuildContext context) async {
    final ready = adminState.tenants.where((t) => t.unit.isEmpty).toList();
    final choice = await showPicker(
      context,
      title: 'Assign tenant',
      options: [
        for (final t in ready)
          PickerOption(
            value: t.username,
            label: t.name,
            subtitle: 'Account ready, no unit yet',
            icon: Icons.person_outline,
            group: 'Ready accounts',
          ),
        const PickerOption(
          value: _newAccount,
          label: 'Create a new account',
          subtitle: 'For someone who has no account yet',
          icon: Icons.add,
          group: 'New',
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    if (choice == _newAccount) {
      push(context, AccountFormScreen(presetUnit: u.name));
      return;
    }
    final t = ready.firstWhere((t) => t.username == choice);
    adminState.updateAccount(
      t,
      name: t.name,
      unit: u.name,
      deposit: u.deposit,
      username: t.username,
      password: t.password,
    );
    toast(context, '${t.name} assigned to ${u.name}');
  }
}

/// Secondary action: white with a gold outline, so it sits under the gold buttons.
class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.green800,
          side: const BorderSide(color: AppColors.gold500, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: AppColors.gold600),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

/// Reminds this unit's tenant of what they owe: the latest due and the total.
/// The admin picks what it is about: everything, rent only, or the other
/// charges only.
class _PendingsSheet extends StatefulWidget {
  const _PendingsSheet(this.t, this.u);
  final TenantRec t;
  final UnitRec u;

  @override
  State<_PendingsSheet> createState() => _PendingsSheetState();
}

class _PendingsSheetState extends State<_PendingsSheet> {
  /// 0 all dues, 1 rent only, 2 other charges only.
  int _what = 0;

  @override
  Widget build(BuildContext context) {
    final t = widget.t, u = widget.u;
    final all = adminState.unpaidFor(t.name);
    if (all.isEmpty) {
      // Full width, so it sits in the middle of the sheet.
      return const SizedBox(
        width: double.infinity,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(Icons.task_alt_rounded, size: 40, color: AppColors.emerald),
              SizedBox(height: 8),
              Text(
                'No pending dues',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'This tenant has nothing unpaid right now.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.slate500),
              ),
            ],
          ),
        ),
      );
    }
    final rent = all.where(adminState.isRentCharge).toList();
    final other = all.where((c) => !adminState.isRentCharge(c)).toList();
    // The choice only matters when there is some of each.
    final choose = rent.isNotEmpty && other.isNotEmpty;
    final what = choose ? _what : 0;
    final unpaid = switch (what) {
      1 => rent,
      2 => other,
      _ => all,
    };
    final latest = unpaid.first;
    final total = unpaid.fold<double>(0, (a, c) => a + c.remaining);
    final count = unpaid.length;
    final title = switch (what) {
      1 => 'Rent reminder',
      2 => 'Charges reminder',
      _ => 'Payment reminder',
    };
    final body =
        'Latest due: ${latest.title}, ${peso(latest.remaining, dhs: u.type == 'Villa')}, due ${latest.due}.\n'
        'Total unpaid: ${peso(total, dhs: u.type == 'Villa')} ($count ${count == 1 ? 'charge' : 'charges'}).\n'
        'Please settle your balance and upload your proof of payment in the app.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (choose) ...[
          const FieldLabel('Remind about'),
          SegmentedTabs(
            light: true,
            labels: [
              'All dues',
              'Rent (${rent.length})',
              'Charges (${other.length})',
            ],
            index: what,
            onChanged: (i) => setState(() => _what = i),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Expanded(
              child: _DueBox(
                'Latest due',
                peso(latest.remaining, dhs: u.type == 'Villa'),
                '${latest.title} · ${latest.due}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DueBox(
                'Total dues',
                peso(total, dhs: u.type == 'Villa'),
                '$count unpaid ${count == 1 ? 'charge' : 'charges'}',
                highlight: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const FieldLabel('Message preview'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.slate50,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.slate600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${t.name} gets this as a notice and a pop-up when they open the app.',
          style: const TextStyle(fontSize: 12, color: AppColors.slate500),
        ),
        const SizedBox(height: 16),
        GoldButton(
          label: 'Send to ${u.name}',
          icon: Icons.send_rounded,
          onPressed: () {
            adminState.notifyTenant(t, title, body, automatic: false);
            popOnce(context);
            toast(context, '$title sent to ${t.name}');
          },
        ),
      ],
    );
  }
}

class _DueBox extends StatelessWidget {
  const _DueBox(this.label, this.value, this.sub, {this.highlight = false});
  final String label, value, sub;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.red.withValues(alpha: .07)
            : AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? AppColors.red.withValues(alpha: .3)
              : AppColors.slate200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.slate500,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: highlight ? AppColors.red : AppColors.green800,
              ),
            ),
          ),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.slate500),
          ),
        ],
      ),
    );
  }
}

/// A notice with the admin's own subject and description, for this unit only.
class _GiveNoticeSheet extends StatefulWidget {
  const _GiveNoticeSheet(this.t, this.u);
  final TenantRec t;
  final UnitRec u;
  @override
  State<_GiveNoticeSheet> createState() => _GiveNoticeSheetState();
}

class _GiveNoticeSheetState extends State<_GiveNoticeSheet> {
  final _key = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Subject'),
          TextFormField(
            controller: _subject,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Unit inspection on Friday',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter a subject' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Description'),
          TextFormField(
            controller: _body,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter a description' : null,
          ),
          const SizedBox(height: 8),
          Text(
            'Only ${widget.t.name} (${widget.u.name}) receives this.',
            style: const TextStyle(fontSize: 12, color: AppColors.slate500),
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: 'Send to ${widget.u.name}',
            icon: Icons.send_rounded,
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              adminState.notifyTenant(
                widget.t,
                _subject.text.trim(),
                _body.text.trim(),
                automatic: false,
              );
              popOnce(context);
              toast(context, 'Notice sent to ${widget.t.name}');
            },
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Overview

/// Everything happening in this unit: money, reports and recent activity.
/// A condo's Status card: label, big value and the line under it. Shows the
/// next check-in date instead of "Reserved", the check-out while a guest is
/// in, or the latest check-in when nothing is coming up.
(String, String, String) _condoStay(UnitRec u) {
  String day(DateTime d) => stayMoment(d).split(' · ').first;
  final now = adminState.currentBooking(u.name);
  if (now != null) {
    return (
      'Staying now',
      'Until ${day(now.checkOut)}',
      'check-out ${clockTime(now.checkOut)}',
    );
  }
  final next = adminState.nextBooking(u.name);
  if (next != null) {
    return ('Next check-in', day(next.checkIn), clockTime(next.checkIn));
  }
  final last = adminState.bookingsFor(u.name).lastOrNull;
  return (
    'Status',
    'Free',
    last == null ? 'no stays yet' : 'last check-in ${day(last.checkIn)}',
  );
}

class _Overview extends StatelessWidget {
  const _Overview(this.u);
  final UnitRec u;

  @override
  Widget build(BuildContext context) {
    final s = adminState;
    final t = s.tenants.where((t) => t.unit == u.name).firstOrNull;
    final name = t?.name ?? u.tenant;
    final payments = name == null
        ? <PaymentRec>[]
        : s.payments.where((p) => p.tenant == name).toList();
    final reports = s.reports.where((r) => r.unit == u.name).toList();
    final requests = name == null
        ? <LeaseRequest>[]
        : s.requests.where((r) => r.tenant == name).toList();
    final openReports = reports
        .where((r) => r.status != ReportStatus.approved)
        .length;
    final condo = u.type == 'Condo';

    final activity = <(IconData, String, String)>[
      for (final p in payments)
        (
          p.status == PayStatus.verified
              ? Icons.check_circle_outline
              : Icons.receipt_long_outlined,
          '${p.title} · ${peso(p.amount, dhs: u.type == 'Villa')}',
          '${p.status == PayStatus.submitted
              ? 'Waiting for verification'
              : p.status == PayStatus.verified
              ? 'Verified'
              : 'Rejected'} · ${p.date}',
        ),
      for (final r in reports)
        (Icons.build_outlined, r.issue, 'Damage report · ${r.date}'),
      for (final r in requests)
        (Icons.autorenew_rounded, r.kind, 'Lease request · ${r.date}'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      children: [
        GridView.count(
          padding: EdgeInsets.zero,
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _Mini(
              'Rate',
              peso(u.rate, dhs: u.type == 'Villa'),
              'per ${u.rateUnit}',
              Icons.sell_outlined,
            ),
            // The security deposit is kept untouched and returned at move-out,
            // minus any documented damage. Same as the rate for now.
            // Condos: the deposit of the guest staying now (tap to take some
            // off it); nothing while no one is in.
            if (condo)
              _Mini(
                'Deposit',
                s.currentBooking(u.name) == null
                    ? '-'
                    : peso(s.currentBooking(u.name)!.depositLeft),
                s.currentBooking(u.name) == null
                    ? 'no guest staying'
                    : 'held · tap to deduct',
                Icons.savings_outlined,
                onTap: s.currentBooking(u.name) == null
                    ? null
                    : () => showAppSheet(
                        context,
                        title: 'Security deposit',
                        builder: (_) => DepositSheet(s.currentBooking(u.name)!),
                      ),
              )
            else
              _Mini(
                'Deposit',
                peso(u.deposit, dhs: u.type == 'Villa'),
                t == null ? 'due on move-in' : 'held · refundable',
                Icons.savings_outlined,
              ),
            // Status is never set by hand: condos follow their bookings,
            // apartments and villas follow the tenant's lease (Occupied once
            // it starts, Reserved before, Vacant with no tenant).
            _Mini(
              condo ? _condoStay(u).$1 : 'Status',
              condo ? _condoStay(u).$2 : _statusLabel(u.status),
              condo ? _condoStay(u).$3 : (u.tenant ?? 'no tenant'),
              Icons.info_outline_rounded,
            ),
            if (condo)
              _Mini(
                'Operational cost',
                peso(s.costsInMonth(u.name, appState.today)),
                'this month · tap to add',
                Icons.receipt_long_outlined,
                onTap: () => showAppSheet(
                  context,
                  title: 'Operational cost · ${u.name}',
                  builder: (_) => CostsSheet(u),
                ),
              )
            else
              _Mini(
                'Payment status',
                switch (t == null ? null : s.rentPaidUntil(t)) {
                  final d? => _paidUntil(d),
                  null => '-',
                },
                t == null
                    ? 'no tenant'
                    : s.rentPaidUntil(t) == null
                    ? 'No rent paid yet'
                    : 'rent paid until',
                Icons.event_available_outlined,
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Condos: damage taken off guests' deposits (unit details are
        // under the pencil at the top, for every unit).
        if (condo) ...[
          _LinkRow(
            icon: Icons.report_problem_outlined,
            label: 'Damage occurred',
            open: s.deductionsIn(u.name, appState.today).length,
            total: 0,
            showCount: false,
            onTap: () => showAppSheet(
              context,
              title: 'Damage occurred · ${u.name}',
              builder: (_) => DamageSheet(u),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // Apartments and condos: what the unit costs every month (internet,
        // Netflix...), taken off profit in Finance.
        if (u.type == 'Apartment' || u.type == 'Condo') ...[
          _LinkRow(
            icon: Icons.receipt_long_outlined,
            label: 'Monthly expenses',
            open: 0,
            total: 0,
            value: '${peso(s.monthlyTotal(u.name))} /mo',
            onTap: () => showAppSheet(
              context,
              title: 'Monthly expenses · ${u.name}',
              builder: (_) => MonthlyExpensesSheet(u.name),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _ConditionRow(u),
        const SizedBox(height: 10),
        // Maintenance and damage reports for this unit only.
        _LinkRow(
          icon: Icons.build_outlined,
          label: 'Unresolved reports',
          open: openReports,
          total: reports.length,
          onTap: () => push(context, ReportVerificationScreen(unit: u.name)),
        ),
        const SizedBox(height: 10),
        // Complaints from this unit's tenant (condos have no tenant account).
        if (!condo)
          _LinkRow(
            icon: Icons.report_gmailerrorred_outlined,
            label: 'Complaints',
            open: s.complaints
                .where(
                  (c) =>
                      c.unit == u.name && c.status != ComplaintStatus.resolved,
                )
                .length,
            total: s.complaints.where((c) => c.unit == u.name).length,
            onTap: () => push(context, ComplaintsAdminScreen(unit: u.name)),
          ),
        const SizedBox(height: 10),
        _DeleteUnitRow(u),
        if (!condo && t != null && t.daysLeft <= 90) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.amberBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE8D5A0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule, size: 18, color: AppColors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lease ends ${t.leaseEnd} (${t.daysLeft} days left)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.amber,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        // Condos: a month calendar of booked and free nights. Others: what
        // happened in the unit.
        if (condo)
          CondoCalendar(u)
        else ...[
          const Text(
            'Recent activity',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.green800,
            ),
          ),
          const SizedBox(height: 4),
          if (activity.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nothing has happened in this unit yet.',
                style: TextStyle(fontSize: 13, color: AppColors.slate500),
              ),
            ),
          for (final a in activity)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: IconBadge(a.$1, size: 34),
              title: Text(
                a.$2,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              subtitle: Text(
                a.$3,
                style: const TextStyle(fontSize: 12, color: AppColors.slate500),
              ),
            ),
        ],
      ],
    );
  }
}

/// A tappable row with a label and "N of M total" (N in red when above 0).
/// "Delete unit" at the bottom of the overview. Deleting archives the unit:
/// it leaves the lists, but its history stays for Finance and reports.
class _DeleteUnitRow extends StatelessWidget {
  const _DeleteUnitRow(this.u);
  final UnitRec u;

  Future<void> _delete(BuildContext context) async {
    final why = adminState.whyKeepUnit(u);
    if (why != null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Can't delete yet"),
          content: Text(why),
          actions: [
            TextButton(onPressed: () => popOnce(ctx), child: const Text('OK')),
          ],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CountdownConfirm(
        title: 'Delete ${u.name}?',
        message:
            '${u.name} will be removed from your units. Its payments, stays, '
            'reports and costs are kept, so your Finance numbers and PDF '
            'reports stay complete.',
        action: 'Yes, delete',
      ),
    );
    if (ok != true || !context.mounted) return;
    adminState.deleteUnit(u);
    popOnce(context);
    toast(context, '${u.name} deleted');
  }

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: .985,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _delete(context),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.red.withValues(alpha: .35)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.red,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Delete unit',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.red,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.slate400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Are you sure?" with the confirm button locked for 5 seconds, so a
/// delete is never done in a hurry.
class _CountdownConfirm extends StatefulWidget {
  const _CountdownConfirm({
    required this.title,
    required this.message,
    required this.action,
  });
  final String title, message, action;

  @override
  State<_CountdownConfirm> createState() => _CountdownConfirmState();
}

class _CountdownConfirmState extends State<_CountdownConfirm> {
  int _left = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _left <= 0;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.green800,
        ),
      ),
      content: Text(
        widget.message,
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: AppColors.slate600,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => popOnce(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.slate200,
            disabledForegroundColor: AppColors.slate500,
          ),
          onPressed: ready ? () => popOnce(context, true) : null,
          child: Text(
            ready ? widget.action : '${widget.action} ($_left)',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.open,
    required this.total,
    required this.onTap,
    this.showCount = true,
    this.value,
  });

  /// Shown on the right instead of the count (e.g. a monthly total).
  final String? value;

  /// False for a plain button row without "N of M total".
  final bool showCount;
  final IconData icon;
  final String label;
  final int open, total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: .985,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.gold600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.slate500,
                    ),
                  ),
                ),
                if (value != null)
                  Text(
                    value!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  )
                else if (showCount)
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$open',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: open > 0 ? AppColors.red : AppColors.emerald,
                          ),
                        ),
                        TextSpan(
                          text: '  of $total total',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.slate400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, this.sub, this.icon, {this.onTap});
  final String label, value, sub;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Only the cards that open something (Status) sink when pressed.
    return PressScale(
      enabled: onTap != null,
      scale: .975,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.slate200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: AppColors.gold600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.slate500,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      const Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: AppColors.slate400,
                      ),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _statusLabel(UnitStatus s) => switch (s) {
  UnitStatus.vacant => 'Vacant',
  UnitStatus.reserved => 'Reserved',
  UnitStatus.occupied => 'Occupied',
};

const _months = [
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

String _day(DateTime d) => '${_months[d.month - 1]} ${d.day}';

/// "Sep 30, 2026": the last day that is paid for.
String _paidUntil(DateTime until) => '${_day(until)}, ${until.year}';

// -------------------------------------------------------------- Documents

/// A plain info row that matches the document rows (same size, weight, divider).
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.green800,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.green800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- Condition

String _conditionLabel(UnitCondition c) => switch (c) {
  UnitCondition.good => 'Ready for occupancy',
  UnitCondition.underMaintenance => 'Under maintenance',
  UnitCondition.underRepair => 'Under repair',
  UnitCondition.underModification => 'Under modification',
};

Color _conditionColor(UnitCondition c) => switch (c) {
  UnitCondition.good => AppColors.emerald,
  UnitCondition.underMaintenance => AppColors.gold600,
  UnitCondition.underRepair => AppColors.red,
  UnitCondition.underModification => AppColors.amber,
};

/// Condition of the unit itself, set by the schedule: Under repair or Under
/// maintenance while such work is on in the unit, Ready for occupancy
/// otherwise. Independent of the occupancy status, so a unit can be occupied
/// and under repair.
class _ConditionRow extends StatelessWidget {
  const _ConditionRow(this.u);
  final UnitRec u;

  @override
  Widget build(BuildContext context) {
    final color = _conditionColor(u.condition);
    final job = adminState.activeWork(u);
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
      'Dec',
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.home_repair_service_outlined,
                size: 18,
                color: AppColors.gold600,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Condition',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate500,
                  ),
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                _conditionLabel(u.condition),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
            ],
          ),
          // Which job makes it so, and until when.
          if (job != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 6),
              child: Text(
                '${job.title} · until ${months[job.endDate.month - 1]} ${job.endDate.day}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.gold700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
