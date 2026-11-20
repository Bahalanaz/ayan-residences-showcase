import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../screens/shell.dart' show SubPage;
import '../../state/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

/// Announcements sent to every tenant, plus the house rules they can read.
class NoticesAdminScreen extends StatefulWidget {
  const NoticesAdminScreen({super.key});
  @override
  State<NoticesAdminScreen> createState() => _NoticesAdminScreenState();
}

class _NoticesAdminScreenState extends State<NoticesAdminScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([adminState, appState]),
      builder: (context, _) => SubPage(
        title: 'Announcements',
        bottom: _tab == 0
            ? GoldButton(
                label: 'New announcement',
                icon: Icons.campaign_rounded,
                onPressed: () => showAppSheet(
                  context,
                  title: 'New announcement',
                  builder: (_) => const _NoticeForm(),
                ),
              )
            : GoldButton(
                label: 'Add a rule',
                icon: Icons.add,
                onPressed: () => showAppSheet(
                  context,
                  title: 'New rule',
                  builder: (_) => const _RuleForm(null),
                ),
              ),
        children: [
          SegmentedTabs(
            labels: const ['Announcements', 'House rules'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          if (_tab == 0) ..._announcements(context) else ..._rules(context),
        ],
      ),
    );
  }

  // ------------------------------------------------------- Announcements

  List<Widget> _announcements(BuildContext context) {
    final list = adminState.announcements;
    final read = list.fold<int>(0, (a, n) => a + n.read);
    final total = list.fold<int>(0, (a, n) => a + n.total);
    return [
      AppCard(
        radius: 22,
        child: Row(
          children: [
            _Stat('${list.length}', 'Published'),
            _divider(),
            _Stat('${total - read}', 'Unread'),
          ],
        ),
      ),
      if (list.isEmpty)
        const EmptyState(
          icon: Icons.campaign_outlined,
          title: 'No announcements yet',
          message: 'Tap New announcement to send one to every tenant.',
        ),
      for (final n in list) _NoticeCard(n),
    ];
  }

  static Widget _divider() =>
      Container(width: 1, height: 34, color: AppColors.slate200);

  // ---------------------------------------------------------- House rules

  List<Widget> _rules(BuildContext context) {
    final rules = appState.rules;
    return [
      AppCard(
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                IconBadge(Icons.menu_book_outlined, size: 38),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Policy handbook',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.green800,
                        ),
                      ),
                      Text(
                        'Tenants see these under Notices > House Rules.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      for (var i = 0; i < rules.length; i++) _RuleCard(i + 1, rules[i]),
    ];
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final String value, label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.green800,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.slate500),
        ),
      ],
    ),
  );
}

// --------------------------------------------------------- Announcement card

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(this.n, {this.tappable = true});
  final AdminNotice n;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final done = n.total > 0 && n.read == n.total;
    return AppCard(
      radius: 20,
      onTap: tappable ? () => push(context, _ReadersScreen(n)) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(Icons.campaign_outlined, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      n.to != null
                          ? '${n.date} · to ${n.to}'
                          : n.unitTypes == null
                          ? n.date
                          : '${n.date} · ${n.unitTypes!.length == 3 ? 'All tenants' : n.unitTypes!.map((t) => '${t}s').join(' & ')}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.slate500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      n.body,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.slate600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.slate50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  done ? Icons.done_all_rounded : Icons.visibility_outlined,
                  size: 16,
                  color: done ? AppColors.emerald : AppColors.gold600,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: n.total == 0 ? 0 : n.read / n.total,
                      minHeight: 6,
                      backgroundColor: AppColors.slate200,
                      color: done ? AppColors.emerald : AppColors.gold500,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  done ? 'Everyone read it' : '${n.read}/${n.total} read',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.slate600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ Who read it

class _ReadersScreen extends StatefulWidget {
  const _ReadersScreen(this.n);
  final AdminNotice n;
  @override
  State<_ReadersScreen> createState() => _ReadersScreenState();
}

class _ReadersScreenState extends State<_ReadersScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final n = widget.n;
        final names = n.recipients.toList()
          ..sort((a, b) {
            final r =
                (n.readBy.contains(a) ? 1 : 0) - (n.readBy.contains(b) ? 1 : 0);
            return r != 0 ? r : a.compareTo(b);
          });
        final shown = names.where(
          (name) => switch (_tab) {
            1 => n.readBy.contains(name),
            2 => !n.readBy.contains(name),
            _ => true,
          },
        );
        return SubPage(
          title: 'Who read it',
          children: [
            _NoticeCard(n, tappable: false),
            SegmentedTabs(
              labels: [
                'All ${n.total}',
                'Read ${n.read}',
                'Unread ${n.total - n.read}',
              ],
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            for (final name in shown)
              _ReaderTile(name, n.readBy.contains(name)),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Nobody here.',
                    style: TextStyle(color: AppColors.slate300),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ReaderTile extends StatelessWidget {
  const _ReaderTile(this.name, this.read);
  final String name;
  final bool read;

  @override
  Widget build(BuildContext context) {
    final t = adminState.tenants.where((t) => t.name == name).firstOrNull;
    final unit = t == null
        ? null
        : adminState.units.where((u) => u.name == t.unit).firstOrNull;
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          IconBadge(
            unit?.type == 'Villa'
                ? Icons.villa_outlined
                : Icons.apartment_rounded,
            size: 38,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                Text(
                  unit == null ? 'No unit' : '${unit.name} · ${unit.type}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
          read ? Pill.verified('READ') : Pill.pending('NOT YET'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Rule card

class _RuleCard extends StatelessWidget {
  const _RuleCard(this.number, this.rule);
  final int number;
  final HouseRule rule;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 20,
      onTap: () => showAppSheet(
        context,
        title: 'Edit rule',
        builder: (_) => _RuleForm(rule),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              gradient: goldGradient,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.green900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  rule.body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.slate600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.edit_outlined, size: 16, color: AppColors.slate400),
        ],
      ),
    );
  }
}

class _RuleForm extends StatefulWidget {
  const _RuleForm(this.rule);

  /// Null when adding a new rule.
  final HouseRule? rule;
  @override
  State<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends State<_RuleForm> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.rule?.title ?? '');
  late final _body = TextEditingController(text: widget.rule?.body ?? '');

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rule;
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Title'),
          TextFormField(
            controller: _title,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a title' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Rule'),
          TextFormField(
            controller: _body,
            maxLines: 5,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter the rule' : null,
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: r == null ? 'Add rule' : 'Save changes',
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              appState.saveRule(r, _title.text.trim(), _body.text.trim());
              popOnce(context);
              toast(context, r == null ? 'Rule added' : 'Rule updated');
            },
          ),
          if (r != null) ...[
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  appState.deleteRule(r);
                  popOnce(context);
                  toast(context, 'Rule removed');
                },
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: AppColors.red,
                ),
                label: const Text(
                  'Remove this rule',
                  style: TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------ New announcement

class _NoticeForm extends StatefulWidget {
  const _NoticeForm();
  @override
  State<_NoticeForm> createState() => _NoticeFormState();
}

class _NoticeFormState extends State<_NoticeForm> {
  final _key = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();

  /// Unit types it goes to; apartments and villas by default.
  final Set<String> _types = {'Apartment', 'Villa'};

  @override
  void dispose() {
    _title.dispose();
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
          const FieldLabel('Title'),
          TextFormField(
            controller: _title,
            validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a title' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Message'),
          TextFormField(
            controller: _body,
            maxLines: 4,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter a message' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Who should get it?'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (type, label, icon) in const [
                ('Apartment', 'Apartments', Icons.apartment_rounded),
                ('Villa', 'Villas', Icons.villa_outlined),
              ])
                FilterChip(
                  avatar: Icon(
                    icon,
                    size: 16,
                    color: _types.contains(type)
                        ? AppColors.green900
                        : AppColors.slate500,
                  ),
                  label: Text(label),
                  selected: _types.contains(type),
                  showCheckmark: false,
                  selectedColor: AppColors.gold500,
                  backgroundColor: AppColors.slate50,
                  side: BorderSide(
                    color: _types.contains(type)
                        ? AppColors.gold500
                        : AppColors.slate200,
                  ),
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _types.contains(type)
                        ? AppColors.green900
                        : AppColors.slate600,
                  ),
                  onSelected: (on) => setState(
                    () => on ? _types.add(type) : _types.remove(type),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _types.isEmpty
                ? 'Pick at least one.'
                : '${adminState.tenantsOfTypes(_types).length} tenants get a notification and must mark it as read.',
            style: TextStyle(
              fontSize: 12,
              color: _types.isEmpty ? AppColors.red : AppColors.slate500,
            ),
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: _types.length == 2
                ? 'Publish to all tenants'
                : _types.isEmpty
                ? 'Publish'
                : 'Publish to ${[
                    for (final t in const ['Apartment', 'Villa'])
                      if (_types.contains(t)) '${t.toLowerCase()}s',
                  ].join(' & ')}',
            onPressed: _types.isEmpty
                ? null
                : () {
                    if (!_key.currentState!.validate()) return;
                    adminState.publishNotice(
                      _title.text.trim(),
                      _body.text.trim(),
                      NoticeKind.general,
                      types: {..._types},
                    );
                    popOnce(context);
                    toast(context, 'Announcement published');
                  },
          ),
        ],
      ),
    );
  }
}
