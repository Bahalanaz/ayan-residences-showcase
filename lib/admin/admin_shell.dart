import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart' show LazyIndexedStack, PressScale, Motion, motionOn, tick, tap;
import 'admin_state.dart';
import 'screens/admin_more_screen.dart';
import 'screens/accounts_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/calendar_admin_screen.dart';
import 'screens/finance_screen.dart';

/// Lets any admin screen switch the bottom-nav tab.
final adminTab = ValueNotifier<int>(0);

class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  static const _pages = <Widget>[
    DashboardScreen(),
    AccountsScreen(),
    FinanceScreen(),
    CalendarAdminScreen(),
    AdminMoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: adminTab,
      builder: (context, i, _) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: LazyIndexedStack(index: i, children: _pages),
            ),
          ),
        ),
        bottomNavigationBar: _AdminNav(index: i),
      ),
    );
  }
}

class _AdminNav extends StatelessWidget {
  const _AdminNav({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.dashboard_rounded, 'Dashboard'),
      (Icons.manage_accounts_rounded, 'Accounts'),
      (Icons.insights_rounded, 'Finance'),
      (Icons.calendar_month_rounded, 'Calendar'),
      (Icons.grid_view_rounded, 'More'),
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
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
          child: ListenableBuilder(
            listenable: adminState,
            builder: (_, _) {
              final badges = [0, adminState.missingLeases, 0, 0, 0];
              return Row(children: [
                for (var n = 0; n < items.length; n++)
                  if (n == 2)
                    // Finance: the main overview, a raised gold button.
                    Expanded(
                        child: _CenterButton(
                            selected: index == 2,
                            onTap: () {
                              if (adminTab.value != 2) tap();
                              adminTab.value = 2;
                            }))
                  else
                  Expanded(
                    child: PressScale(
                      scale: .92,
                      child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        if (adminTab.value != n) tick();
                        adminTab.value = n;
                      },
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: n == index ? goldGradient : null,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Badge(
                            isLabelVisible: badges[n] > 0 && n != 0,
                            backgroundColor:
                                n == index ? AppColors.green900 : AppColors.gold500,
                            textColor: n == index ? AppColors.gold400 : AppColors.green900,
                            label: Text('${badges[n]}'),
                            child: AnimatedScale(
                              scale: n == index ? 1.12 : 1,
                              duration: motionOn(context) ? Motion.medium : Duration.zero,
                              curve: Curves.easeOutBack,
                              child: Icon(items[n].$1,
                                  size: 22,
                                  color: n == index
                                      ? AppColors.green900
                                      : AppColors.slate300),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                            duration: Motion.quick,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: n == index ? FontWeight.w800 : FontWeight.w500,
                              color: n == index ? AppColors.gold400 : AppColors.slate300,
                            ),
                            child: Text(items[n].$2)),
                      ]),
                    ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}

/// The raised round button in the middle of the admin bar (Finance).
class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.selected, required this.onTap});
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      scale: .92,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // Same height as the other tabs; the circle rises above the bar.
        child: SizedBox(
          height: 52,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
            AnimatedPositioned(
              duration: motionOn(context) ? Motion.medium : Duration.zero,
              curve: Curves.easeOutBack,
              // Lifts a little higher while Finance is open.
              top: selected ? -30 : -26,
              child: AnimatedContainer(
                duration: motionOn(context) ? Motion.medium : Duration.zero,
                curve: Curves.easeOut,
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  gradient: goldGradient,
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? Colors.white : AppColors.greenDeep, width: 4),
                  boxShadow: [
                    const BoxShadow(color: Colors.black45, blurRadius: 12, offset: Offset(0, 4)),
                    if (selected)
                      BoxShadow(color: AppColors.gold500.withValues(alpha: .55), blurRadius: 22, spreadRadius: 1),
                  ],
                ),
                child: AnimatedRotation(
                  turns: selected ? 0 : -.05,
                  duration: motionOn(context) ? Motion.medium : Duration.zero,
                  curve: Curves.easeOutBack,
                  child: const Icon(Icons.insights_rounded, size: 28, color: AppColors.green900),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              child: AnimatedDefaultTextStyle(
                  duration: Motion.quick,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? AppColors.gold400 : AppColors.slate300,
                  ),
                  child: const Text('Finance')),
            ),
          ]),
        ),
      ),
    );
  }
}
