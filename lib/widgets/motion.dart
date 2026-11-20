import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Turns the decorative animations (entrances, count-ups, pulses) on or off.
/// Tests switch it off so screens settle at once; the phone's own "remove
/// animations" setting switches them off too (see [motionOn]).
bool animateUi = true;

/// True when decorative motion should play here.
bool motionOn(BuildContext context) =>
    animateUi && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

/// Standard timings: quick for small feedback, a bit longer for things that
/// enter the screen. Exits are faster than entrances.
abstract final class Motion {
  static const quick = Duration(milliseconds: 160);
  static const medium = Duration(milliseconds: 260);
  static const enter = Duration(milliseconds: 380);
  static const curve = Curves.easeOutCubic;
}

/// A light tick under the finger for selections (tabs, chips, toggles).
void tick() => HapticFeedback.selectionClick();

/// A firmer tap for main actions (buttons that save or send).
void tap() => HapticFeedback.lightImpact();

/// Marks when a list was first shown, so its items only animate in on that
/// first appearance and not every time they scroll back into view.
class RevealScope extends InheritedWidget {
  const RevealScope({super.key, required this.shownAt, required super.child});
  final DateTime shownAt;

  static DateTime? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RevealScope>()?.shownAt;

  @override
  bool updateShouldNotify(RevealScope old) => old.shownAt != shownAt;
}

/// Fades and lifts its child into place, [index] steps after the list
/// appeared, so a screen's cards arrive one after another.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 18,
  });
  final Widget child;
  final int index;

  /// How far below its place the child starts, in pixels.
  final double offset;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  static const _step = 45; // ms between items
  static const _maxSteps = 8; // later items do not wait longer

  AnimationController? _c;
  Animation<double>? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null) return;
    final shownAt = RevealScope.of(context);
    // Items that appear long after the list (scrolled into view) just show.
    final late =
        shownAt != null &&
        DateTime.now().difference(shownAt) > const Duration(milliseconds: 900);
    if (!motionOn(context) || late) return;
    final delay = _step * widget.index.clamp(0, _maxSteps);
    final total = delay + Motion.enter.inMilliseconds;
    _c = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: total),
    )..forward();
    _t = CurvedAnimation(
      parent: _c!,
      curve: Interval(delay / total, 1, curve: Motion.curve),
    );
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: t.value,
        child: Transform.translate(
          offset: Offset(0, (1 - t.value) * widget.offset),
          child: child,
        ),
      ),
    );
  }
}

/// Text whose first number counts up to its value (e.g. "12", "8/11",
/// "₱45,000.00"), and counts from the old value when it changes.
class CountUpText extends StatefulWidget {
  const CountUpText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.textAlign,
  });
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText> {
  static final _number = RegExp(r'\d[\d,]*(\.\d+)?');
  double _from = 0;

  double? _valueOf(String s) {
    final m = _number.firstMatch(s);
    return m == null ? null : double.tryParse(m[0]!.replaceAll(',', ''));
  }

  @override
  void didUpdateWidget(CountUpText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _from = _valueOf(old.text) ?? 0;
  }

  /// Puts [v] back in place of the number, keeping commas and decimals.
  String _format(double v) {
    final m = _number.firstMatch(widget.text)!;
    final src = m[0]!;
    final decimals = src.contains('.') ? src.split('.')[1].length : 0;
    var s = v.toStringAsFixed(decimals);
    if (src.contains(',')) {
      final p = s.split('.');
      p[0] = p[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );
      s = p.join('.');
    }
    return widget.text.replaceRange(m.start, m.end, s);
  }

  @override
  Widget build(BuildContext context) {
    final to = _valueOf(widget.text);
    Text text(String s) => Text(
      s,
      style: (widget.style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      maxLines: widget.maxLines,
      textAlign: widget.textAlign,
    );
    if (to == null || !motionOn(context)) return text(widget.text);
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.text),
      tween: Tween(begin: _from, end: to),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => text(v == to ? widget.text : _format(v)),
    );
  }
}

/// A soft gold glow that breathes around its child, to draw the eye to
/// something waiting (the alert dots). Still when motion is off.
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child});
  final Widget child;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionOn(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final t = Curves.easeOut.transform(_c.value);
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (_c.isAnimating)
              Transform.scale(
                scale: 1 + t * 1.1,
                child: Opacity(
                  opacity: (1 - t) * .55,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: AppColors.gold400,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            child!,
          ],
        );
      },
    );
  }
}

/// Page change: the new screen slides in a little from the right and fades
/// up; the old one drifts left and dims. Short and calm, not a full swipe.
class SmoothPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!motionOn(context)) return child;
    final inT = CurvedAnimation(
      parent: animation,
      curve: Motion.curve,
      reverseCurve: Curves.easeInCubic,
    );
    final outT = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Motion.curve,
    );
    return SlideTransition(
      position: Tween(
        begin: Offset.zero,
        end: const Offset(-.06, 0),
      ).animate(outT),
      child: FadeTransition(
        opacity: Tween(begin: 1.0, end: .85).animate(outT),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(.12, 0),
            end: Offset.zero,
          ).animate(inT),
          child: FadeTransition(opacity: inT, child: child),
        ),
      ),
    );
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);
}

/// A bell that rings now and then: a quick side-to-side wiggle with a small
/// swell, then a rest, so it catches the eye without being busy. Still when
/// motion is off.
class RingingBell extends StatefulWidget {
  const RingingBell({super.key, required this.child});
  final Widget child;

  @override
  State<RingingBell> createState() => _RingingBellState();
}

class _RingingBellState extends State<RingingBell>
    with SingleTickerProviderStateMixin {
  // One cycle: a short nudge, then a long rest.
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  );
  static const _ring = .064; // about half a second of the 8

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (motionOn(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final p = (_c.value / _ring).clamp(0.0, 1.0); // 0..1 while ringing
        final ringing = _c.value < _ring;
        // Two small tilts that fade out, and a slight swell that
        // rises and settles over the same time.
        final angle = ringing ? math.sin(p * math.pi * 4) * (1 - p) * .12 : 0.0;
        final scale = ringing ? 1 + math.sin(p * math.pi) * .06 : 1.0;
        return Transform.scale(
          scale: scale,
          child: Transform.rotate(
            angle: angle,
            // Swing from the top of the bell, like a real one.
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
  }
}

/// Closes the screen, sheet or popup that [context] belongs to, but only
/// once: a quick second tap on the same Save or Close button does nothing
/// instead of also closing the screen behind it.
void popOnce<T extends Object?>(BuildContext context, [T? result]) {
  final route = ModalRoute.of(context);
  if (route != null && !route.isActive) return;
  Navigator.pop<T>(context, result);
}
