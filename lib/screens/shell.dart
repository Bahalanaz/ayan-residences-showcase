import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../state/backend.dart';
import '../state/sync.dart';
import '../theme.dart';
import '../widgets/common.dart'
    show LazyIndexedStack, PressScale, demoLoadDelay, Reveal, RevealScope, Motion, motionOn, tick;
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'more_screen.dart';
import 'notice_popup.dart';
import 'notices_screen.dart';

/// Lets any screen switch the bottom-nav tab.
final tabIndex = ValueNotifier<int>(0);

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  @override
  void initState() {
    super.initState();
    // Opening the app with an unread notice shows the latest one as a popup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showLatestNoticePopup(context);
    });
  }

  static const _pages = <Widget>[
    HomeScreen(),
    CalendarScreen(),
    NoticesScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: tabIndex,
      builder: (context, i, _) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: LazyIndexedStack(index: i, children: _pages),
            ),
          ),
        ),
        bottomNavigationBar: _BottomNav(index: i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, 'Home'),
      (Icons.calendar_month_rounded, 'Calendar'),
      (Icons.campaign_rounded, 'Notices'),
      (Icons.person_rounded, 'Account'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.greenDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
            top: BorderSide(color: AppColors.gold500.withValues(alpha: .45), width: 1.2)),
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Row(
            children: [
              for (var n = 0; n < items.length; n++)
                Expanded(
                  child: PressScale(
                    scale: .92,
                    child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      if (tabIndex.value != n) tick();
                      tabIndex.value = n;
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListenableBuilder(
                          listenable: appState,
                          builder: (_, _) {
                            final selected = n == index;
                            // Notices shows how many are still unread.
                            final count = n == 2 ? appState.pendingAcks : 0;
                            final badge = count > 0;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: selected ? goldGradient : null,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Badge(
                                isLabelVisible: badge,
                                backgroundColor: selected
                                    ? AppColors.green900
                                    : AppColors.gold500,
                                textColor:
                                    selected ? AppColors.gold400 : AppColors.green900,
                                label: Text('$count'),
                                child: AnimatedScale(
                                  scale: selected ? 1.12 : 1,
                                  duration: motionOn(context) ? Motion.medium : Duration.zero,
                                  curve: Curves.easeOutBack,
                                  child: Icon(items[n].$1,
                                      size: 24,
                                      color: selected
                                          ? AppColors.green900
                                          : AppColors.slate300),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                            duration: Motion.quick,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  n == index ? FontWeight.w800 : FontWeight.w500,
                              color: n == index ? AppColors.gold400 : AppColors.slate300,
                            ),
                            child: Text(items[n].$2)),
                      ],
                    ),
                  ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scaffold used by pushed (non-tab) screens.
class SubPage extends StatelessWidget {
  const SubPage({super.key, required this.title, required this.children, this.bottom});
  final String title;
  final List<Widget> children;

  /// Pinned to the bottom of the screen (usually the main action).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.green800,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), child: bottom),
                ),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: _RevealList(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// A scrolling column whose items fade up one after another the first time
/// it is shown.
class _RevealList extends StatefulWidget {
  const _RevealList({required this.padding, required this.children, this.alwaysScroll = false});
  final EdgeInsets padding;
  final List<Widget> children;
  final bool alwaysScroll;

  @override
  State<_RevealList> createState() => _RevealListState();
}

class _RevealListState extends State<_RevealList> {
  final _shownAt = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return RevealScope(
      shownAt: _shownAt,
      child: ListView(
        physics: widget.alwaysScroll ? const AlwaysScrollableScrollPhysics() : null,
        // Dragging the page closes the keyboard, uncovering what is below.
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: widget.padding,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Reveal(index: i, child: widget.children[i]),
            ),
        ],
      ),
    );
  }
}

/// Standard scrolling body for tab screens.
class TabBody extends StatelessWidget {
  const TabBody({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    // Pull down to refresh. The demo has nothing to fetch, so it just waits a
    // moment; the real app re-loads from the server here.
    return RefreshIndicator(
      color: AppColors.green900,
      backgroundColor: AppColors.gold400,
      onRefresh: () async {
        if (backendOn) {
          try {
            await Sync.flush();
            await Sync.load();
          } catch (_) {
            messengerKey.currentState?.showSnackBar(
                const SnackBar(content: Text('Could not refresh. Check your internet connection.')));
          }
        } else {
          await Future<void>.delayed(
              demoLoadDelay == Duration.zero ? Duration.zero : const Duration(milliseconds: 800));
        }
      },
      child: _RevealList(
        alwaysScroll: true,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: children,
      ),
    );
  }
}
