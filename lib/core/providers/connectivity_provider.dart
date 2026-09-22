import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Streams the device's connectivity as a simple online/offline flag. Emits
/// `true` when any connection type is available, `false` when fully offline.
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
        (results) => results.any((result) => result != ConnectivityResult.none),
      );
});

/// True only once we've positively observed the device going offline, so the
/// banner doesn't flash before the first connectivity event arrives.
final isOfflineProvider = Provider<bool>((ref) {
  return ref.watch(connectivityProvider).valueOrNull == false;
});
