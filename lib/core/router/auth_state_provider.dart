import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/profile.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/services/supabase_service.dart';

/// Emits the raw Supabase auth state (signed in / signed out).
final authStateProvider = StreamProvider<AuthState>((ref) {
  return SupabaseService.auth.onAuthStateChange;
});

/// The current user's `profiles` row, or null if they haven't finished
/// onboarding (username + avatar) yet.
final myProfileProvider = FutureProvider<Profile?>((ref) async {
  final authState = ref.watch(authStateProvider).valueOrNull;
  if (authState?.session == null) return null;
  return ref.watch(profileRepositoryProvider).fetchMyProfile();
});
