import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';
import 'motion.dart';
import 'picker.dart';
export 'motion.dart';
export 'picker.dart';
export 'states.dart';

/// Money in pesos, or in dirhams ([dhs]) for villas: "₱8,000.00" or
/// "AED 24,000.00".
String peso(double v, {bool dhs = false}) {
  final s = v.abs().toStringAsFixed(2);
  final parts = s.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return '${v < 0 ? '-' : ''}${dhs ? 'AED ' : '₱'}$whole.${parts[1]}';
}

/// The currency sign for a form label: "₱" or "AED".
String currencySign(bool dhs) => dhs ? 'AED' : '₱';

void toast(BuildContext context, String message) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 3500),
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.gold400, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// Makes whatever it wraps sink slightly while a finger is on it, then spring
/// back. It only watches the pointer, so the child's own tap handling is
/// untouched. Use it on buttons and tappable cards.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = .965,
  });
  final Widget child;
  final bool enabled;

  /// Size while pressed (1 = no change).
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;
  Offset? _start;
  Timer? _hold;

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  void _press(PointerDownEvent e) {
    if (!widget.enabled) return;
    _hold?.cancel();
    _start = e.position;
    setState(() => _down = true);
  }

  /// Springs back; a quick tap is held for a moment so the sink is visible.
  void _release() {
    if (!_down) return;
    _hold?.cancel();
    _hold = Timer(const Duration(milliseconds: 70), () {
      if (mounted) setState(() => _down = false);
    });
  }

  void _move(PointerMoveEvent e) {
    // The finger moved away (scrolling or dragging): stop looking pressed.
    if (_down && _start != null && (e.position - _start!).distance > 12) {
      setState(() => _down = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _press,
      onPointerMove: _move,
      onPointerUp: (_) => _release(),
      onPointerCancel: (_) => _release(),
      child: AnimatedScale(
        scale: _down && widget.enabled ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// White rounded card used throughout the app.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = Colors.white,
    this.border,
    this.radius = 22,
  });
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color;
  final BoxBorder? border;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    // A soft, layered shadow (a wide ambient one and a tight contact one)
    // reads as "lifted paper" on the dark green, without a hard edge.
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: r,
        border: border ?? Border.all(color: Colors.white.withValues(alpha: .6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: r,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    // Only cards that can be tapped sink; plain cards stay still. A gentler
    // sink for cards, since they are bigger than buttons.
    return onTap == null ? card : PressScale(scale: .975, child: card);
  }
}

class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    required this.fg,
    required this.bg,
    this.border,
  });
  final String text;
  final Color fg, bg;
  final Color? border;

  factory Pill.pending(String t) => Pill(
    t,
    fg: AppColors.amber,
    bg: AppColors.amberBg,
    border: const Color(0xFFE8D5A0),
  );
  factory Pill.verified(String t) => Pill(
    t,
    fg: const Color(0xFF1F6045),
    bg: AppColors.emeraldBg,
    border: const Color(0xFFB7DEC3),
  );
  factory Pill.urgent(String t) => Pill(
    t,
    fg: AppColors.red,
    bg: AppColors.redBg,
    border: const Color(0xFFFECACA),
  );
  factory Pill.info(String t) =>
      Pill(t, fg: AppColors.blue, bg: AppColors.blueBg);
  factory Pill.neutral(String t) =>
      Pill(t, fg: AppColors.slate600, bg: AppColors.slate100);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          letterSpacing: .4,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class ScreenHeader extends StatelessWidget {
  const ScreenHeader(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.2,
                  letterSpacing: -.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      color: AppColors.slate300,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ?action,
      ],
    );
  }
}

/// Stops a button from running twice when it is tapped quickly or
/// repeatedly: taps are ignored while its action is still running (async
/// actions included) and for a short moment after.
mixin TapGuard<T extends StatefulWidget> on State<T> {
  bool _running = false;
  Duration? _last;

  // The app's own frame clock (taps always draw a frame), not the wall
  // clock, so the short pause after a tap also holds in tests.
  static Duration get _now =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp;

  /// The button became a different one (same spot, new label): a tap on
  /// it is a new tap, not a repeat of the old button's.
  void resetGuard() => _last = null;

  Future<void> guarded(FutureOr<void> Function() action) async {
    final now = _now, last = _last;
    if (_running ||
        (last != null && now - last < const Duration(milliseconds: 700))) {
      return;
    }
    _running = true;
    _last = now;
    tap();
    try {
      await action();
    } finally {
      _running = false;
      _last = _now;
    }
  }
}

/// Runs [work] behind a small "please wait" box that covers the screen, so a
/// slow action shows it is happening and cannot be started twice. Returns
/// false when another one was already running (nothing was done).
bool _busyShown = false;
Future<bool> runBusy(
  BuildContext context,
  String message,
  Future<void> Function() work,
) async {
  if (_busyShown) return false;
  _busyShown = true;
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.gold500,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.green800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  try {
    await work();
  } finally {
    _busyShown = false;
    nav.pop();
  }
  return true;
}

class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = false,
    this.expand = true,
  });
  final String label;

  /// May be async: the button ignores taps until it finishes.
  final FutureOr<void> Function()? onPressed;
  final IconData? icon;
  final bool compact, expand;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> with TapGuard {
  @override
  void didUpdateWidget(GoldButton old) {
    super.didUpdateWidget(old);
    if (old.label != widget.label) resetGuard();
  }

  @override
  Widget build(BuildContext context) {
    final GoldButton(:label, :onPressed, :icon, :compact, :expand) = widget;
    final enabled = onPressed != null;
    return PressScale(
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : .5,
        child: Container(
          width: expand ? double.infinity : null,
          decoration: BoxDecoration(
            gradient: goldGradient,
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(compact ? 12 : 14),
              onTap: onPressed == null ? null : () => guarded(onPressed),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 16,
                  vertical: compact ? 8 : 13,
                ),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon case final i?) ...[
                      Icon(
                        i,
                        size: compact ? 14 : 16,
                        color: AppColors.green900,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.green900,
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 12 : 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NavyButton extends StatefulWidget {
  const NavyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;

  /// May be async: the button ignores taps until it finishes.
  final FutureOr<void> Function() onPressed;
  final IconData? icon;

  @override
  State<NavyButton> createState() => _NavyButtonState();
}

class _NavyButtonState extends State<NavyButton> with TapGuard {
  @override
  Widget build(BuildContext context) {
    final NavyButton(:label, :icon) = widget;
    return PressScale(
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold500,
            foregroundColor: AppColors.green900,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: () => guarded(widget.onPressed),
          icon: icon == null
              ? const SizedBox.shrink()
              : Icon(icon, size: 16, color: AppColors.green900),
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: 2),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: AppColors.slate600,
      ),
    ),
  );
}

/// A tappable field that opens the selection sheet ([showPicker]). Pass plain
/// [items], or richer [options] (icons, subtitles, badges, groups) for long
/// lists; the sheet adds search automatically once there are many.
class DropdownField extends StatelessWidget {
  const DropdownField({
    super.key,
    required this.value,
    this.items = const [],
    this.options,
    required this.onChanged,
    this.title = 'Choose',
  });
  final String value;
  final List<String> items;
  final List<PickerOption>? options;
  final ValueChanged<String> onChanged;
  final String title;

  List<PickerOption> get _options =>
      options ?? [for (final i in items) PickerOption(value: i, label: i)];

  @override
  Widget build(BuildContext context) {
    final opts = _options;
    final current = opts.where((o) => o.value == value).firstOrNull;
    return PressScale(
      scale: .985,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showPicker(
            context,
            title: title,
            options: opts,
            selected: value,
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            suffixIcon: Icon(
              Icons.keyboard_arrow_down,
              color: AppColors.slate500,
            ),
          ),
          child: Text(
            current?.label ?? value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: AppColors.green800),
          ),
        ),
      ),
    );
  }
}

/// Simulated media picker: tap to "attach" a photo/video, shows removable chips.
class AttachmentPicker extends StatelessWidget {
  const AttachmentPicker({
    super.key,
    required this.files,
    required this.onAdd,
    required this.onRemove,
    required this.title,
    required this.hint,
    this.icon = Icons.photo_camera_outlined,
    this.photos,
  });
  final List<String> files;

  /// Picked photos to preview (instead of file names in [files]).
  final List<Uint8List>? photos;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final String title, hint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final shots = photos ?? const <Uint8List>[];
    // With photos picked: a tidy grid of square tiles, the last one adds more.
    if (shots.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, box) {
          const gap = 10.0;
          final size = (box.maxWidth - gap * 2) / 3;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < shots.length; i++)
                    SizedBox.square(
                      dimension: size,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.slate200),
                              color: AppColors.slate50,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.memory(shots[i], fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => onRemove(i),
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: .55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox.square(
                    dimension: size,
                    child: InkWell(
                      onTap: onAdd,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.slate50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.gold500.withValues(alpha: .6),
                            width: 1.5,
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 26,
                              color: AppColors.gold600,
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Add more',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gold600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${shots.length} ${shots.length == 1 ? 'photo' : 'photos'} added · tap × to remove',
                style: const TextStyle(fontSize: 12, color: AppColors.slate500),
              ),
            ],
          );
        },
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PressScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onAdd,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.slate200, width: 2),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 28, color: AppColors.gold500),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.slate600,
                    ),
                  ),
                  Text(
                    hint,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.slate400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (photos == null && files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < files.length; i++)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.green800.withValues(alpha: .06),
                    side: BorderSide.none,
                    avatar: Icon(
                      files[i].endsWith('.mp4')
                          ? Icons.videocam_outlined
                          : Icons.image_outlined,
                      size: 16,
                      color: AppColors.gold600,
                    ),
                    label: Text(files[i], style: const TextStyle(fontSize: 11)),
                    onDeleted: () => onRemove(i),
                    deleteIconColor: AppColors.slate500,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet wrapper that handles the keyboard + header.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget Function(BuildContext) builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        // Keep the last button clear of the phone's own navigation buttons
        // (the three-button bar), which the sheet would otherwise sit under.
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          20 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slate200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => popOnce(ctx),
                  icon: const Icon(Icons.close, color: AppColors.slate500),
                ),
              ],
            ),
            const Divider(height: 8),
            const SizedBox(height: 10),
            builder(ctx),
          ],
        ),
      ),
    ),
  );
}

class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.size = 36, this.fg, this.bg});
  final IconData icon;
  final double size;
  final Color? fg, bg;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      // A warm gold wash, a little deeper at the bottom-right.
      gradient: bg != null
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.gold400.withValues(alpha: .22),
                AppColors.gold500.withValues(alpha: .34),
              ],
            ),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(icon, size: size * .5, color: fg ?? AppColors.gold700),
  );
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.k, this.v, {super.key, this.last = false});
  final String k, v;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppColors.slate100)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: const TextStyle(fontSize: 12, color: AppColors.slate400),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            v,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.green800,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A row of tabs with a gold pill that slides to the chosen one.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.light = false,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  /// Light style for use on white sheets and cards.
  final bool light;

  @override
  Widget build(BuildContext context) {
    // A long label (e.g. "Property Maintenance") gets a wider tab.
    final flex = [for (final l in labels) l.length > 14 ? 3 : 2];
    final total = flex.fold<int>(0, (a, b) => a + b);
    final before = flex
        .take(index.clamp(0, labels.length))
        .fold<int>(0, (a, b) => a + b);
    final on = motionOn(context);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: light ? AppColors.slate100 : AppColors.green900,
        border: light ? Border.all(color: AppColors.slate200) : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final unit = box.maxWidth / total;
          return Stack(
            children: [
              if (index >= 0 && index < labels.length)
                AnimatedPositioned(
                  duration: on ? Motion.medium : Duration.zero,
                  curve: Curves.easeOutBack,
                  left: unit * before,
                  width: unit * flex[index],
                  top: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: light ? goldGradient : null,
                      color: light ? null : AppColors.gold500,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      flex: flex[i],
                      child: PressScale(
                        scale: .95,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (i != index) tick();
                            onChanged(i);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Center(
                              // Long labels shrink a little rather than overflow.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: AnimatedDefaultTextStyle(
                                  duration: on ? Motion.quick : Duration.zero,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: i == index
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: i == index
                                        ? AppColors.green900
                                        : (light
                                              ? AppColors.slate600
                                              : AppColors.slate300),
                                  ),
                                  child: Text(labels[i], maxLines: 1),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Asks "are you sure?" before something that can't easily be undone.
/// Returns true when the admin picks [action].
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool danger = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(
        message,
        style: const TextStyle(
          fontSize: 13.5,
          height: 1.4,
          color: AppColors.slate600,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => popOnce(ctx, false),
          child: const Text(
            'Back',
            style: TextStyle(
              color: AppColors.slate500,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: () => popOnce(ctx, true),
          child: Text(
            action,
            style: TextStyle(
              color: danger ? AppColors.red : AppColors.green800,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A search box for the top of a list.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search'});
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    style: const TextStyle(fontSize: 14, color: AppColors.green800),
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.slate400),
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
    ),
  );
}

/// True when [query] is empty or every word of it appears in one of [fields].
bool matchesSearch(String query, List<String> fields) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final hay = fields.join(' ').toLowerCase();
  return q.split(RegExp(r'\s+')).every(hay.contains);
}
