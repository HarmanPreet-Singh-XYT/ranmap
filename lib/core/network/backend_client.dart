import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/services/supabase_service.dart';
import '../constants/env.dart';
import '../util/backend_error.dart';

/// A failed ranmap-server call, carrying the HTTP status so callers can branch
/// on it (e.g. show a distinct message for 429). Its [toString] is just the
/// user-facing message, so `friendlyError` surfaces it verbatim.
class BackendException implements Exception {
  const BackendException(this.statusCode, this.message, {this.code});

  final int statusCode;
  final String message;

  /// Machine-readable error code from the response body, when present (e.g.
  /// `premium_required` — see `isPremiumRequired`).
  final String? code;

  @override
  String toString() => message;
}

/// One place for the client→ranmap-server HTTP pattern: attach the Supabase
/// session token, enforce a timeout, and decode the `{ "error": ... }` body.
/// The AI/phone/voice/maps repositories previously each re-implemented this.
class BackendClient {
  BackendClient._();

  static const Duration defaultTimeout = Duration(seconds: 20);

  static Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    Duration timeout = defaultTimeout,
    String fallbackMessage = 'Request failed',
  }) async {
    final uri = Uri.parse('${Env.backendUrl}$path').replace(queryParameters: query);
    final response = await _send(
      () => http.get(uri, headers: _headers()),
      timeout,
    );
    return _decode(response, fallbackMessage);
  }

  static Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = defaultTimeout,
    String fallbackMessage = 'Request failed',
  }) async {
    final uri = Uri.parse('${Env.backendUrl}$path');
    final response = await _send(
      () => http.post(uri, headers: _headers(), body: jsonEncode(body)),
      timeout,
    );
    return _decode(response, fallbackMessage);
  }

  /// Auth headers for requests that can't go through [getJson] — e.g. an
  /// `Image`/`CachedNetworkImage` fetching a protected binary from the backend.
  static Map<String, String> authHeaders() => _headers();

  /// Like [authHeaders], but returns null instead of throwing when there's no
  /// session. Safe to call from `build`, where an exception would fail the
  /// whole widget tree (an image then just falls back to its error widget).
  static Map<String, String>? authHeadersOrNull() {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token == null) return null;
    return {'Authorization': 'Bearer $token'};
  }

  static Map<String, String> _headers() {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token == null) throw StateError('Not signed in');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> _send(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const BackendException(0, 'The server took too long to respond.');
    }
  }

  static Map<String, dynamic> _decode(http.Response response, String fallbackMessage) {
    if (response.statusCode != 200) {
      throw BackendException(
        response.statusCode,
        backendErrorMessage(response.statusCode, response.body, fallbackMessage),
        code: backendErrorCode(response.body),
      );
    }
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
    } catch (_) {
      // Fall through to the generic message below.
    }
    throw const BackendException(200, 'Unexpected response from the server.');
  }
}
