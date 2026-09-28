import '../models/vehicle_service.dart';
import '../services/supabase_service.dart';

/// The user's vehicle service settings (`vehicle_service`, owner-only RLS).
class VehicleServiceRepository {
  final _client = SupabaseService.client;

  Future<VehicleService> fetch() async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return const VehicleService();
    final row = await _client
        .from('vehicle_service')
        .select()
        .eq('user_id', uid)
        .maybeSingle();
    return row == null ? const VehicleService() : VehicleService.fromJson(row);
  }

  Future<void> save({
    required double intervalKm,
    required double lastServiceKm,
  }) async {
    final uid = SupabaseService.currentUserId;
    await _client.from('vehicle_service').upsert({
      'user_id': uid,
      'interval_km': intervalKm,
      'last_service_km': lastServiceKm,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
