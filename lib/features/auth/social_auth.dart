import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/supabase_service.dart';

/// Deep link the OAuth providers redirect back to after the user approves.
///
/// Registered natively (iOS `CFBundleURLTypes`, Android `intent-filter`) and
/// must also be allow-listed under Supabase → Authentication → URL
/// Configuration, or the round-trip can't complete.
const String kAuthRedirectUrl = 'com.ranmap.app://login-callback';

/// Opens [provider]'s OAuth screen in the external browser.
///
/// Returns whether the browser was launched. On success the session itself
/// arrives asynchronously via the auth-state stream once the provider redirects
/// back to [kAuthRedirectUrl] — callers don't navigate manually.
Future<bool> signInWithProvider(OAuthProvider provider) {
  return SupabaseService.auth.signInWithOAuth(
    provider,
    redirectTo: kAuthRedirectUrl,
    authScreenLaunchMode: LaunchMode.externalApplication,
  );
}
