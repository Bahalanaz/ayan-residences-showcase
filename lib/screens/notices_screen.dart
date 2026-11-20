import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'shell.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});
  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => TabBody(children: [
        const ScreenHeader('Announcements & Rules'),
        SegmentedTabs(
          labels: const ['Notices', 'House Rules'],
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        LoadingSwitch(
          skeleton: const SkeletonCards(),
          child: _tab == 0 ? _notices(context) : const _Rules(),
        ),
      ]),
    );
  }

  Widget _notices(BuildContext context) {
    final list = appState.notices;
    if (list.isEmpty) {
      return const EmptyState(
          icon: Icons.campaign_outlined,
          title: 'No notices yet',
          message: 'Announcements from management will appear here.');
    }
    return Column(children: [
      for (final n in list) Padding(padding: const EdgeInsets.only(bottom: 14), child: _NoticeCard(n)),
    ]);
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard(this.n);
  final Notice n;

  @override
  Widget build(BuildContext context) {
    // Acknowledged notices soften: grey card, dimmed text.
    final read = n.acknowledged;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: read ? const Color(0xFFE6EBDF) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: read ? .12 : .26),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            opacity: read ? .62 : 1,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.date,
                  style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
              const SizedBox(height: 6),
              Text(n.title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.green800)),
              const SizedBox(height: 4),
              Text(n.body,
                  style: const TextStyle(
                      fontSize: 12, height: 1.4, color: AppColors.slate600)),
            ]),
          ),
          if (n.requiresAck) ...[
            const SizedBox(height: 10),
            AckButton(key: ValueKey(n.id), notice: n),
          ],
        ]),
      ),
    );
  }
}

/// "Acknowledge Notice" button. On tap it collapses into a gold circle, draws a
/// white check with a pulse ring, then slides to the bottom-right as a small
/// gold check circle.
class AckButton extends StatefulWidget {
  const AckButton({super.key, required this.notice});
  final Notice notice;

  @override
  State<AckButton> createState() => _AckButtonState();
}

class _AckButtonState extends State<AckButton>
    with SingleTickerProviderStateMixin {
  static const _h = 22.0;
  static const _full = 44.0;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
    value: widget.notice.acknowledged ? 1 : 0,
  );

  @override
  void didUpdateWidget(AckButton old) {
    super.didUpdateWidget(old);
    // Acknowledged somewhere else (e.g. the popup): jump to the done state.
    if (widget.notice.acknowledged && !_c.isAnimating && _c.value < 1) {
      _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap() {
    if (_c.isAnimating || widget.notice.acknowledged) return;
    HapticFeedback.lightImpact();
    appState.acknowledge(widget.notice);
    _c.forward(from: 0);
  }

  static double _seg(double t, double a, double b) =>
      ((t - a) / (b - a)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final full = box.maxWidth;
      return AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final collapse = Curves.easeInOutCubic.transform(_seg(t, 0, .25));
          final check = Curves.easeOut.transform(_seg(t, .25, .5));
          final ring = Curves.easeOut.transform(_seg(t, .3, .62));
          final slide = Curves.easeInOutCubic.transform(_seg(t, .62, 1));

          final width = full + (_h - full) * collapse;
          final height = _full + (_h - _full) * collapse;
          final align = Alignment.lerp(Alignment.center, Alignment.centerRight, slide)!;
          final label = (1 - _seg(t, 0, .12));

          return SizedBox(
            height: _full,
            child: Align(
              alignment: align,
              child: CustomPaint(
                foregroundPainter: RingPainter(ring, width),
                child: GestureDetector(
                  onTap: _tap,
                  child: Container(
                    width: width,
                    height: height,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: goldGradient,
                      borderRadius: BorderRadius.circular(14 - 3 * collapse),
                    ),
                    child: ClipRect(
                      child: t < .25
                          ? Opacity(
                              opacity: label,
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.task_alt,
                                      size: 16, color: AppColors.green900),
                                  SizedBox(width: 8),
                                  Text('Acknowledge Notice',
                                      maxLines: 1,
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.green900)),
                                ],
                              ),
                            )
                          : Center(
                              child: CustomPaint(
                                size: const Size(12, 12),
                                painter: CheckPainter(check, Colors.white),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

class CheckPainter extends CustomPainter {
  CheckPainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .2, size.height * .53)
      ..lineTo(size.width * .43, size.height * .75)
      ..lineTo(size.width * .82, size.height * .28);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(CheckPainter o) => o.progress != progress || o.color != color;
}

class RingPainter extends CustomPainter {
  RingPainter(this.progress, this.width, [this.base = 11.0]);
  final double base;
  final double progress, width;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.gold400.withValues(alpha: (1 - progress) * .8);
    canvas.drawCircle(size.center(Offset.zero), base + base * .73 * progress, paint);
  }

  @override
  bool shouldRepaint(RingPainter o) => o.progress != progress;
}

class _Rules extends StatelessWidget {
  const _Rules();

  // Listens itself: as a const widget it is not rebuilt with the screen, so
  // rules the admin adds would only show after leaving the tab.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (context, _) => _content(context),
      );

  Widget _content(BuildContext context) {
    final rules = appState.rules;
    return Column(children: [
      AppCard(
        radius: 22,
        child: Row(children: [
          const IconBadge(Icons.menu_book_outlined, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Policy handbook',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.green800)),
              Text('Ayan Residences · ${rules.length} rules',
                  style: const TextStyle(fontSize: 12, color: AppColors.slate500)),
            ]),
          ),
        ]),
      ),
      for (var i = 0; i < rules.length; i++) ...[
        const SizedBox(height: 14),
        AppCard(
          radius: 20,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration:
                  const BoxDecoration(gradient: goldGradient, shape: BoxShape.circle),
              child: Text('${i + 1}',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.green900)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(rules[i].title,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.green800)),
                const SizedBox(height: 3),
                Text(rules[i].body,
                    style: const TextStyle(
                        fontSize: 13, height: 1.4, color: AppColors.slate600)),
              ]),
            ),
          ]),
        ),
      ],
    ]);
  }
}
