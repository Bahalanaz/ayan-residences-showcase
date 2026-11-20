import 'package:flutter/material.dart';

import '../../screens/home_screen.dart' show push;
import '../../screens/shell.dart' show SubPage;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

IconData _icon(String category) => switch (category) {
  'Noise' => Icons.volume_up_outlined,
  'Neighbors' => Icons.groups_outlined,
  'Cleanliness' => Icons.cleaning_services_outlined,
  'Facilities' => Icons.elevator_outlined,
  'Staff' => Icons.badge_outlined,
  _ => Icons.report_gmailerrorred_outlined,
};

String _label(ComplaintStatus s) => switch (s) {
  ComplaintStatus.open => 'Open',
  ComplaintStatus.inProgress => 'In progress',
  ComplaintStatus.resolved => 'Resolved',
};

Pill _pill(ComplaintStatus s) => switch (s) {
  ComplaintStatus.open => Pill.urgent('OPEN'),
  ComplaintStatus.inProgress => Pill.pending('IN PROGRESS'),
  ComplaintStatus.resolved => Pill.verified('RESOLVED'),
};

/// Complaints from tenants: filter by status, answer, and mark as resolved.
class ComplaintsAdminScreen extends StatefulWidget {
  /// Pass [unit] to see only that unit's complaints.
  const ComplaintsAdminScreen({super.key, this.unit});
  final String? unit;
  @override
  State<ComplaintsAdminScreen> createState() => _ComplaintsAdminScreenState();
}

class _ComplaintsAdminScreenState extends State<ComplaintsAdminScreen> {
  int _tab = 0;
  static const _tabs = ['Open', 'In progress', 'Resolved'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final status = ComplaintStatus.values[_tab];
        final list = adminState.complaints
            .where((c) => c.status == status)
            .where((c) => widget.unit == null || c.unit == widget.unit)
            .toList();
        return SubPage(
          title: widget.unit == null
              ? 'Complaints'
              : 'Complaints · ${widget.unit}',
          children: [
            SegmentedTabs(
              labels: _tabs,
              index: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
            if (list.isEmpty)
              EmptyState(
                icon: Icons.task_alt_rounded,
                title: 'Nothing ${_label(status).toLowerCase()}',
                message: switch (status) {
                  ComplaintStatus.open =>
                    'New complaints from tenants will show up here.',
                  ComplaintStatus.inProgress =>
                    'Complaints you are working on will be listed here.',
                  ComplaintStatus.resolved =>
                    'Resolved complaints are kept here for your records.',
                },
              ),
            for (final c in list)
              AppCard(
                radius: 18,
                onTap: () => push(context, _ComplaintDetail(c)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBadge(_icon(c.category), size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  c.category,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.green800,
                                  ),
                                ),
                              ),
                              Text(
                                c.date,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.slate400,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${c.tenant} · ${c.unit}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            c.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.slate600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _pill(c.status),
                        ],
                      ),
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

class _ComplaintDetail extends StatefulWidget {
  const _ComplaintDetail(this.c);
  final ComplaintRec c;
  @override
  State<_ComplaintDetail> createState() => _ComplaintDetailState();
}

class _ComplaintDetailState extends State<_ComplaintDetail> {
  late final _response = TextEditingController(text: widget.c.response ?? '');
  late ComplaintStatus _status = widget.c.status;

  @override
  void dispose() {
    _response.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return SubPage(
      title: c.category,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(_icon(c.category), size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.tenant,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800,
                          ),
                        ),
                        Text(
                          '${c.unit} · ${c.date}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.slate500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                c.body,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: AppColors.green800,
                ),
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FieldLabel('Status'),
              SegmentedTabs(
                light: true,
                labels: [for (final s in ComplaintStatus.values) _label(s)],
                index: _status.index,
                onChanged: (i) =>
                    setState(() => _status = ComplaintStatus.values[i]),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Response to the tenant'),
              TextField(controller: _response, maxLines: 4),
              const SizedBox(height: 14),
              GoldButton(
                label: 'Save',
                onPressed: () {
                  adminState.updateComplaint(c, _status, _response.text.trim());
                  popOnce(context);
                  toast(context, 'Complaint updated');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
