import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/phone_repository.dart';
import '../repositories/premium_repository.dart';
import '../repositories/profile_repository.dart';

/// Repository providers live in the data layer so both core (router/auth) and
/// features can depend on them without a feature layer importing another
/// feature. Screens and other providers should read these instead of
/// constructing a repository directly.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository());
final phoneRepositoryProvider = Provider<PhoneRepository>((ref) => PhoneRepository());
final premiumRepositoryProvider = Provider<PremiumRepository>((ref) => PremiumRepository());
