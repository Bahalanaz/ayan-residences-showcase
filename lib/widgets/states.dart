import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

/// How long the demo shows ghost placeholders before the content appears.
/// The real app shows them until the data has arrived from the server.
/// Tests set this to zero.
Duration demoLoadDelay = const Duration(milliseconds: 700);

/// Shows [skeleton] (ghost placeholders) while data loads, then fades to
/// [child]. In the demo the data is instant, so it waits [demoLoadDelay] once
/// each time the screen opens, to show the loading state.
class LoadingSwitch extends StatefulWidget {
  const LoadingSwitch({super.key, required this.skeleton, required this.child});
  final Widget skeleton, child;

  @override
  State<LoadingSwitch> createState() => _LoadingSwitchState();
}

class _LoadingSwitchState extends State<LoadingSwitch> {
  late bool _loading = demoLoadDelay > Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_loading) {
      _timer = Timer(demoLoadDelay, () {
        if (mounted) setState(() => _loading = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOut,
      child: _loading
          ? KeyedSubtree(key: const ValueKey('loading'), child: widget.skeleton)
          : KeyedSubtree(key: const ValueKey('ready'), child: widget.child),
    );
  }
}

/// An IndexedStack that builds each tab the first time it is opened (and
/// keeps it afterwards), so every tab shows its loading state on first visit
/// instead of all of them loading in the background at start-up.
class LazyIndexedStack extends StatefulWidget {
  const LazyIndexedStack({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack>
    with SingleTickerProviderStateMixin {
  final _visited = <int>{};

  /// Plays when the tab changes: the new tab fades in and rises slightly.
  late final _switch = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240), value: 1);
  late final _t = CurvedAnimation(parent: _switch, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(LazyIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && motionOn(context)) _switch.forward(from: 0);
  }

  @override
  void dispose() {
    _switch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _visited.add(widget.index);
    return FadeTransition(
      opacity: _t,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .015), end: Offset.zero).animate(_t),
        child: IndexedStack(
          index: widget.index,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _visited.contains(i) ? widget.children[i] : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

/// A soft light sweep across everything inside it, so grey placeholder shapes
/// read as "loading" rather than as broken.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});
  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

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
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          final dx = rect.width * (-1 + 3 * _c.value);
          return LinearGradient(
            colors: const [Color(0x00FFFFFF), Color(0xB3FFFFFF), Color(0x00FFFFFF)],
            stops: const [.35, .5, .65],
            transform: _SlideGradient(dx),
          ).createShader(rect);
        },
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);
  final double dx;
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(dx, 0, 0);
}

/// One grey placeholder shape (a line of text, an avatar, a pill...).
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 12, this.radius = 6, this.circle = false});
  final double? width;
  final double height, radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: circle ? height : width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.slate200,
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: circle ? null : BorderRadius.circular(radius),
        ),
      );
}

/// A ghost version of a typical list card: avatar, two lines and a status pill.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 18,
      child: Row(children: [
        const Bone(height: 40, circle: true),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Bone(width: 150, height: 13),
            SizedBox(height: 8),
            Bone(width: 220, height: 10),
            SizedBox(height: 10),
            Bone(width: 70, height: 18, radius: 9),
          ]),
        ),
      ]),
    );
  }
}

/// Several ghost cards stacked with the usual spacing.
class SkeletonCards extends StatelessWidget {
  const SkeletonCards({super.key, this.count = 3});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          const SkeletonCard(),
        ],
      ]),
    );
  }
}

/// Ghost version of the two-column photo grid of units.
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: GridView.count(
        padding: EdgeInsets.zero,
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .86,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (var i = 0; i < count; i++)
            Container(
              decoration: BoxDecoration(
                color: AppColors.slate200,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.all(12),
              alignment: Alignment.bottomLeft,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Bone(width: 60, height: 10),
                  SizedBox(height: 8),
                  Bone(width: 90, height: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Ghost chat bubbles, alternating sides.
class SkeletonChat extends StatelessWidget {
  const SkeletonChat({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bubble(bool mine, double w, double h) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: w,
            height: h,
            margin: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.slate200.withValues(alpha: .85),
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        );
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 8),
        child: Column(children: [
          bubble(false, 220, 54),
          bubble(true, 170, 40),
          bubble(false, 250, 74),
          bubble(true, 200, 54),
          bubble(false, 140, 40),
        ]),
      ),
    );
  }
}

/// "Nothing here yet", with an icon, a short explanation and an optional
/// action. [onDark] picks light text for the green background.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.onDark = true,
  });
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold500.withValues(alpha: onDark ? .16 : .14),
            border: Border.all(color: AppColors.gold500.withValues(alpha: .35)),
          ),
          child: Icon(icon, size: 30, color: AppColors.gold500),
        ),
        const SizedBox(height: 14),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: onDark ? Colors.white : AppColors.green800)),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: onDark ? AppColors.slate300 : AppColors.slate500)),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          GoldButton(label: actionLabel!, onPressed: onAction, compact: true, expand: false),
        ],
      ]),
    );
  }
}

/// Something went wrong (no connection, server error) with a retry button.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = "Couldn't load this",
    this.message = 'Check your connection and try again.',
    required this.onRetry,
    this.onDark = true,
  });
  final String title, message;
  final VoidCallback onRetry;
  final bool onDark;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: title,
        message: message,
        actionLabel: 'Try again',
        onAction: onRetry,
        onDark: onDark,
      );
}
