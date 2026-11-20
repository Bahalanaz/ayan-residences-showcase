import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../state/app_state.dart' show ReportType;
import '../../screens/shell.dart' show SubPage;
import '../../state/sync.dart' show Sync;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/chat_view.dart' show choosePhoto;
import '../admin_state.dart';
import 'maintenance_admin_screen.dart' show ScheduleForm;

Widget _statusPill(ReportStatus s) => switch (s) {
  ReportStatus.pending => Pill.pending('PENDING'),
  ReportStatus.underReview => Pill.info('UNDER REVIEW'),
  ReportStatus.approved => Pill.verified('APPROVED'),
};

/// Maintenance (routine fixing) or Damage (broken, needs classifying).
Widget _typePill(ReportType t) => switch (t) {
  ReportType.maintenance => Pill.neutral('MAINTENANCE'),
  ReportType.damage => Pill.urgent('DAMAGE'),
  ReportType.modification => Pill.info('MODIFICATION'),
};

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen(this.r, {super.key});
  final DamageReport r;
  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  @override
  void initState() {
    super.initState();
    // The report's photos download now.
    Sync.fetch([widget.r]);
  }

  late ReportStatus _status = widget.r.status;
  late DamageKind? _kind = widget.r.kind;
  final _update = TextEditingController();

  @override
  void dispose() {
    _update.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    const statusLabels = {
      ReportStatus.pending: 'Pending',
      ReportStatus.underReview: 'Under review',
      ReportStatus.approved: 'Approved',
    };
    return ListenableBuilder(
      listenable: adminState,
      // A live update replaces the records: use the current copy.
      builder: (context, _) => _page(
        context,
        adminState.reports.where((x) => x.id == r.id).firstOrNull ?? r,
        statusLabels,
      ),
    );
  }

  Widget _page(
    BuildContext context,
    DamageReport r,
    Map<ReportStatus, String> statusLabels,
  ) {
    return SubPage(
      title: r.id,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(alignment: Alignment.centerLeft, child: _typePill(r.type)),
              const SizedBox(height: 8),
              Text(
                r.issue,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                r.description,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.slate600,
                ),
              ),
              const SizedBox(height: 10),
              KeyValueRow('Tenant', r.tenant),
              KeyValueRow('Unit', r.unit),
              KeyValueRow('Reported', r.date, last: true),
              const SizedBox(height: 8),
              // Photos the admin attached: the real pictures, tap to enlarge.
              if (r.photoFiles.isNotEmpty)
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: r.photoFiles.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (_) => Dialog(
                          clipBehavior: Clip.antiAlias,
                          child: InteractiveViewer(
                            child: Image.memory(r.photoFiles[i]),
                          ),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          r.photoFiles[i],
                          width: 84,
                          height: 84,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    for (
                      var i = 0;
                      i < (r.attachments == 0 ? 1 : r.attachments.clamp(1, 3));
                      i++
                    )
                      Container(
                        width: 72,
                        height: 72,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppColors.slate100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          r.attachments == 0
                              ? Icons.image_not_supported_outlined
                              : Icons.image_outlined,
                          color: AppColors.gold600,
                        ),
                      ),
                    if (r.attachments > 0)
                      Text(
                        '${r.attachments} photo/video',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate500,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        // Progress notes the tenant reads on their report ("Plumber booked...").
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Progress updates',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${r.tenant} sees these on their report.',
                style: const TextStyle(fontSize: 12, color: AppColors.slate500),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _update,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Plumber booked for Friday 9 AM',
                ),
              ),
              const SizedBox(height: 10),
              GoldButton(
                label: 'Post update',
                icon: Icons.send_rounded,
                compact: true,
                onPressed: () {
                  final text = _update.text.trim();
                  if (text.isEmpty) return;
                  adminState.postReportUpdate(r, text);
                  _update.clear();
                  toast(context, 'Update posted');
                },
              ),
              for (final u in r.updates) ...[
                const Divider(height: 22),
                Text(
                  u.text,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.green800,
                  ),
                ),
                Text(
                  u.date,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.slate400,
                  ),
                ),
              ],
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verification',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800,
                ),
              ),
              const SizedBox(height: 10),
              const FieldLabel('Status shown to the tenant'),
              DropdownField(
                value: statusLabels[_status]!,
                items: statusLabels.values.toList(),
                onChanged: (v) => setState(
                  () => _status = statusLabels.entries
                      .firstWhere((e) => e.value == v)
                      .key,
                ),
              ),
              // Only damage is classified (accident or intentional) and can lead to
              // a deposit deduction; routine maintenance never does.
              if (r.type == ReportType.damage) ...[
                const SizedBox(height: 12),
                const FieldLabel('Classification'),
                Row(
                  children: [
                    Expanded(
                      child: _KindChip(
                        'Accident',
                        _kind == DamageKind.accident,
                        () => setState(() => _kind = DamageKind.accident),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _KindChip(
                        'Intentional',
                        _kind == DamageKind.intentional,
                        () => setState(() => _kind = DamageKind.intentional),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              GoldButton(
                label: 'Save verification',
                onPressed: () {
                  adminState.saveReport(
                    r,
                    _status,
                    r.type == ReportType.damage ? _kind : null,
                    r.deduction,
                    r.note,
                  );
                  popOnce(context);
                  toast(context, 'Report updated');
                },
              ),
              const SizedBox(height: 10),
              // Next step: book the work. Intentional damage is filled in as the
              // tenant paying; the amount to charge is entered there.
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.green800,
                  side: const BorderSide(color: AppColors.gold500),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  final intentional =
                      r.type == ReportType.damage &&
                      _kind == DamageKind.intentional;
                  showAppSheet(
                    context,
                    title: 'Schedule work',
                    builder: (_) => ScheduleForm(
                      title: r.issue,
                      where: r.unit,
                      kind: switch (r.type) {
                        ReportType.maintenance => 1,
                        ReportType.modification => 3,
                        _ => 0,
                      },
                      tenantPays: intentional,
                    ),
                  );
                },
                icon: const Icon(
                  Icons.event_available_rounded,
                  size: 18,
                  color: AppColors.gold700,
                ),
                label: const Text(
                  'Schedule this',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip(this.label, this.selected, this.onTap);
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: selected ? goldGradient : null,
        color: selected ? null : AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.transparent : AppColors.slate200,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: selected ? AppColors.green900 : AppColors.slate600,
        ),
      ),
    ),
  );
}

/// Report verification: maintenance and damage reports made by tenants. The
/// admin checks each one; for damage they decide accident or intentional and
/// set any deduction. Pass [unit] to see only that unit's reports.
class ReportVerificationScreen extends StatefulWidget {
  const ReportVerificationScreen({super.key, this.unit});
  final String? unit;
  @override
  State<ReportVerificationScreen> createState() =>
      _ReportVerificationScreenState();
}

class _ReportVerificationScreenState extends State<ReportVerificationScreen> {
  bool get _isCondo =>
      widget.unit != null &&
      adminState.units.where((u) => u.name == widget.unit).firstOrNull?.type ==
          'Condo';

  int _filter = 0;
  int _type = 0; // 0 all, 1 maintenance, 2 damage, 3 modification
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.unit == null
              ? 'Report verification'
              : 'Reports · ${widget.unit}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: adminState,
              builder: (context, _) {
                final all = adminState.reports
                    .where((r) => widget.unit == null || r.unit == widget.unit)
                    .where(
                      (r) => matchesSearch(_q, [
                        r.id,
                        r.tenant,
                        r.unit,
                        r.issue,
                        r.description,
                      ]),
                    )
                    .where(
                      (r) => switch (_type) {
                        1 => r.type == ReportType.maintenance,
                        2 => r.type == ReportType.damage,
                        3 => r.type == ReportType.modification,
                        _ => true,
                      },
                    )
                    .toList();
                int count(ReportStatus s) =>
                    all.where((r) => r.status == s).length;
                final shown = switch (_filter) {
                  1 =>
                    all.where((r) => r.status == ReportStatus.pending).toList(),
                  2 =>
                    all
                        .where((r) => r.status == ReportStatus.underReview)
                        .toList(),
                  3 =>
                    all
                        .where((r) => r.status == ReportStatus.approved)
                        .toList(),
                  _ => all,
                };
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Count(
                            'Pending',
                            count(ReportStatus.pending),
                            AppColors.amber,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Count(
                            'In review',
                            count(ReportStatus.underReview),
                            AppColors.blue,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Count(
                            'Approved',
                            count(ReportStatus.approved),
                            AppColors.emerald,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Maintenance or damage.
                    SegmentedTabs(
                      labels: const [
                        'All types',
                        'Maintenance',
                        'Damage',
                        'Modifications',
                      ],
                      index: _type,
                      onChanged: (i) => setState(() => _type = i),
                    ),
                    const SizedBox(height: 10),
                    SegmentedTabs(
                      labels: const ['All', 'Pending', 'In review', 'Approved'],
                      index: _filter,
                      onChanged: (i) => setState(() => _filter = i),
                    ),
                    // Condos have no tenant app: the landlady files reports here.
                    if (_isCondo) ...[
                      const SizedBox(height: 14),
                      GoldButton(
                        label: 'New report',
                        icon: Icons.add_rounded,
                        onPressed: () => showAppSheet(
                          context,
                          title: 'New report · ${widget.unit}',
                          builder: (_) => _ManualReportForm(widget.unit!),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    SearchField(
                      hint: 'Search issue, tenant, unit',
                      onChanged: (v) => setState(() => _q = v),
                    ),
                    const SizedBox(height: 14),
                    if (shown.isEmpty)
                      EmptyState(
                        icon: Icons.fact_check_outlined,
                        title: 'No reports here',
                        message: _isCondo
                            ? 'Reports you add for this condo will show up here.'
                            : 'Reports from tenants will show up in this list.',
                      ),
                    for (final r in shown)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _ReportCard(r),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
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
}

class _ReportCard extends StatelessWidget {
  const _ReportCard(this.r);
  final DamageReport r;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 18,
      onTap: () => push(context, ReportDetailScreen(r)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusPill(r.status),
              const SizedBox(width: 6),
              _typePill(r.type),
              const Spacer(),
              Text(
                r.id,
                style: const TextStyle(fontSize: 12, color: AppColors.slate400),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            r.issue,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: AppColors.green800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${r.tenant} · ${r.unit}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
          ),
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Icons.schedule, size: 13, color: AppColors.slate400),
              const SizedBox(width: 4),
              Text(
                r.date,
                style: const TextStyle(fontSize: 12, color: AppColors.slate400),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.attach_file,
                size: 13,
                color: AppColors.slate400,
              ),
              Text(
                '${r.attachments}',
                style: const TextStyle(fontSize: 12, color: AppColors.slate400),
              ),
              const Spacer(),
              if (r.kind != null)
                r.kind == DamageKind.accident
                    ? Pill.info('Accident')
                    : Pill.urgent('Intentional'),
            ],
          ),
          if (r.status == ReportStatus.pending) ...[
            const SizedBox(height: 12),
            GoldButton(
              label: 'Start review',
              icon: Icons.fact_check_outlined,
              compact: true,
              onPressed: () {
                adminState.saveReport(
                  r,
                  ReportStatus.underReview,
                  r.kind,
                  r.deduction,
                  r.note,
                );
                push(context, ReportDetailScreen(r));
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// A report the landlady enters for a condo: maintenance, damage or a
/// modification, what happened and photos. It is about the unit itself;
/// damage by a guest is handled by deducting their deposit.
class _ManualReportForm extends StatefulWidget {
  const _ManualReportForm(this.unit);
  final String unit;
  @override
  State<_ManualReportForm> createState() => _ManualReportFormState();
}

class _ManualReportFormState extends State<_ManualReportForm> {
  final _key = GlobalKey<FormState>();
  final _issue = TextEditingController();
  final _desc = TextEditingController();
  ReportType _type = ReportType.damage;
  final List<Uint8List> _photos = [];

  @override
  void dispose() {
    _issue.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Type'),
          SegmentedTabs(
            light: true,
            labels: const ['Maintenance', 'Damage', 'Modification'],
            index: _type.index,
            onChanged: (i) => setState(() => _type = ReportType.values[i]),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Issue'),
          TextFormField(
            controller: _issue,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Broken lamp, leaking faucet',
            ),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Name the issue' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('What happened'),
          TextFormField(
            controller: _desc,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Where, when and how...',
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Describe it' : null,
          ),
          const SizedBox(height: 12),
          const FieldLabel('Photos'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.green800,
              side: const BorderSide(color: AppColors.gold500),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () async {
              final bytes = await choosePhoto(context);
              if (bytes != null && mounted) setState(() => _photos.add(bytes));
            },
            icon: const Icon(
              Icons.add_a_photo_outlined,
              color: AppColors.gold600,
            ),
            label: Text(
              _photos.isEmpty
                  ? 'Add a photo'
                  : '${_photos.length} ${_photos.length == 1 ? 'photo' : 'photos'} · add another',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 16),
          GoldButton(
            label: 'Save report',
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              adminState.addManualReport(
                unit: widget.unit,
                issue: _issue.text.trim(),
                description: _desc.text.trim(),
                type: _type,

                files: _photos,
              );
              popOnce(context);
              toast(context, 'Report saved.');
            },
          ),
        ],
      ),
    );
  }
}
