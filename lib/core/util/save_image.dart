import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

import '../widgets/app_toast.dart';
import 'error_text.dart';

/// Saves image [bytes] to the device's photo library, asking for permission the
/// first time, and reports the outcome with a toast.
Future<void> saveImageToGallery(
  BuildContext context,
  Uint8List bytes, {
  String? name,
}) async {
  try {
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      if (context.mounted) {
        showAppToast(
          context,
          'Allow photo access in Settings to save images.',
          error: true,
        );
      }
      return;
    }
    await Gal.putImageBytes(
      bytes,
      name: name ?? 'ranmap_${DateTime.now().millisecondsSinceEpoch}',
    );
    if (context.mounted) showAppToast(context, 'Saved to Photos.');
  } catch (e) {
    debugPrint('save image failed: $e');
    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
  }
}

/// Downloads [url] and saves it to the photo library.
Future<void> saveImageUrlToGallery(
  BuildContext context,
  String url, {
  String? name,
}) async {
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode}).');
    }
    if (!context.mounted) return;
    await saveImageToGallery(context, response.bodyBytes, name: name);
  } catch (e) {
    debugPrint('download image failed: $e');
    if (context.mounted) showAppToast(context, friendlyError(e), error: true);
  }
}
