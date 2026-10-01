import '../../core/network/backend_client.dart';

/// Reconciles `profiles.plan` with RevenueCat via the backend
/// (`POST /billing/sync`).
///
/// The RevenueCat webhook is the primary path, but it can lag or fail (bad
/// auth header, misconfigured URL, an anonymous purchase). Calling this after a
/// purchase and on launch/sign-in means the DB converges regardless — so a
/// paying user is never stuck on "free" because a webhook didn't land.
class BillingRepository {
  const BillingRepository();

  /// Best-effort: a reconcile must never throw into the UI (e.g. when offline or
  /// not signed in).
  Future<void> sync() async {
    try {
      await BackendClient.postJson('/billing/sync', const {});
    } catch (_) {
      // Ignore — the webhook remains the backstop, and the next call retries.
    }
  }
}
