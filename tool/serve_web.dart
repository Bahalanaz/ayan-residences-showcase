// Serves the built web app (build/web) on http://localhost:8080 to try it
// in a browser. Run `flutter build web` first, then: dart tool/serve_web.dart
import 'dart:io';

const _types = {
  'html': 'text/html; charset=utf-8',
  'js': 'application/javascript',
  'mjs': 'application/javascript',
  'json': 'application/json',
  'css': 'text/css',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'wasm': 'application/wasm',
  'ico': 'image/x-icon',
};

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args.first) : 8080;
  final root = Directory('build/web').absolute.path;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Serving $root on http://localhost:$port');
  await for (final req in server) {
    var path = Uri.decodeComponent(req.uri.path);
    if (path == '/' || path.isEmpty) path = '/index.html';
    var file = File('$root$path');
    // Unknown paths fall back to the app (it handles its own screens).
    if (!file.existsSync() || path.contains('..')) file = File('$root/index.html');
    final ext = file.path.split('.').last.toLowerCase();
    req.response.headers.contentType = ContentType.parse(_types[ext] ?? 'application/octet-stream');
    req.response.headers.set('Cache-Control', 'no-cache');
    await req.response.addStream(file.openRead());
    await req.response.close();
  }
}
