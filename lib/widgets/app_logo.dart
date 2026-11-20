import 'package:flutter/material.dart';

import '../theme.dart';

/// Ivory used for the light faces of the logo and the wordmark.
const logoIvory = Color(0xFFF8F5EE);

/// The logo artwork, cut out of its background (made for dark screens).
const logoMarkAsset = 'assets/images/logo_mark.png';
const logoFullAsset = 'assets/images/logo_full.png';

/// Width / height of each artwork.
const _markAspect = 640 / 408;
const _fullAspect = 1000 / 687;

/// The building mark on its own (headers, chat, app icon).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 74});

  /// Height of the mark; the width follows the artwork's proportions.
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * _markAspect,
      height: size,
      child: Image.asset(
        logoMarkAsset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// The full logo (mark, "AYAN" and "RESIDENCES") with "RENTAL MANAGEMENT"
/// under it, centred.
class AppLogoLockup extends StatelessWidget {
  const AppLogoLockup({super.key, this.width = 200});
  final double width;

  @override
  Widget build(BuildContext context) {
    Widget line(double w, Widget text) =>
        SizedBox(width: w, child: FittedBox(fit: BoxFit.fitWidth, child: text));
    return SizedBox(
      width: width,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: width,
          height: width / _fullAspect,
          child: Image.asset(
            logoFullAsset,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
          ),
        ),
        SizedBox(height: width * .04),
        line(
          width * .62,
          const Text('RENTAL MANAGEMENT',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                  height: 1,
                  color: AppColors.gold400)),
        ),
      ]),
    );
  }
}

/// A tall tower with a window grid and a striped side, a shorter striped
/// tower, and a stepped roofline with a small four-pane window under the
/// peak. Gold and ivory, in the app's colours.
class LogoMarkPainter extends CustomPainter {
  const LogoMarkPainter();

  // Artwork is designed in this box (units are arbitrary).
  static const _x0 = 180.0, _y0 = 280.0, _w = 670.0, _h = 472.0;
  static const aspect = _w / _h;

  // Top edge of the roof, left tip to right tip.
  static const _roof = [
    Offset(188, 744), Offset(305, 662), Offset(350, 692), Offset(505, 574),
    Offset(655, 692), Offset(712, 662), Offset(842, 744),
  ];
  // Bottom edge of the roof band (between the tips).
  static const _roofUnder = [
    Offset(712, 688), Offset(655, 718), Offset(505, 602), Offset(350, 718), Offset(305, 688),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = (size.width / _w) < (size.height / _h) ? size.width / _w : size.height / _h;
    canvas.translate((size.width - _w * s) / 2, (size.height - _h * s) / 2);
    canvas.scale(s);
    canvas.translate(-_x0, -_y0);

    const bounds = Rect.fromLTWH(_x0, _y0, _w, _h);
    final gold = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.gold400, AppColors.gold500, AppColors.gold600],
      ).createShader(bounds);

    // Towers sit behind the roof: clip everything below its top edge.
    canvas.save();
    final above = Path()..moveTo(_x0, _y0)..lineTo(_x0 + _w, _y0)..lineTo(_x0 + _w, 744);
    for (final p in _roof.reversed) {
      above.lineTo(p.dx, p.dy);
    }
    above
      ..lineTo(_x0, 744)
      ..close();
    canvas.clipPath(above);

    _bigTower(canvas, gold);
    _smallTower(canvas);
    canvas.restore();

    // Roof band: thick, tapering to points at both ends.
    final roof = Path()..moveTo(_roof.first.dx, _roof.first.dy);
    for (final p in _roof.skip(1)) {
      roof.lineTo(p.dx, p.dy);
    }
    for (final p in _roofUnder) {
      roof.lineTo(p.dx, p.dy);
    }
    roof.close();
    canvas.drawPath(
        roof,
        Paint()
          ..shader = const LinearGradient(
            colors: [AppColors.gold600, AppColors.gold400, AppColors.gold500, AppColors.gold400, AppColors.gold600],
            stops: [0, .3, .5, .7, 1],
          ).createShader(bounds));

    // Small four-pane window under the peak.
    final ivory = Paint()..color = logoIvory;
    for (final x in [484.0, 512.0]) {
      for (final y in [664.0, 692.0]) {
        canvas.drawRect(Rect.fromLTWH(x, y, 22, 22), ivory);
      }
    }
  }

  /// y of the big tower's slanted top edge at x.
  static double _top(double x) => 404 - (x - 350) * (112 / 155);

  void _bigTower(Canvas canvas, Paint gold) {
    // Front face as a frame of even thickness on every side: the outer
    // outline minus the inner area.
    const l = 350.0, r = 505.0, bottom = 760.0, frame = 14.0;
    final outer = Path()
      ..moveTo(l, _top(l))
      ..lineTo(r, _top(r))
      ..lineTo(r, bottom)
      ..lineTo(l, bottom)
      ..close();
    const il = l + frame, ir = r - frame;
    final inner = Path()
      ..moveTo(il, _top(il) + frame)
      ..lineTo(ir, _top(ir) + frame)
      ..lineTo(ir, bottom)
      ..lineTo(il, bottom)
      ..close();
    canvas.drawPath(Path.combine(PathOperation.difference, outer, inner), gold);

    // Window grid: 2 columns x 4 rows with the same gap everywhere (between
    // the panes and between the panes and the frame), following the slant.
    const gap = 11.0, paneH = 46.0;
    const paneW = (ir - il - 3 * gap) / 2;
    for (final x1 in const [il + gap, il + 2 * gap + paneW]) {
      final x2 = x1 + paneW;
      for (var row = 0; row < 4; row++) {
        final dy = frame + gap + row * (paneH + gap + 6);
        canvas.drawPath(
            Path()
              ..moveTo(x1, _top(x1) + dy)
              ..lineTo(x2, _top(x2) + dy)
              ..lineTo(x2, _top(x2) + dy + paneH)
              ..lineTo(x1, _top(x1) + dy + paneH)
              ..close(),
            gold);
      }
    }

    // Side face: four stripes of equal width, lit (ivory) to shaded (gold).
    _stripes(
        canvas,
        Path()
          ..moveTo(r, _top(r))
          ..lineTo(588, _top(r) + 44)
          ..lineTo(588, bottom)
          ..lineTo(r, bottom)
          ..close(),
        r,
        588,
        const [logoIvory, AppColors.gold400, AppColors.gold500, AppColors.gold600]);
  }

  void _smallTower(Canvas canvas) {
    const l = 600.0, r = 690.0, bottom = 760.0;
    _stripes(
        canvas,
        Path()
          ..moveTo(l, 470)
          ..lineTo(646, 446)
          ..lineTo(r, 466)
          ..lineTo(r, bottom)
          ..lineTo(l, bottom)
          ..close(),
        l,
        r,
        const [AppColors.gold600, AppColors.gold400, AppColors.gold500, logoIvory]);
  }

  /// Fills [shape] with vertical stripes of equal width between [x1] and [x2].
  /// Each stripe is its own clipped rectangle, so the edges stay crisp.
  void _stripes(Canvas canvas, Path shape, double x1, double x2, List<Color> colors) {
    final w = (x2 - x1) / colors.length;
    canvas.save();
    canvas.clipPath(shape);
    for (var i = 0; i < colors.length; i++) {
      // Each stripe overlaps the next a little so no seam shows through.
      canvas.drawRect(Rect.fromLTRB(x1 + i * w, 0, x1 + (i + 1) * w + .8, 2000),
          Paint()..color = colors[i]);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoMarkPainter old) => false;
}
