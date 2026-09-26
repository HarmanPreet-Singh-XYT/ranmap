import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the device's connectivity as a simple online/offline flag. Emits
/// `true` when any connection type is available, `false` when fully offline.
///
/// The current state is emitted first (via `checkConnectivity`) so launching
/// the app while already offline shows the offline banner immediately instead
/// of waiting for the next connectivity *change*.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  yield _isOnline(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(_isOnline);
});

bool _isOnline(List<ConnectivityResult> results) =>
    results.any((result) => result != ConnectivityResult.none);

/// True only once we've positively observed the device going offline, so the
/// banner doesn't flash before the first connectivity event arrives.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).valueOrNull == false;
});
