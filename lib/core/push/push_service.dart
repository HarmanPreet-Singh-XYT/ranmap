import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/backend_client.dart';

/// Device push notifications (FCM).
///
/// The app must register its FCM token with ranmap-server (`device_tokens`) or
/// no push is delivered — the server only has a token to send to once this
/// runs. Registration is deliberately lazy and non-intrusive:
///
///  * [configurePush] initializes Firebase and, **if the user already granted
///    permission**, refreshes the server-side token — it never prompts on a
///    cold start.
///  * The OS prompt happens only when the user asks for it (Settings →
///    Notifications), via [requestPushPermission].
///
/// Everything is best-effort: a build without Firebase config (`google-
/// services.json` / `GoogleService-Info.plist`) initializes to a no-op and
/// reports [isPushConfigured] false, so the UI can be honest instead of
/// pretending to deliver.
bool _ready = false;

/// Whether push is usable in this build (Firebase initialized successfully).
bool get isPushConfigured => _ready;

/// Initializes Firebase and wires token refresh. A no-op when Firebase isn't
/// configured, and never throws — push must not be able to block app startup.
Future<void> configurePush() async {
  // Web push needs a VAPID key and a service worker; this app is mobile-only.
  if (kIsWeb || _ready) return;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('push: Firebase is not configured in this build: $e');
    return;
  }

  try {
    // Registering a background handler keeps data messages from being dropped
    // while the app is backgrounded. The handler itself is intentionally a
    // no-op: notification-style messages are shown by the OS.
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
    // FCM rotates tokens; re-register so the server always has the live one.
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => unawaited(_registerCurrentToken()),
    );
  } catch (e) {
    debugPrint('push: setup failed: $e');
    return;
  }

  _ready = true;
  // Refresh the server-side token for a user who already opted in, without
  // prompting (a prompt here would be the same premature-ask mistake as the
  // location permission at launch).
  if (await _permissionGranted()) {
    await _registerCurrentToken();
  }
}

/// Re-registers the current device after sign-in, when permission is already
/// granted. Safe to call on every auth change; a no-op otherwise.
Future<void> syncPushRegistration() async {
  if (!_ready) return;
  if (await _permissionGranted()) await _registerCurrentToken();
}

/// Requests the OS notification permission (must be a user gesture) and, when
/// granted, registers this device. Returns whether notifications are now on.
Future<bool> requestPushPermission() async {
  if (!_ready) return false;
  try {
    final settings = await FirebaseMessaging.instance.requestPermission();
    final granted = _isGranted(settings.authorizationStatus);
    if (granted) await _registerCurrentToken();
    return granted;
  } catch (e) {
    debugPrint('push: permission request failed: $e');
    return false;
  }
}

/// Forgets this device's token on the server. Call while still signed in (the
/// request authenticates with the session), i.e. before signing out.
Future<void> unregisterPush() async {
  if (!_ready) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await BackendClient.postJson(
      '/notifications/unregister',
      {'token': token},
      fallbackMessage: 'Could not unregister this device',
    );
  } catch (e) {
    debugPrint('push: unregister failed: $e');
  }
}

Future<void> _registerCurrentToken() async {
  if (!_ready) return;
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await BackendClient.postJson(
      '/notifications/register',
      {'token': token, 'platform': _platform},
      fallbackMessage: 'Could not register this device for notifications',
    );
  } catch (e) {
    // Best-effort: a failed registration must not surface as an app error.
    debugPrint('push: register failed: $e');
  }
}

Future<bool> _permissionGranted() async {
  if (!_ready) return false;
  try {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return _isGranted(settings.authorizationStatus);
  } catch (_) {
    return false;
  }
}

bool _isGranted(AuthorizationStatus status) =>
    status == AuthorizationStatus.authorized ||
    status == AuthorizationStatus.provisional;

/// The server's expected platform string.
String get _platform =>
    defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

/// The OS-level notification status, driving the Settings affordance.
enum PushStatus { unsupported, denied, authorized }

/// Whether this build can push, and whether the user has allowed it.
final pushStatusProvider = FutureProvider<PushStatus>((ref) async {
  if (!_ready) return PushStatus.unsupported;
  try {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    return _isGranted(settings.authorizationStatus)
        ? PushStatus.authorized
        : PushStatus.denied;
  } catch (_) {
    return PushStatus.unsupported;
  }
});

/// Must be top-level and annotated for the background isolate.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // The background isolate is separate from the main one, so Firebase must be
  // initialized here too. Guarded so a config-less build stays a no-op.
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
  } catch (_) {
    // No Firebase config — nothing to do.
  }
  // Otherwise a no-op: the OS displays notification-style messages.
}
