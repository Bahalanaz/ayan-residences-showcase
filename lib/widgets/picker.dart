import 'package:flutter/material.dart';

import '../theme.dart';
import 'motion.dart';

/// One choice in the picker. Only [value] and [label] are required; the rest
/// make long lists easier to scan (icon, a second line, a badge, a group).
class PickerOption {
  const PickerOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.group,
    this.badge,
    this.badgeColor,
    this.kind,
    this.person,
  });
  final String value, label;
  final String? subtitle, group, badge;

  /// Its kind ("Apartment", "Condo", "Villa"): when options have kinds, the
  /// sheet shows a filter button for each. Null shows under every filter.
  final String? kind;

  /// Who lives there, shown with a person icon.
  final String? person;
  final IconData? icon;
  final Color? badgeColor;
}

/// Opens a selection sheet that copes with long lists: grouped sections, a
/// search box (shown once there are more than [searchFrom] options), a second
/// line and badge per option, and a tall scrolling list that never fills the
/// whole screen. Returns the chosen value, or null if dismissed.
Future<String?> showPicker(
  BuildContext context, {
  required String title,
  required List<PickerOption> options,
  String? selected,
  int searchFrom = 7,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _PickerSheet(
      title: title,
      options: options,
      selected: selected,
      searchable: options.length >= searchFrom,
    ),
  );
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.searchable,
  });
  final String title;
  final List<PickerOption> options;
  final String? selected;
  final bool searchable;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  final _search = TextEditingController();
  String _q = '';

  /// The kind filter picked at the top (null shows everything).
  String? _kind;

  late final List<String> _kinds = [
    for (final k in const ['Apartment', 'Condo', 'Villa'])
      if (widget.options.any((o) => o.kind == k)) k,
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(PickerOption o) {
    if (_kind != null && o.kind != null && o.kind != _kind) return false;
    if (_q.isEmpty) return true;
    final hay =
        '${o.label} ${o.subtitle ?? ''} ${o.group ?? ''} ${o.badge ?? ''} ${o.person ?? ''}'
            .toLowerCase();
    return _q.split(' ').where((w) => w.isNotEmpty).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final shown = widget.options.where(_matches).toList();
    final h = MediaQuery.sizeOf(context).height;
    final rows = <Widget>[];
    String? lastGroup = '\u0000';
    for (final o in shown) {
      if (o.group != lastGroup) {
        lastGroup = o.group;
        if (o.group != null) rows.add(_GroupHeader(o.group!));
      }
      rows.add(
        _OptionTile(
          option: o,
          selected: o.value == widget.selected,
          onTap: () => popOnce(context, o.value),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * .78),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.slate200,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green800,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.options.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate400,
                    ),
                  ),
                  IconButton(
                    onPressed: () => popOnce(context),
                    icon: const Icon(Icons.close, color: AppColors.slate500),
                  ),
                ],
              ),
            ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 20,
                      color: AppColors.slate400,
                    ),
                    suffixIcon: _q.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setState(() {
                              _search.clear();
                              _q = '';
                            }),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(color: AppColors.slate200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: const BorderSide(color: AppColors.slate200),
                    ),
                  ),
                ),
              ),
            if (_kinds.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: _KindButton(
                        label: 'All',
                        icon: Icons.grid_view_rounded,
                        on: _kind == null,
                        onTap: () => setState(() => _kind = null),
                      ),
                    ),
                    for (final k in _kinds) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 3,
                        child: _KindButton(
                          label: k,
                          icon: switch (k) {
                            'Villa' => Icons.house_rounded,
                            'Condo' => Icons.domain_rounded,
                            _ => Icons.meeting_room_rounded,
                          },
                          on: _kind == k,
                          onTap: () =>
                              setState(() => _kind = _kind == k ? null : k),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            Flexible(
              child: shown.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text(
                        'No matches',
                        style: TextStyle(
                          color: AppColors.slate400,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      children: rows,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11.5,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w800,
        color: AppColors.gold700,
      ),
    ),
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });
  final PickerOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = option;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? AppColors.gold500.withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                if (o.icon != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.gold500.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(o.icon, size: 19, color: AppColors.gold600),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: AppColors.green800,
                        ),
                      ),
                      if (o.subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            o.subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.slate500,
                            ),
                          ),
                        ),
                      if (o.person != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.person_rounded,
                                size: 14,
                                color: AppColors.emerald,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  o.person!,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
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
                ),
                if (o.badge != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: (o.badgeColor ?? AppColors.slate500).withValues(
                        alpha: .12,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      o.badge!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: o.badgeColor ?? AppColors.slate500,
                      ),
                    ),
                  ),
                ],
                if (selected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle,
                    size: 20,
                    color: AppColors.gold600,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KindButton extends StatelessWidget {
  const _KindButton({
    required this.label,
    required this.icon,
    required this.on,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        gradient: on ? goldGradient : null,
        color: on ? null : AppColors.slate50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? Colors.transparent : AppColors.slate200),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: on ? AppColors.green900 : AppColors.gold600,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: on ? AppColors.green900 : AppColors.slate600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
