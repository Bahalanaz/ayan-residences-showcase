import 'dart:typed_data';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../state/chat_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../admin_state.dart';
import 'unit_detail_screen.dart';

/// Property types shown in the menu: label -> type stored on each unit.
const _types = {'Apartments': 'Apartment', 'Condo': 'Condo', 'Villa': 'Villa'};

/// Units for one property type, shown as photo cards.
class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});
  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> {
  String _label = 'Apartments';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Property',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold500,
        foregroundColor: AppColors.green900,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add unit',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        onPressed: () => showAppSheet(
          context,
          title: 'Add unit',
          builder: (_) => _UnitForm(initialType: _types[_label]!),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: adminState,
              builder: (context, _) {
                final units = adminState.units
                    .where((u) => u.type == _types[_label])
                    .toList();
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                  children: [
                    // Property type tabs, same style as the report filters.
                    SegmentedTabs(
                      labels: [
                        for (final l in _types.keys)
                          l == 'Apartments' ? l : '${l}s',
                      ],
                      index: _types.keys.toList().indexOf(_label),
                      onChanged: (i) =>
                          setState(() => _label = _types.keys.elementAt(i)),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        '$_label · ${units.length} ${units.length == 1 ? 'unit' : 'units'}',
                        style: const TextStyle(
                          color: AppColors.slate300,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    LoadingSwitch(
                      skeleton: const SkeletonGrid(),
                      child: units.isEmpty
                          ? EmptyState(
                              icon: Icons.apartment_rounded,
                              title: 'No ${_label.toLowerCase()} yet',
                              message: 'Add a unit to start tracking its tenant, rent and repairs.',
                              actionLabel: 'Add unit',
                              onAction: () => showAppSheet(
                                context,
                                title: 'Add unit',
                                builder: (_) =>
                                    _UnitForm(initialType: _types[_label]!),
                              ),
                            )
                          : GridView.count(
                              padding: EdgeInsets.zero,
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: .92,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [for (final u in units) _UnitCard(u)],
                            ),
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

/// Bell on a unit card when the tenant needs attention: open damage reports,
/// open complaints, or chat messages management hasn't read. Hidden when
/// there is nothing.
class _UnitBell extends StatelessWidget {
  const _UnitBell(this.u);
  final UnitRec u;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([adminState, chatState]),
      builder: (context, _) {
        final s = adminState;
        final tenant = s.tenants.where((t) => t.unit == u.name).firstOrNull;
        final count =
            s.reports
                .where(
                  (r) => r.unit == u.name && r.status != ReportStatus.approved,
                )
                .length +
            s.complaints
                .where(
                  (c) =>
                      c.unit == u.name && c.status != ComplaintStatus.resolved,
                )
                .length +
            (tenant == null
                ? 0
                : chatState.unread(ChatSender.admin, tenant.name)) +
            (tenant == null
                ? 0
                : s
                      .requiredDocs(tenant)
                      .where((d) => s.docState(tenant, d) == DocState.toReview)
                      .length);
        if (count == 0) return const SizedBox.shrink();
        return Tooltip(
          message: '$count new from the tenant',
          // The bell is centred in its circle; the count sits on the circle's
          // top-right edge.
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 3,
                  top: 3,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      // No background: just the gold bell, which rings now and
                      // then. The shadow keeps it readable on the photo.
                      child: RingingBell(
                        child: Icon(
                          Icons.notifications_active_rounded,
                          size: 24,
                          color: AppColors.gold400,
                          shadows: [
                            Shadow(color: Colors.black87, blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 17),
                    height: 17,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard(this.u);
  final UnitRec u;

  @override
  Widget build(BuildContext context) {
    final pill = switch (u.status) {
      UnitStatus.vacant => Pill.neutral('Vacant'),
      UnitStatus.reserved => Pill.pending('Reserved'),
      UnitStatus.occupied => Pill.verified('Occupied'),
    };
    final condition = switch (u.condition) {
      UnitCondition.good => null,
      UnitCondition.underMaintenance => Pill.info('Under maintenance'),
      UnitCondition.underRepair => Pill.urgent('Under repair'),
      UnitCondition.underModification => Pill.pending('Under modification'),
    };
    return OpenContainer<void>(
      transitionType: ContainerTransitionType.fade,
      transitionDuration: const Duration(milliseconds: 520),
      closedElevation: 3,
      closedColor: Colors.white,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      openColor: AppColors.slate50,
      openElevation: 0,
      openShape: const RoundedRectangleBorder(),
      openBuilder: (_, _) => UnitDetailScreen(u),
      closedBuilder: (_, _) => Stack(
        fit: StackFit.expand,
        children: [
          unitImage(u),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x14000000),
                  Color(0x00000000),
                  Color(0xCC08251E),
                ],
                stops: [0, .35, 1],
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                pill,
                if (condition != null) ...[
                  const SizedBox(height: 4),
                  condition,
                ],
              ],
            ),
          ),
          Positioned(top: 6, right: 6, child: _UnitBell(u)),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.property,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  u.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
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

/// Asks for a template name. Owns its text controller so it is only disposed
/// once the dialog has fully closed.
class _TemplateNameDialog extends StatefulWidget {
  const _TemplateNameDialog({required this.initial, required this.summary});
  final String initial, summary;
  @override
  State<_TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<_TemplateNameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: const Text(
        'Save as template',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.green800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.summary,
            style: const TextStyle(fontSize: 12.5, color: AppColors.slate500),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Template name'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => popOnce(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold500,
            foregroundColor: AppColors.green900,
          ),
          onPressed: () => popOnce(context, _name.text.trim()),
          child: const Text(
            'Save',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _UnitForm extends StatefulWidget {
  const _UnitForm({required this.initialType});
  final String initialType;
  @override
  State<_UnitForm> createState() => _UnitFormState();
}

class _UnitFormState extends State<_UnitForm> {
  final _key = GlobalKey<FormState>();
  // The property of the last unit added (most often the next one's too).
  final _property = TextEditingController(
    text: adminState.units.isEmpty ? '' : adminState.units.last.property,
  );
  final _name = TextEditingController();
  final _rate = TextEditingController();
  late String _type = widget.initialType;

  /// Set by the type: condo per night, apartment per month, villa per year.
  String get _per => ratePeriodFor(_type);

  bool get _villa => _type == 'Villa';
  int _beds = 1;
  Uint8List? _photo;

  /// Name of the template last applied, to highlight its chip.
  String? _applied;

  @override
  void dispose() {
    _property.dispose();
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  /// Fills every field except the unit name from a template.
  void _apply(UnitTemplate t) {
    setState(() {
      _applied = t.name;
      _property.text = t.property;
      _type = t.type;
      _beds = t.bedrooms;
      _rate.text = t.rate == null
          ? ''
          : t.rate! == t.rate!.roundToDouble()
          ? t.rate!.toStringAsFixed(0)
          : '${t.rate}';
      if (t.photo != null) _photo = t.photo;
    });
  }

  /// Saves the current settings (not the unit name) under a name.
  Future<void> _saveTemplate() async {
    if (_property.text.trim().isEmpty) {
      toast(context, 'Enter a property first');
      return;
    }
    final suggestion = '${_property.text.trim()} · ${bedroomLabel(_beds)}';
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _TemplateNameDialog(
        initial: _applied ?? suggestion,
        summary:
            '${_property.text.trim()} · $_type · ${bedroomLabel(_beds)}'
            '${_rate.text.trim().isEmpty ? '' : ' · ${currencySign(_type == 'Villa')}${_rate.text.trim()}/$_per'}'
            '${_photo != null ? ' · with photo' : ''}',
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    adminState.saveTemplate(
      UnitTemplate(
        name: name,
        property: _property.text.trim(),
        type: _type,
        bedrooms: _beds,
        rate: double.tryParse(_rate.text),
        rateUnit: _per,
        photo: _photo,
      ),
    );
    setState(() => _applied = name);
    toast(context, 'Template "$name" saved');
  }

  Future<void> _deleteTemplate(UnitTemplate t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Delete template?',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.green800,
          ),
        ),
        content: Text(
          '"${t.name}" will be removed. Units already added stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => popOnce(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => popOnce(ctx, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    adminState.deleteTemplate(t);
    setState(() {
      if (_applied == t.name) _applied = null;
    });
  }

  Widget _templates() {
    final list = adminState.unitTemplates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: FieldLabel('Start from a template')),
            if (list.isNotEmpty)
              const Text(
                'Hold to delete',
                style: TextStyle(fontSize: 11, color: AppColors.slate400),
              ),
          ],
        ),
        if (list.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.gold500.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.bookmark_add_outlined,
                  size: 18,
                  color: AppColors.gold600,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No templates yet. Fill the form, then tap the bookmark below to save one.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.slate600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = list[i];
                final on = t.name == _applied;
                return GestureDetector(
                  onLongPress: () => _deleteTemplate(t),
                  child: ChoiceChip(
                    selected: on,
                    onSelected: (_) => _apply(t),
                    showCheckmark: false,
                    avatar: Icon(
                      on
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded,
                      size: 16,
                      color: on ? AppColors.green900 : AppColors.gold600,
                    ),
                    label: Text(t.name),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: on ? AppColors.green900 : AppColors.green800,
                    ),
                    selectedColor: AppColors.gold400,
                    backgroundColor: AppColors.slate50,
                    side: BorderSide(
                      color: on ? AppColors.gold500 : AppColors.slate200,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 14),
      ],
    );
  }

  Future<void> _pick() async {
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
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _photo = bytes);
    } catch (_) {
      if (mounted) toast(context, 'Could not open the photo picker.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _templates(),
          const FieldLabel('Photo'),
          PressScale(
            scale: .98,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _pick,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: _photo == null ? 96 : 170,
                  width: double.infinity,
                  child: _photo == null
                      ? Container(
                          decoration: BoxDecoration(
                            color: AppColors.slate50,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.slate200),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: const Row(
                            children: [
                              IconBadge(Icons.add_a_photo_outlined, size: 48),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Add a photo of the unit',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.green800,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Camera or gallery · optional',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.slate500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: AppColors.slate400,
                              ),
                            ],
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(_photo!, fit: BoxFit.cover),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .55),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Change photo',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // A villa is one unit: its name is all it needs.
          if (_villa)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const FieldLabel('Villa name'),
                TextFormField(
                  controller: _property,
                  decoration: const InputDecoration(hintText: 'e.g. Villa 789'),
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Enter the villa name'
                      : adminState.unitNameTaken(v!)
                      ? 'A unit with this name already exists'
                      : null,
                ),
              ],
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Property'),
                      TextFormField(
                        controller: _property,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter a property'
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FieldLabel('Unit name'),
                      TextFormField(
                        controller: _name,
                        decoration: const InputDecoration(
                          hintText: 'e.g. Unit 503',
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter a name'
                            : adminState.unitNameTaken(v!)
                            ? 'A unit with this name already exists'
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Type'),
                    DropdownField(
                      value: _type,
                      items: _types.values.toList(),
                      onChanged: (v) => setState(() {
                        _type = v;
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FieldLabel('Bedrooms'),
                    DropdownField(
                      value: bedroomLabel(_beds),
                      items: [for (var i = 0; i <= 6; i++) bedroomLabel(i)],
                      onChanged: (v) => setState(() => _beds = bedroomCount(v)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
                        _per,
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
          const SizedBox(height: 22),
          // Same height for both: the template button and the main action.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Save the current settings as a template for the next unit.
                Tooltip(
                  message: 'Save as template',
                  child: PressScale(
                    scale: .94,
                    child: Material(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: const BorderSide(
                          color: AppColors.gold500,
                          width: 1.4,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _saveTemplate,
                        child: const SizedBox(
                          width: 50,
                          child: Icon(
                            Icons.bookmark_add_outlined,
                            color: AppColors.gold600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GoldButton(
                    label: 'Add unit',
                    icon: Icons.add,
                    onPressed: () {
                      if (!_key.currentState!.validate()) return;
                      adminState.addUnit(
                        _property.text.trim(),
                        _type,
                        _villa ? _property.text.trim() : _name.text.trim(),
                        double.parse(_rate.text),
                        _per,
                        photo: _photo,
                        bedrooms: _beds,
                      );
                      popOnce(context);
                      toast(context, 'Unit added');
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
