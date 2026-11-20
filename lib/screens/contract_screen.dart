import 'package:flutter/material.dart';

import '../admin/admin_state.dart' show TenantRec, adminState, parseDate;
import '../state/demo.dart';
import '../state/app_state.dart';
import '../widgets/chat_view.dart' show PdfTile;
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

const _renewalOptions = [
  'Request 1-Year Renewal (Same Terms)',
  'Request Renewal with Parking Slot Addition',
  'Notice of Intent to Move Out (End of Lease)',
];

/// 1 -> "1st", 2 -> "2nd", 5 -> "5th", 22 -> "22nd".
String ordinal(int n) {
  if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
  return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
}

String _fmt(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
}

/// The assigned contract: file details and a download button. (Opening the
/// pages in-app and saving to the phone come with the PDF viewer and backend.)
class _ContractSheet extends StatelessWidget {
  const _ContractSheet(this.t);
  final TenantRec t;

  @override
  Widget build(BuildContext context) {
    final at = t.contractAssignedAt;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PdfTile(name: t.contractName!, size: t.contractPdf?.length ?? 0),
      if (at != null) ...[
        const SizedBox(height: 8),
        Text('Added by management on ${_fmt(at)}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate500)),
      ],
      const SizedBox(height: 16),
      GoldButton(
        label: 'Download PDF',
        icon: Icons.download_rounded,
        onPressed: () {
          popOnce(context);
          toast(context, 'Downloading ${t.contractName}...');
        },
      ),
    ]);
  }
}

class ContractScreen extends StatefulWidget {
  const ContractScreen({super.key});
  @override
  State<ContractScreen> createState() => _ContractScreenState();
}

class _ContractScreenState extends State<ContractScreen> {
  final _key = GlobalKey<FormState>();
  final _notes = TextEditingController();
  final _phone = TextEditingController();
  String _choice = _renewalOptions.first;

  @override
  void initState() {
    super.initState();
    _phone.text = appState.phone;
  }

  @override
  void dispose() {
    _notes.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, adminState]),
      builder: (context, _) {
        final s = appState;
        // The lease terms are whatever management set for this tenant.
        final rec = adminState.tenants.where((x) => x.name == s.currentTenant).firstOrNull;
        final start = parseDate(rec?.leaseStart ?? '') ?? s.leaseStart;
        final end = parseDate(rec?.leaseEnd ?? '') ?? s.leaseEnd;
        final unitRec = rec == null
            ? null
            : adminState.units.where((u) => u.name == rec.unit).firstOrNull;
        final unitText = unitRec != null ? '${unitRec.name} · ${unitRec.property}' : s.unit;
        final rent = rec?.rent ?? s.monthlyRent;
        final deposit = rec?.deposit ?? s.deposit;
        final dueDay = rec?.dueDay ?? 5;
        final termMonths = rec?.termMonths ?? 12;
        final days = end.difference(s.today).inDays;
        final total = end.difference(start).inDays;
        final progress = total <= 0 ? 1.0 : (1 - days / total).clamp(0.0, 1.0);
        // The tenant's request still waiting for an answer, from the database
        // (so it shows on any phone and after reopening the app).
        final request = demoData ? null : adminState.pendingRequestOf(s.currentTenant);
        final choice = s.renewalChoice ?? request?.kind;
        final statusText = s.renewalStatus ??
            (request == null ? null : 'Submitted ${request.date} · Awaiting management review');
        final moveOut = (choice ?? '').toLowerCase().contains('move');
        return SubPage(title: 'Rental Contract & Lease', children: [
          // Lease overview
          Stack(children: [
            AppCard(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('UNIT ASSIGNED',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.slate500)),
                const SizedBox(height: 2),
                Text(unitText,
                    style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: _Date('Start Date', _fmt(start))),
                  const SizedBox(width: 10),
                  Expanded(child: _Date('Expiration Date', _fmt(end))),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.slate100,
                    color: AppColors.gold500,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.amberBg.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE8D5A0)),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.schedule, size: 18, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(TextSpan(
                        style: const TextStyle(
                            fontSize: 12, height: 1.4, color: AppColors.amber),
                        children: [
                          TextSpan(
                              text: '$days Days Remaining. ',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          const TextSpan(
                              text:
                                  'Renewal requests are recommended 90 days before contract ends.'),
                        ],
                      )),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                ListenableBuilder(
                  listenable: adminState,
                  builder: (context, _) {
                    // The contract management assigned to this tenant.
                    final t = adminState.tenants
                        .where((x) => x.name == s.currentTenant)
                        .firstOrNull;
                    if (t?.contractName == null) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppColors.slate50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.slate200),
                        ),
                        child: const Text('Your contract will appear here once management adds it.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12.5, color: AppColors.slate500)),
                      );
                    }
                    return NavyButton(
                      label: 'View / Download Contract (PDF)',
                      icon: Icons.picture_as_pdf_outlined,
                      onPressed: () => showAppSheet(context,
                          title: 'Your contract', builder: (_) => _ContractSheet(t!)),
                    );
                  },
                ),
              ]),
            ),
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: const BoxDecoration(
                  color: AppColors.gold500,
                  borderRadius: BorderRadius.only(
                      topRight: Radius.circular(22), bottomLeft: Radius.circular(14)),
                ),
                child: const Text('ACTIVE LEASE',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green900)),
              ),
            ),
          ]),

          // Terms summary
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Key Lease Terms',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800)),
              const SizedBox(height: 6),
              KeyValueRow(adminState.rentLabelOf(rec), peso(rent, dhs: adminState.isVilla(appState.currentTenant))),
              KeyValueRow('Due date', '${ordinal(dueDay)} of every month'),
              KeyValueRow('Security deposit', peso(deposit, dhs: adminState.isVilla(appState.currentTenant))),
              KeyValueRow('Lease term', '$termMonths months', last: true),
            ]),
          ),

          // Renewal
          AppCard(
            child: statusText != null
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(moveOut ? Icons.logout : Icons.autorenew,
                          color: AppColors.gold600, size: 20),
                      const SizedBox(width: 8),
                      const Text('Your Request',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.green800)),
                      const Spacer(),
                      Pill.pending('UNDER REVIEW'),
                    ]),
                    const SizedBox(height: 10),
                    Text(choice ?? '',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.green800)),
                    const SizedBox(height: 2),
                    Text(statusText,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.slate500)),
                  ])
                : Form(
                    key: _key,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Lease Renewal & Intent',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.green800)),
                          const SizedBox(height: 2),
                          const Text(
                              'Notify management of your plans for the upcoming term.',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.slate500)),
                          const SizedBox(height: 12),
                          const FieldLabel('Action Request'),
                          DropdownField(
                              value: _choice,
                              items: _renewalOptions,
                              onChanged: (v) => setState(() => _choice = v)),
                          const SizedBox(height: 12),
                          const FieldLabel('Updated Contact Number'),
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            validator: (v) => (v ?? '').trim().length < 7
                                ? 'Enter a valid phone number'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          const FieldLabel('Additional Notes / Special Requests'),
                          TextFormField(
                            controller: _notes,
                            maxLines: 2,
                            decoration: const InputDecoration(
                                hintText: 'Parking slot, move-out date, etc...'),
                          ),
                          const SizedBox(height: 14),
                          GoldButton(
                            label: _choice == _renewalOptions[2]
                                ? 'Submit Move-out Notice'
                                : 'Submit Renewal Request',
                            onPressed: () {
                              if (!_key.currentState!.validate()) return;
                              appState.submitRenewal(_choice, _phone.text);
                              toast(context,
                                  'Lease request sent to management!');
                            },
                          ),
                        ]),
                  ),
          ),
        ]);
      },
    );
  }
}

class _Date extends StatelessWidget {
  const _Date(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppColors.slate50, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.green800)),
        ]),
      );
}
