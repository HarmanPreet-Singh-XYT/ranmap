import 'dart:convert';

/// Decodes a `{ "error": "..." }` body returned by ranmap-server, falling back
/// to a status-based message. Shared by the repositories that talk to the
/// backend directly (AI assistant, phone verification, voice tokens), so the
/// three copies of this logic can't drift.
String backendErrorMessage(int statusCode, String body, String fallback) {
  try {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is String && error.isNotEmpty) return error;
    }
  } catch (_) {
    // Body wasn't JSON — fall through to the status-based message.
  }
  return '$fallback (HTTP $statusCode)';
}

/// Extracts the machine-readable `code` from a ranmap-server error body (e.g.
/// `premium_required`), or null when the body carries none.
String? backendErrorCode(String body) {
  try {
    final data = jsonDecode(body);
    if (data is Map<String, dynamic>) {
      final code = data['code'];
      if (code is String && code.isNotEmpty) return code;
    }
  } catch (_) {
    // Body wasn't JSON — no code to report.
  }
  return null;
}
