import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../admin/admin_state.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/chat_view.dart' show choosePhoto;
import '../widgets/common.dart';
import 'shell.dart';

/// Three tabs: report damage / a repair, file a complaint, or ask to modify the unit.
class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, adminState]),
      builder: (context, _) => SubPage(
        title: 'Reports & Complaints',
        children: [
          SegmentedTabs(
            labels: const ['Property Maintenance', 'Complaint', 'Modification'],
            index: _tab,
            onChanged: (i) => setState(() => _tab = i),
          ),
          if (_tab == 0) ..._reports(context) else if (_tab == 1) ..._complaints(context) else ..._requests(context),
        ],
      ),
    );
  }

  List<Widget> _reports(BuildContext context) {
    final list = appState.tickets.where((t) => t.type != ReportType.modification).toList();
    return [
      GoldButton(
        label: 'Report an Issue',
        icon: Icons.build_rounded,
        onPressed: () => showTicketSheet(context),
      ),
      const Text('Your reports',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
      LoadingSwitch(
        skeleton: const SkeletonCards(count: 2),
        child: list.isEmpty
            ? EmptyState(
                icon: Icons.build_circle_outlined,
                title: 'No reports yet',
                message: 'If something in your unit breaks, report it here with a photo.',
                actionLabel: 'Report an issue',
                onAction: () => showTicketSheet(context),
              )
            : Column(children: [
                for (final t in list)
                  Padding(padding: const EdgeInsets.only(bottom: 14), child: _TicketCard(t)),
              ]),
      ),
    ];
  }

  List<Widget> _complaints(BuildContext context) {
    final mine =
        adminState.complaints.where((c) => c.tenant == appState.currentTenant).toList();
    return [
      GoldButton(
        label: 'File a Complaint',
        icon: Icons.report_gmailerrorred_outlined,
        onPressed: () => showAppSheet(context,
            title: 'File a complaint', builder: (_) => const _ComplaintForm()),
      ),
      const Text('Your complaints',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
      if (mine.isEmpty)
        EmptyState(
          icon: Icons.sentiment_satisfied_alt_rounded,
          title: 'No complaints',
          message: 'Noise, cleanliness, neighbours or facilities: tell management here and they will respond.',
          actionLabel: 'File a complaint',
          onAction: () => showAppSheet(context,
              title: 'File a complaint', builder: (_) => const _ComplaintForm()),
        )
      else
        Column(children: [
          for (final c in mine)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: _ComplaintCard(c)),
        ]),
    ];
  }

  List<Widget> _requests(BuildContext context) {
    final mine =
        appState.tickets.where((t) => t.type == ReportType.modification).toList();
    void open() => showAppSheet(context,
        title: 'Modification request', builder: (_) => const _RequestForm());
    return [
      GoldButton(label: 'New Modification Request', icon: Icons.edit_note_rounded, onPressed: open),
      const Text('Your requests',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
      if (mine.isEmpty)
        EmptyState(
          icon: Icons.handyman_outlined,
          title: 'No requests',
          message: 'Want to change something in your unit, like painting or adding a fixture? Ask management here first.',
          actionLabel: 'New request',
          onAction: open,
        )
      else
        Column(children: [
          for (final c in mine)
            Padding(padding: const EdgeInsets.only(bottom: 14), child: _TicketCard(c)),
        ]),
    ];
  }
}

class _RequestForm extends StatefulWidget {
  const _RequestForm();
  @override
  State<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<_RequestForm> {
  final _key = GlobalKey<FormState>();
  final _what = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _what.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const FieldLabel('What do you want to change?'),
        TextFormField(
          controller: _what,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Repaint the bedroom, install a shelf'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Please say what you want changed' : null,
        ),
        const SizedBox(height: 12),
        const FieldLabel('Details'),
        TextFormField(
          controller: _body,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Where, how, and who will do the work...'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Please add some details' : null,
        ),
        const SizedBox(height: 8),
        const Text('Please wait for management to approve before starting any work.',
            style: TextStyle(fontSize: 12, color: AppColors.slate500)),
        const SizedBox(height: 16),
        GoldButton(
          label: 'Submit request',
          icon: Icons.send_rounded,
          onPressed: () {
            if (!_key.currentState!.validate()) return;
            appState.addTicket(
                issue: _what.text.trim(),
                description: _body.text.trim(),
                attachments: 0,
                type: ReportType.modification);
            popOnce(context);
            toast(context, 'Request submitted. Management will respond.');
          },
        ),
      ]),
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  const _ComplaintCard(this.c);
  final ComplaintRec c;

  @override
  Widget build(BuildContext context) {
    final pill = switch (c.status) {
      ComplaintStatus.open => Pill.pending('RECEIVED'),
      ComplaintStatus.inProgress => Pill.info('IN PROGRESS'),
      ComplaintStatus.resolved => Pill.verified('RESOLVED'),
    };
    return AppCard(
      radius: 18,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          pill,
          const Spacer(),
          Text(c.date, style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
        ]),
        const SizedBox(height: 10),
        Text(c.category,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green800)),
        const SizedBox(height: 4),
        Text(c.body, style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.slate500)),
        if (c.response != null) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.slate50, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Management replied',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.gold700)),
              const SizedBox(height: 2),
              Text(c.response!,
                  style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.green800)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _ComplaintForm extends StatefulWidget {
  const _ComplaintForm();
  @override
  State<_ComplaintForm> createState() => _ComplaintFormState();
}

class _ComplaintFormState extends State<_ComplaintForm> {
  final _key = GlobalKey<FormState>();
  final _body = TextEditingController();
  String _category = complaintCategories.first;

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const FieldLabel('What is it about?'),
        DropdownField(
            value: _category,
            items: complaintCategories,
            onChanged: (v) => setState(() => _category = v)),
        const SizedBox(height: 12),
        const FieldLabel('Tell us what happened'),
        TextFormField(
          controller: _body,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              hintText: 'When, where, and who or what is involved...'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Please describe the problem' : null,
        ),
        const SizedBox(height: 8),
        const Text('Only management sees your complaint, not other tenants.',
            style: TextStyle(fontSize: 12, color: AppColors.slate500)),
        const SizedBox(height: 16),
        GoldButton(
          label: 'Submit complaint',
          icon: Icons.send_rounded,
          onPressed: () {
            if (!_key.currentState!.validate()) return;
            adminState.fileComplaint(appState.currentTenant, _category, _body.text.trim());
            popOnce(context);
            toast(context, 'Complaint submitted. Management will respond.');
          },
        ),
      ]),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard(this.t);
  final Ticket t;

  @override
  Widget build(BuildContext context) {
    // Management's view of the same report: its status and progress notes.
    final report = adminState.reports.where((r) => r.id == t.id).firstOrNull;
    final status = switch (report?.status) {
      ReportStatus.pending => TicketStatus.pending,
      ReportStatus.underReview => TicketStatus.underReview,
      ReportStatus.approved => TicketStatus.approved,
      null => t.status,
    };
    final pill = switch (status) {
      TicketStatus.pending => Pill.pending('PENDING'),
      TicketStatus.underReview => Pill.info('UNDER REVIEW'),
      TicketStatus.approved => Pill.verified('APPROVED'),
    };
    final photos = report?.attachments ?? t.attachments;
    return AppCard(
      radius: 18,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          pill,
          const SizedBox(width: 8),
          Text(switch (t.type) { ReportType.maintenance => 'Maintenance', ReportType.damage => 'Damage', ReportType.modification => 'Modification' },
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.slate500)),
        ]),
        const SizedBox(height: 10),
        Text(t.title,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green800)),
        const SizedBox(height: 4),
        Text(t.description,
            style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
        // Progress notes from management.
        if (report != null && report.updates.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.slate50, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Updates from management',
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.gold700)),
              for (final u in report.updates) ...[
                const SizedBox(height: 6),
                Text(u.text,
                    style: const TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.green800)),
                Text(u.date, style: const TextStyle(fontSize: 11, color: AppColors.slate400)),
              ],
            ]),
          ),
        ],
        const Divider(height: 22),
        Row(children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.schedule, size: 12, color: AppColors.slate400),
                  const SizedBox(width: 4),
                  Text('Reported: ${t.date}',
                      style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
                ]),
                if (photos > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.attach_file, size: 12, color: AppColors.slate400),
                    Text('$photos',
                        style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
                  ]),
              ],
            ),
          ),
          // More photos can be added until the report is approved.
          if (status != TicketStatus.approved)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () async {
                final bytes = await choosePhoto(context);
                if (bytes == null || !context.mounted) return;
                appState.addTicketPhotos(t, 1);
                adminState.addReportPhotos(t.id, 1, photos: [bytes]);
                toast(context, 'Photo added to your report.');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.add_a_photo_outlined, size: 14, color: AppColors.gold600),
                  SizedBox(width: 4),
                  Text('Add photo',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.gold700)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }
}

void showTicketSheet(BuildContext context) {
  showAppSheet(context,
      title: 'Property Maintenance', builder: (_) => const _TicketForm());
}

class _TicketForm extends StatefulWidget {
  const _TicketForm();
  @override
  State<_TicketForm> createState() => _TicketFormState();
}

class _TicketFormState extends State<_TicketForm> {
  final _key = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _issue = TextEditingController();
  final List<Uint8List> _photos = [];
  ReportType _type = ReportType.maintenance;

  @override
  void dispose() {
    _issue.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_key.currentState!.validate()) return;
    appState.addTicket(
      issue: _issue.text.trim(),
      description: _desc.text.trim(),
      attachments: _photos.length,
      type: _type,
      photos: _photos,
    );
    popOnce(context);
    toast(context, 'Issue report has been submitted.');
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const FieldLabel('Type'),
        SegmentedTabs(
          light: true,
          labels: const ['Maintenance', 'Damage'],
          index: _type.index,
          onChanged: (i) => setState(() => _type = ReportType.values[i]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              _type == ReportType.maintenance
                  ? 'Something that needs fixing or servicing, like a leak or a filter.'
                  : 'Something that got broken or damaged in the unit.',
              style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Issue'),
        TextFormField(
          controller: _issue,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
              hintText: 'e.g. Leaking faucet, broken door lock'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Please name the issue' : null,
        ),
        const SizedBox(height: 12),
        const FieldLabel('Description of Problem'),
        TextFormField(
          controller: _desc,
          maxLines: 3,
          decoration:
              const InputDecoration(hintText: 'Describe the damage or concern...'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Please describe the issue' : null,
        ),
        const SizedBox(height: 12),
        const FieldLabel('Attach Photos'),
        AttachmentPicker(
          title: 'Take photo or select from gallery',
          hint: 'Photos help us fix it faster',
          files: const [],
          photos: _photos,
          onAdd: () async {
            final bytes = await choosePhoto(context);
            if (bytes != null && mounted) setState(() => _photos.add(bytes));
          },
          onRemove: (i) => setState(() => _photos.removeAt(i)),
        ),
        const SizedBox(height: 16),
        GoldButton(label: 'Submit Issue Report', onPressed: _submit),
      ]),
    );
  }
}
