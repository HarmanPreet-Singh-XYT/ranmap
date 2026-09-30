import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/avatars.dart';
import '../../../core/widgets/avatar_view.dart';

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

  /// Upper bound on cached renders. Most keys are a small closed set (colour ×
  /// icon), but avatar pins key a render per user avatar, and an uploaded
  /// avatar's path changes on every upload — so the cache must not grow without
  /// limit. Oldest entries are evicted first (Dart maps keep insertion order).
  static const int _cacheMaxEntries = 64;

  /// A teardrop pin with a glyph, anchored at the *bottom* tip (use
  /// [IconAnchor.BOTTOM] on the annotation). A [count] above 1 adds a small
  /// number badge (capped at "9+") for several items stacked at one spot.
  static Future<Uint8List> pin(
    Color color,
    IconData icon, {
    double devicePixelRatio = 3,
    int count = 1,
  }) {
    return _cached(
      'pin-${color.toARGB32()}-${icon.codePoint}-$devicePixelRatio-$count',
      () => _renderPin(color, icon, devicePixelRatio, count),
    );
  }

  /// A teardrop pin holding a person's avatar, anchored at the *bottom* tip.
  /// Used over a teammate's vehicle; carries no name (details open on tap).
  static Future<Uint8List> avatarPin(
    String avatarSeed,
    Color color, {
    double devicePixelRatio = 3,
  }) {
    return _cached(
      'avatar-$avatarSeed-${color.toARGB32()}-$devicePixelRatio',
      () => _renderAvatarPin(avatarSeed, color, devicePixelRatio),
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
    // Evict oldest renders past the cap so avatar pins can't grow it forever.
    while (_cache.length > _cacheMaxEntries) {
      _cache.remove(_cache.keys.first);
    }
    return future.catchError((Object error, StackTrace stack) {
      if (identical(_cache[key], future)) _cache.remove(key);
      throw error;
    });
  }

  static Future<Uint8List> _renderPin(
    Color color,
    IconData icon,
    double dpr,
    int count,
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

    if (count > 1) {
      // 0.78 keeps the badge's outer edge inside the bitmap (0.78 + 0.2 < 1).
      final badgeCenter = Offset(width * 0.78, width * 0.16);
      final badgeRadius = width * 0.2;
      canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = Colors.white);
      canvas.drawCircle(
        badgeCenter,
        badgeRadius - dpr * 1.5,
        Paint()..color = const Color(0xFFD93025),
      );
      final text = TextPainter(
        text: TextSpan(
          text: count > 9 ? '9+' : '$count',
          style: TextStyle(
            color: Colors.white,
            fontSize: badgeRadius * 1.05,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        badgeCenter - Offset(text.width / 2, text.height / 2),
      );
    }

    return _encode(recorder, width, height);
  }

  static const _avatarPinWidth = 50.0;
  static const _avatarPinHeight = 52.0;

  static Future<Uint8List> _renderAvatarPin(
    String seed,
    Color color,
    double dpr,
  ) async {
    final width = _avatarPinWidth * dpr;
    final height = _avatarPinHeight * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    final radius = width * 0.40;
    final center = Offset(width / 2, radius + width * 0.04);
    final circle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final tail = Path()
      ..moveTo(center.dx - radius * 0.42, center.dy + radius * 0.8)
      ..lineTo(width / 2, height - dpr * 1.5)
      ..lineTo(center.dx + radius * 0.42, center.dy + radius * 0.8)
      ..close();
    final shape = Path.combine(PathOperation.union, circle, tail);

    canvas.drawShadow(shape, Colors.black, dpr * 1.8, false);
    canvas.drawPath(shape, Paint()..color = color);
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = dpr * 1.5
        ..color = Colors.white,
    );

    // The avatar sits in a white disc inside the pin's head.
    final inner = radius - dpr * 3.5;
    canvas.drawCircle(center, inner, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: inner)),
    );
    final drawn = await _paintAvatar(canvas, seed, center, inner * 2);
    canvas.restore();
    if (!drawn) {
      _paintGlyph(
        canvas,
        Icons.person_rounded,
        center,
        inner * 1.3,
        color,
      );
    }

    return _encode(recorder, width, height);
  }

  /// Paints the avatar for [seed] into a square of side [size] centred on
  /// [center]. Returns false when it couldn't be loaded, so the caller can fall
  /// back to a generic glyph instead of an empty pin.
  static Future<bool> _paintAvatar(
    Canvas canvas,
    String seed,
    Offset center,
    double size,
  ) async {
    final origin = center - Offset(size / 2, size / 2);
    try {
      if (isCustomAvatar(seed)) {
        final image = await _loadNetworkImage(
          customAvatarUrl(customAvatarPath(seed)),
        );
        if (image == null) return false;
        try {
          final src = Rect.fromLTWH(
            0,
            0,
            image.width.toDouble(),
            image.height.toDouble(),
          );
          // Cover-fit: crop the longer side so the face isn't squashed.
          final side = src.shortestSide;
          final crop = Rect.fromCenter(
            center: src.center,
            width: side,
            height: side,
          );
          canvas.drawImageRect(
            image,
            crop,
            origin & Size(size, size),
            Paint()..filterQuality = FilterQuality.high,
          );
          return true;
        } finally {
          image.dispose();
        }
      }
      final info = await vg.loadPicture(
        SvgStringLoader(AvatarView.svgFor(seed)),
        null,
      );
      final scale = size / (info.size.width == 0 ? size : info.size.width);
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.scale(scale);
      canvas.drawPicture(info.picture);
      canvas.restore();
      info.picture.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<ui.Image?> _loadNetworkImage(String url) {
    final completer = Completer<ui.Image?>();
    final stream = NetworkImage(url).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        // Clone so the image outlives this stream: once the listener is
        // removed the completer may dispose the original, and the caller draws
        // it after this callback returns. The clone is disposed by the caller.
        if (!completer.isCompleted) completer.complete(info.image.clone());
        stream.removeListener(listener);
      },
      onError: (Object _, StackTrace? _) {
        if (!completer.isCompleted) completer.complete(null);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    // A slow avatar must not stall the pin forever.
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        stream.removeListener(listener);
        return null;
      },
    );
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
