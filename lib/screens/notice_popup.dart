import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme.dart';
import 'notices_screen.dart' show CheckPainter, RingPainter;

/// How long the tenant must wait before "Mark as read" unlocks.
const _readDelay = Duration(seconds: 3);
bool _popupOpen = false;

/// Shown when the tenant opens the app with an unread notice. It can't be
/// dismissed until the notice is marked as read, and the button only unlocks
/// after [_readDelay] so the notice actually gets read.
Future<void> showLatestNoticePopup(BuildContext context) async {
  final unread = appState.notices.where((n) => !n.acknowledged);
  if (unread.isEmpty || _popupOpen) return;
  _popupOpen = true;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'New notice',
    barrierColor: Colors.black.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, _, _) => _NoticePopup(unread.first),
    transitionBuilder: (_, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(begin: .88, end: 1).animate(curved),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, .06), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
  _popupOpen = false;
}

class _NoticePopup extends StatefulWidget {
  const _NoticePopup(this.notice);
  final Notice notice;
  @override
  State<_NoticePopup> createState() => _NoticePopupState();
}

class _NoticePopupState extends State<_NoticePopup> with TickerProviderStateMixin {
  late final AnimationController _wait =
      AnimationController(vsync: this, duration: _readDelay)..forward();
  late final AnimationController _done =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
        ..repeat();
  bool _marked = false;

  @override
  void dispose() {
    _wait.dispose();
    _done.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _mark() async {
    if (_marked || !_wait.isCompleted) return;
    setState(() => _marked = true);
    HapticFeedback.lightImpact();
    appState.acknowledge(widget.notice);
    await _done.forward();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notice;
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.green700, AppColors.green900],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.gold500.withValues(alpha: .55)),
              boxShadow: [
                BoxShadow(
                    color: AppColors.gold500.withValues(alpha: .18),
                    blurRadius: 40,
                    spreadRadius: 2),
                const BoxShadow(
                    color: Colors.black54, blurRadius: 30, offset: Offset(0, 14)),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(children: [
              // Soft gold glow in the corner.
              Positioned(
                top: -60,
                right: -60,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      AppColors.gold500.withValues(alpha: .22),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, _) => CustomPaint(
                        painter: RingPainter(_pulse.value, 84, 32),
                        child: Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: const BoxDecoration(
                                shape: BoxShape.circle, gradient: goldGradient),
                            child: const Icon(Icons.notifications_active_rounded,
                                size: 32, color: AppColors.green900),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('NEW NOTICE',
                      style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w800,
                          color: AppColors.gold400)),
                  const SizedBox(height: 12),
                  Text(n.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 20,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: Text(n.body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: AppColors.slate300)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(n.date,
                      style: const TextStyle(fontSize: 12, color: AppColors.slate400)),
                  const SizedBox(height: 22),
                  _ReadButton(wait: _wait, done: _done, onTap: _mark),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Locked for [_readDelay] with a gold progress line, then unlocks as a gold
/// button. On tap it collapses to a circle, draws a check, then the popup closes.
class _ReadButton extends StatelessWidget {
  const _ReadButton({required this.wait, required this.done, required this.onTap});
  final AnimationController wait, done;
  final VoidCallback onTap;

  static const _h = 52.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final full = box.maxWidth;
      return AnimatedBuilder(
        animation: Listenable.merge([wait, done]),
        builder: (context, _) {
          final ready = wait.isCompleted;
          final secs = (_readDelay.inSeconds * (1 - wait.value)).ceil();
          final d = done.value;
          final collapse = Curves.easeInOutCubic.transform((d / .3).clamp(0.0, 1.0));
          final check = Curves.easeOut.transform(((d - .3) / .35).clamp(0.0, 1.0));
          final ring = Curves.easeOut.transform(((d - .35) / .5).clamp(0.0, 1.0));
          final width = full + (_h - full) * collapse;
          final marked = d > 0;

          return SizedBox(
            height: _h + 8,
            child: Center(
              child: CustomPaint(
                foregroundPainter: RingPainter(ring, width, 26),
                child: GestureDetector(
                  onTap: ready && !marked ? onTap : null,
                  child: Container(
                    width: width,
                    height: _h,
                    decoration: BoxDecoration(
                      gradient: ready ? goldGradient : null,
                      color: ready ? null : Colors.white.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                          color: ready
                              ? Colors.transparent
                              : Colors.white.withValues(alpha: .18)),
                      boxShadow: ready
                          ? [
                              BoxShadow(
                                  color: AppColors.gold600.withValues(alpha: .45),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6))
                            ]
                          : null,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(alignment: Alignment.center, children: [
                      if (!ready)
                        Align(
                          alignment: Alignment.bottomLeft,
                          child: FractionallySizedBox(
                            widthFactor: wait.value,
                            child: Container(height: 3, color: AppColors.gold400),
                          ),
                        ),
                      if (!marked)
                        Text(ready ? 'Mark as read' : 'Please read...  $secs',
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: ready
                                    ? AppColors.green900
                                    : AppColors.slate300))
                      else
                        CustomPaint(
                          size: const Size(24, 24),
                          painter: CheckPainter(check, AppColors.green900),
                        ),
                    ]),
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
