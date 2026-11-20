import 'package:flutter/material.dart';

import '../../state/app_state.dart' show appState;
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _month(DateTime d) =>
    '${_months[d.month - 1].substring(0, 3)} ${d.year}';

/// A unit's recurring monthly expenses (internet, Netflix, dues): listed
/// with their monthly total, added, or stopped. Finance takes them off
/// profit every month they run.
class MonthlyExpensesSheet extends StatefulWidget {
  const MonthlyExpensesSheet(this.unit, {super.key});
  final String unit;

  @override
  State<MonthlyExpensesSheet> createState() => _MonthlyExpensesSheetState();
}

class _MonthlyExpensesSheetState extends State<MonthlyExpensesSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  late DateTime _since = DateTime(appState.today.year, appState.today.month);
  String? _error;

  /// Also keep this expense as a template for this type of unit.
  bool _saveTemplate = false;

  /// "Apartment" or "Condo": which templates show here.
  late final String _type =
      adminState.units.where((u) => u.name == widget.unit).firstOrNull?.type ??
      'Apartment';

  String get _typePlural => _type == 'Condo' ? 'condos' : 'apartments';

  /// Fills the form from a template (the start month stays as picked).
  void _useTemplate(ExpenseTemplate t) {
    setState(() {
      _name.text = t.name;
      _amount.text = t.amount == t.amount.roundToDouble()
          ? t.amount.toStringAsFixed(0)
          : t.amount.toStringAsFixed(2);
      _saveTemplate = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _since,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
      helpText: 'Starts in which month?',
    );
    if (d != null) setState(() => _since = DateTime(d.year, d.month));
  }

  void _add() {
    final amount =
        double.tryParse(_amount.text.trim().replaceAll(',', '')) ?? 0;
    if (_name.text.trim().isEmpty || amount <= 0) {
      setState(
        () => _error = 'Enter what it is and how much it costs a month.',
      );
      return;
    }
    adminState.addMonthlyExpense(
      widget.unit,
      MonthlyExpense(name: _name.text.trim(), amount: amount, since: _since),
    );
    if (_saveTemplate) {
      adminState.saveExpenseTemplate(_type, _name.text.trim(), amount);
    }
    final saved = _saveTemplate;
    _name.clear();
    _amount.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _error = null;
      _saveTemplate = false;
    });
    toast(
      context,
      saved
          ? 'Added, and saved as a template for $_typePlural'
          : 'Expense added',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adminState,
      builder: (context, _) {
        final villa = adminState.isVillaUnit(widget.unit);
        final now = DateTime(appState.today.year, appState.today.month);
        final all = adminState.monthlyExpensesFor(widget.unit);
        final running = all
            .where((e) => e.until == null || !e.until!.isBefore(now))
            .toList();
        final stopped = all
            .where((e) => e.until != null && e.until!.isBefore(now))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total a month.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.green700, AppColors.green900],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EVERY MONTH',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    peso(adminState.monthlyTotal(widget.unit), dhs: villa),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'Taken off profit in Finance each month',
                    style: TextStyle(fontSize: 12, color: AppColors.slate300),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (running.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No monthly expenses yet. Add one below.',
                  style: TextStyle(fontSize: 13, color: AppColors.slate500),
                ),
              ),
            for (final e in running)
              _ExpenseTile(
                e,
                villa: villa,
                onStop: () async {
                  final ok = await confirmAction(
                    context,
                    title: 'Stop ${e.name}?',
                    message:
                        'It will no longer be taken off profit from ${_month(now)} on. '
                        'Months already counted stay as they are.',
                    action: 'Stop',
                  );
                  if (ok) adminState.stopMonthlyExpense(widget.unit, e);
                },
              ),
            if (stopped.isNotEmpty) ...[
              const SizedBox(height: 6),
              const FieldLabel('Stopped'),
              for (final e in stopped) _ExpenseTile(e, villa: villa),
            ],
            const Divider(height: 24),
            // Saved templates for this type of unit: tap to fill the form.
            Builder(
              builder: (context) {
                final templates = adminState.expenseTemplatesFor(_type);
                final runningNames = {
                  for (final e in running) e.name.toLowerCase(),
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bookmarks_outlined,
                          size: 16,
                          color: AppColors.gold600,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Templates for $_typePlural',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.slate600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (templates.isEmpty)
                      Text(
                        'None yet. Tick "Save as a template" when adding one to reuse it on other $_typePlural.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slate400,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in templates)
                            InputChip(
                              // Already running on this unit: shown, but not offered again.
                              isEnabled: !runningNames.contains(
                                t.name.toLowerCase(),
                              ),
                              avatar:
                                  runningNames.contains(t.name.toLowerCase())
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: AppColors.emerald,
                                    )
                                  : const Icon(
                                      Icons.add_rounded,
                                      size: 16,
                                      color: AppColors.gold700,
                                    ),
                              label: Text(
                                '${t.name} · ${peso(t.amount, dhs: villa)}',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.green800,
                                ),
                              ),
                              backgroundColor: AppColors.gold400.withValues(
                                alpha: .18,
                              ),
                              side: BorderSide(
                                color: AppColors.gold500.withValues(alpha: .5),
                              ),
                              deleteIconColor: AppColors.slate400,
                              onPressed: () => _useTemplate(t),
                              onDeleted: () async {
                                final ok = await confirmAction(
                                  context,
                                  title: 'Delete the ${t.name} template?',
                                  message:
                                      'It is removed from the templates for $_typePlural. '
                                      'Expenses already added to units are not changed.',
                                  action: 'Delete',
                                );
                                if (ok) adminState.deleteExpenseTemplate(t);
                              },
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),
            // Add one.
            const FieldLabel('Add a monthly expense'),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'e.g. Netflix, Internet, Association dues',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Amount a month',
                      prefixText: '${currencySign(villa)} ',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickMonth,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        suffixIcon: Icon(
                          Icons.calendar_month_outlined,
                          color: AppColors.slate500,
                        ),
                      ),
                      child: Text(
                        'From ${_month(_since)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.green800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.red),
                ),
              ),
            const SizedBox(height: 4),
            // Keep it for other units of the same type.
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _saveTemplate = !_saveTemplate),
              child: Row(
                children: [
                  Checkbox(
                    value: _saveTemplate,
                    activeColor: AppColors.gold600,
                    onChanged: (v) =>
                        setState(() => _saveTemplate = v ?? false),
                  ),
                  Expanded(
                    child: Text(
                      'Save as a template for $_typePlural',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.slate600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GoldButton(
              label: 'Add expense',
              icon: Icons.add_rounded,
              onPressed: _add,
            ),
          ],
        );
      },
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile(this.e, {required this.villa, this.onStop});
  final MonthlyExpense e;
  final bool villa;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slate200),
      ),
      child: Row(
        children: [
          IconBadge(
            onStop == null
                ? Icons.pause_circle_outline_rounded
                : Icons.autorenew_rounded,
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.green800,
                  ),
                ),
                Text(
                  e.until == null
                      ? 'Since ${_month(e.since)}'
                      : '${_month(e.since)} - ${_month(e.until!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.slate500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${peso(e.amount, dhs: villa)}/mo',
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.green800,
            ),
          ),
          if (onStop != null)
            IconButton(
              tooltip: 'Stop',
              onPressed: onStop,
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.slate400,
              ),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
