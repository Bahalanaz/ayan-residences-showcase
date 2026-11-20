import 'package:flutter/material.dart';

import '../state/session.dart';
import '../theme.dart';
import '../widgets/common.dart' show PressScale;
import '../widgets/app_logo.dart';
import '../admin/admin_shell.dart';
import '../admin/admin_state.dart';
import '../state/backend.dart';
import '../state/demo.dart';
import '../state/sync.dart';
import 'shell.dart';

/// Accounts are issued by building management, so there is no sign-up.
/// Demo credentials until a real backend is connected.
const _demoUsername = '123';
const _demoPassword = '123';


/// Replaceable photo for the welcome state (put a new file at this path).
const _buildingAsset = 'assets/images/building.png';

/// One screen, two states driven by a single animation:
///   0.0 = login  (white card up, logo in the header)
///   1.0 = welcome (card lowered, building photo, centered logo, Get started)
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const _headerH = 270.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
    value: 1, // open on the welcome state
  );

  final _key = GlobalKey<FormState>();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _hide = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _toWelcome() {
    FocusScope.of(context).unfocus();
    _c.forward();
  }

  void _toLogin() => _c.reverse();

  Future<void> _login() async {
    // Close the keyboard. Done through the focus manager, which can't fail
    // even if an earlier screen left the keyboard connection in a bad state.
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_key.currentState!.validate()) return;
    try {
      await _signIn();
    } catch (e) {
      // Never leave the button stuck: show what went wrong and let them retry.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not log in. Please try again.';
        });
      }
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!demoData) return _signInOnline();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final user = _user.text.trim().toLowerCase();
    final isAdmin = user == adminUsername && _pass.text == adminPassword;
    final isAccount = adminState.tenants.any(
        (t) => t.username.toLowerCase() == user && t.password == _pass.text);
    final isDemo = demoData && user == _demoUsername && _pass.text == _demoPassword;
    if (isAdmin || isAccount || isDemo) {
      await Session.save(_user.text.trim());
      final account = adminState.tenants.where((t) => t.username.toLowerCase() == user);
      if (!isAdmin) adminState.signInTenant(account.isEmpty ? 'Juan Dela Cruz' : account.first.name); // empty only for the demo login
      if (!mounted) return;
      tabIndex.value = 0;
      adminTab.value = 0;
      Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => isAdmin ? const AdminShell() : const Shell(),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
      ));
    } else {
      setState(() {
        _loading = false;
        _error =
            'Incorrect username or password. Please check the details given by management.';
      });
    }
  }

  /// The real login: checked by Supabase. The admin goes to the admin app,
  /// a tenant to the tenant app, each with their own data loaded.
  Future<void> _signInOnline() async {
    final problem = await backendSignIn(_user.text, _pass.text);
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _loading = false;
        _error = problem;
      });
      return;
    }
    final isAdmin = signedInAsAdmin;
    String? loadProblem;
    try {
      await Sync.load();
      if (!isAdmin && !Sync.hasTenantRecord) {
        loadProblem = 'This login is not linked to a tenant yet. Please contact management.';
      }
    } catch (_) {
      loadProblem = 'Logged in, but the data could not be loaded. Check your internet connection and try again.';
    }
    if (loadProblem != null) {
      await backendSignOut();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = loadProblem;
      });
      return;
    }
    if (!mounted) return;
    tabIndex.value = 0;
    adminTab.value = 0;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, _, _) => isAdmin ? const AdminShell() : const Shell(),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: AppColors.green900,
      body: LayoutBuilder(builder: (context, box) {
        final h = box.maxHeight;
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(_c.value);
            final welcome = _c.value > .5;

            // Logo block: header position -> centered, growing as it moves.
            final loginTop = safeTop + 36;
            // Welcome group: logo 230 + 32 + title 36 + 24 + button 52.
            const groupH = 230 + 32 + 36 + 24 + 52.0;
            final welcomeTop = (h - groupH) / 2;
            final blockTop = loginTop + (welcomeTop - loginTop) * t;
            // Full logo (mark + AYAN RESIDENCES + RENTAL MANAGEMENT) grows
            // from the header size to the welcome size.
            final logoH = 170 + 60 * t;

            final cardTop = _headerH + (h - _headerH) * t;
            final extrasOpacity = ((t - .55) / .45).clamp(0.0, 1.0);
            final photoOpacity = ((t - .1) / .9).clamp(0.0, 1.0);

            return Stack(
              children: [
                // Streaks belong to the login state; hidden on the welcome photo.
                Positioned.fill(
                  child: Opacity(
                    opacity: 1 - t,
                    child: const CustomPaint(painter: _StreakPainter()),
                  ),
                ),

                // Welcome backdrop: the building photo, softened and tinted.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: photoOpacity * .55,
                      child: Image.asset(
                        _buildingAsset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.green900.withValues(alpha: .55 * photoOpacity),
                            AppColors.green900.withValues(alpha: .85 * photoOpacity),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Tap the header background to lower the card.
                if (!welcome)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: _headerH,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toWelcome,
                      child: const SizedBox.expand(),
                    ),
                  ),

                // Logo + brand (moves between header and center).
                Positioned(
                  top: blockTop,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: SizedBox(
                        height: logoH,
                        child: const FittedBox(child: AppLogoLockup(width: 200)),
                      ),
                    ),
                  ),
                ),

                // Welcome extras: Get started! + Login.
                Positioned(
                  top: welcomeTop + 230 + 32,
                  left: 32,
                  right: 32,
                  child: IgnorePointer(
                    ignoring: !welcome,
                    child: Opacity(
                      opacity: extrasOpacity,
                      child: Transform.translate(
                        offset: Offset(0, 24 * (1 - extrasOpacity)),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Column(children: [
                              const Text('Get started!',
                                  style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              const SizedBox(height: 24),
                              _GoldPillButton(label: 'Login', onPressed: _toLogin),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // White login card.
                Positioned(
                  top: cardTop,
                  left: 0,
                  right: 0,
                  height: (h - _headerH).clamp(0, double.infinity),
                  child: _buildCard(),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: LayoutBuilder(builder: (context, box) {
        return SingleChildScrollView(
          // Room for the phone's navigation buttons under the card.
          padding: EdgeInsets.fromLTRB(28, 28, 28, 24 + MediaQuery.paddingOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: (box.maxHeight - 52 - MediaQuery.paddingOf(context).bottom)
                    .clamp(0.0, double.infinity)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _key,
                  child: Column(children: [
                    const Text('Welcome!',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green800)),
                    const SizedBox(height: 4),
                    const Text('Log in with the account given by management',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppColors.slate500)),
                    const SizedBox(height: 24),
                    _PillField(
                      controller: _user,
                      hint: 'Username',
                      icon: Icons.person_rounded,
                      action: TextInputAction.next,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Enter your username' : null,
                    ),
                    const SizedBox(height: 14),
                    _PillField(
                      controller: _pass,
                      hint: 'Password',
                      icon: Icons.lock_rounded,
                      obscure: _hide,
                      action: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                      validator: (v) =>
                          (v ?? '').isEmpty ? 'Enter your password' : null,
                      suffix: IconButton(
                        onPressed: () => setState(() => _hide = !_hide),
                        icon: Icon(
                            _hide
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: AppColors.slate400),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 16, color: AppColors.red),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_error!,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.35,
                                      color: AppColors.red)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    _GoldPillButton(
                        label: 'Log In', loading: _loading, onPressed: _login),
                    const SizedBox(height: 22),
                    const Row(children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.verified_user_outlined,
                            size: 16, color: AppColors.gold600),
                      ),
                      Expanded(child: Divider()),
                    ]),
                    const SizedBox(height: 14),
                    const Text(
                        'This is a private app for Ayan Residences tenants. Accounts are created by the admin. No sign-up is available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.45, color: AppColors.slate500)),
                    // The sample tenant login only exists in the demo.
                    if (demoData) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.slate50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.slate200),
                        ),
                        child: const Text('Demo login  ·  123 / 123',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.slate500)),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _PillField extends StatelessWidget {
  const _PillField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.suffix,
    this.validator,
    this.action,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder b(Color c, [double w = 1.4]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide(color: c, width: w),
        );
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      textInputAction: action,
      onFieldSubmitted: onSubmitted,
      // When the keyboard opens, scroll far enough that the Log In button
      // under the fields stays visible too, not just the field.
      scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 150),
      autocorrect: false,
      enableSuggestions: !obscure,
      style: const TextStyle(
          fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.green800),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14.5, color: AppColors.slate400),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        prefixIcon: Icon(icon, size: 21, color: AppColors.gold600),
        suffixIcon: suffix,
        border: b(AppColors.slate300),
        enabledBorder: b(AppColors.slate300),
        focusedBorder: b(AppColors.gold500, 2),
        errorBorder: b(AppColors.red),
        focusedErrorBorder: b(AppColors.red, 2),
      ),
    );
  }
}

class _GoldPillButton extends StatelessWidget {
  const _GoldPillButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
  });
  final String label;
  final VoidCallback onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      enabled: !loading,
      child: Container(
      width: double.infinity,
      height: 52,
      decoration: BoxDecoration(
        gradient: goldGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
              color: AppColors.gold600.withValues(alpha: .4),
              blurRadius: 14,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: loading ? null : onPressed,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.6, color: AppColors.green900),
                  )
                : Text(label,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.green900)),
          ),
        ),
      ),
      ),
    );
  }
}

/// Navy backdrop with soft diagonal streaks.
class _StreakPainter extends CustomPainter {
  const _StreakPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.green700, AppColors.green900],
        ).createShader(Offset.zero & size),
    );

    const bandH = 270.0;
    void band(double x, double w, double alpha, Color c) {
      final p = Path()
        ..moveTo(x, 0)
        ..lineTo(x + w, 0)
        ..lineTo(x + w - bandH * .55, bandH)
        ..lineTo(x - bandH * .55, bandH)
        ..close();
      canvas.drawPath(p, Paint()..color = c.withValues(alpha: alpha));
    }

    band(size.width * .15, 90, .10, AppColors.green600);
    band(size.width * .55, 140, .08, AppColors.green600);
    band(size.width * .95, 70, .12, AppColors.gold500);
    band(size.width * 1.2, 110, .07, AppColors.green600);

    final line = Paint()
      ..color = AppColors.gold400.withValues(alpha: .35)
      ..strokeWidth = 1.2;
    for (final x in [.30, .62, .88]) {
      canvas.drawLine(Offset(size.width * x, 0),
          Offset(size.width * x - bandH * .55, bandH), line);
    }
  }

  @override
  bool shouldRepaint(_StreakPainter old) => false;
}
