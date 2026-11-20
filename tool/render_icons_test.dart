// Regenerates the app icons from the logo artwork (assets/images/logo_mark.png).
// Run after changing the logo:  flutter test tool/render_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';


/// The logo mark, decoded once.
ui.Image? _mark;
Future<ui.Image> _logo() async {
  if (_mark != null) return _mark!;
  final codec = await ui.instantiateImageCodec(
      File('assets/images/logo_mark.png').readAsBytesSync());
  return _mark = (await codec.getNextFrame()).image;
}

/// Draws the mark centred on a square [px] wide; [fill] is how much of the
/// width the mark takes. [background] adds the dark emerald gradient.
Future<void> _icon(String path, int px, double fill, {bool background = true}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = px.toDouble();
  if (background) {
    canvas.drawRect(
        Rect.fromLTWH(0, 0, s, s),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A4134), Color(0xFF03261F)],
          ).createShader(Rect.fromLTWH(0, 0, s, s)));
  }
  final logo = await _logo();
  final w = s * fill, h = w * logo.height / logo.width;
  canvas.drawImageRect(
    logo,
    Rect.fromLTWH(0, 0, logo.width.toDouble(), logo.height.toDouble()),
    Rect.fromLTWH((s - w) / 2, (s - h) / 2, w, h),
    Paint()..filterQuality = FilterQuality.high,
  );
  final image = await rec.endRecording().toImage(px, px);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render app icons', () async {
    const res = 'android/app/src/main/res';
    const densities = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
    for (final e in densities.entries) {
      // Classic square icon.
      await _icon('$res/mipmap-${e.key}/ic_launcher.png', (48 * e.value).round(), .7);
      // Shaped (adaptive) icon foreground: 108dp with the mark in the safe zone.
      await _icon('$res/mipmap-${e.key}/ic_launcher_foreground.png', (108 * e.value).round(), .54,
          background: false);
    }

    // iOS: every size in the icon set (no transparency allowed).
    final ios = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    final name = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png');
    for (final f in ios.listSync().whereType<File>()) {
      final m = name.firstMatch(f.uri.pathSegments.last);
      if (m == null) continue;
      final px = (double.parse(m.group(1)!) * int.parse(m.group(2)!)).round();
      await _icon(f.path, px, .7);
    }

    // Web icons, if present.
    for (final (path, px) in const [
      ('web/icons/Icon-192.png', 192),
      ('web/icons/Icon-512.png', 512),
      ('web/icons/Icon-maskable-192.png', 192),
      ('web/icons/Icon-maskable-512.png', 512),
      ('web/favicon.png', 32),
    ]) {
      if (File(path).existsSync()) await _icon(path, px, path.contains('maskable') ? .54 : .7);
    }

    // Large preview for checking the result.
    await _icon('build/icon_preview.png', 1024, .7);
  });
}
