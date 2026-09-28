import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/user_document.dart';
import '../../data/models/vehicle_service.dart';
import '../../data/repositories/document_repository.dart';
import '../../data/repositories/vehicle_service_repository.dart';

final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(),
);

/// The user's document wallet, newest first.
final userDocumentsProvider = FutureProvider.autoDispose<List<UserDocument>>((
  ref,
) {
  return ref.watch(documentRepositoryProvider).list();
});

/// A signed URL for one document (the bucket is private).
final documentSignedUrlProvider = FutureProvider.autoDispose
    .family<String, String>((ref, storagePath) {
      return ref.watch(documentRepositoryProvider).signedUrl(storagePath);
    });

final vehicleServiceRepositoryProvider = Provider<VehicleServiceRepository>(
  (ref) => VehicleServiceRepository(),
);

/// The user's vehicle service settings.
final vehicleServiceProvider = FutureProvider.autoDispose<VehicleService>((
  ref,
) {
  return ref.watch(vehicleServiceRepositoryProvider).fetch();
});
