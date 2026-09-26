import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Procedurally-drawn marker bitmaps.
///
/// The repo bundles no marker PNGs (see the note in `core/constants/avatars.dart`),
/// so pins and vehicle badges are rendered to PNG bytes at runtime and handed to
/// Mapbox point annotations. Vehicle badges double as the fallback image when a
/// 3D model can't be shown.
abstract final class MapMarkers {
  const MapMarkers._();

  static const _pinWidth = 44.0;
  static const _pinHeight = 56.0;
  static const _badgeSize = 44.0;

  static final Map<String, Future<Uint8List>> _cache = {};

  /// A teardrop pin with a glyph, anchored at the *bottom* tip (use
  /// [IconAnchor.BOTTOM] on the annotation).
  static Future<Uint8List> pin(
    Color color,
    IconData icon, {
    double devicePixelRatio = 3,
  }) {
    return _cached(
      'pin-${color.toARGB32()}-${icon.codePoint}-$devicePixelRatio',
      () => _renderPin(color, icon, devicePixelRatio),
    );
  }

  /// A circular colored badge with a glyph, anchored at its center.
  static Future<Uint8List> badge(
    Color color,
    IconData icon, {
    double devicePixelRatio = 3,
  }) {
    return _cached(
      'badge-${color.toARGB32()}-${icon.codePoint}-$devicePixelRatio',
      () => _renderBadge(color, icon, devicePixelRatio),
    );
  }

  /// Caches a render, but evicts the entry if it fails so a transient render
  /// error isn't cached as a permanent failure for that pin.
  static Future<Uint8List> _cached(
    String key,
    Future<Uint8List> Function() render,
  ) {
    final existing = _cache[key];
    if (existing != null) return existing;
    final future = render();
    _cache[key] = future;
    return future.catchError((Object error, StackTrace stack) {
      if (identical(_cache[key], future)) _cache.remove(key);
      throw error;
    });
  }

  static Future<Uint8List> _renderPin(
    Color color,
    IconData icon,
    double dpr,
  ) async {
    final width = _pinWidth * dpr;
    final height = _pinHeight * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    final radius = width * 0.36;
    final center = Offset(width / 2, radius + width * 0.04);

    final circle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final tail = Path()
      ..moveTo(center.dx - radius * 0.55, center.dy + radius * 0.72)
      ..lineTo(width / 2, height - dpr * 1.5)
      ..lineTo(center.dx + radius * 0.55, center.dy + radius * 0.72)
      ..close();
    final shape = Path.combine(PathOperation.union, circle, tail);

    canvas.drawShadow(shape, Colors.black, dpr * 1.6, false);
    canvas.drawPath(shape, Paint()..color = color);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dpr * 1.5
        ..color = Colors.white,
    );

    _paintGlyph(canvas, icon, center, width * 0.34, Colors.white);

    return _encode(recorder, width, height);
  }

  static Future<Uint8List> _renderBadge(
    Color color,
    IconData icon,
    double dpr,
  ) async {
    final size = _badgeSize * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size, size));

    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - dpr;
    canvas.drawCircle(center, radius, Paint()..color = color);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dpr * 1.5
        ..color = Colors.white,
    );

    _paintGlyph(canvas, icon, center, size * 0.55, Colors.white);

    return _encode(recorder, size, size);
  }

  static void _paintGlyph(
    Canvas canvas,
    IconData icon,
    Offset center,
    double fontSize,
    Color color,
  ) {
    final painter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      )
      ..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
    painter.dispose();
  }

  static Future<Uint8List> _encode(
    ui.PictureRecorder recorder,
    double width,
    double height,
  ) async {
    final image = await recorder.endRecording().toImage(
      width.round(),
      height.round(),
    );
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Marker image encoding returned no bytes');
      }
      return bytes.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
