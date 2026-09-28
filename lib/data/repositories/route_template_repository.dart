import '../models/route_template.dart';
import '../models/trip.dart';
import '../services/supabase_service.dart';

/// A personal library of saved routes (`route_templates`), owner-only via RLS
/// (the `route_templates_owner` policy in 0028).
class RouteTemplateRepository {
  final _client = SupabaseService.client;

  static const _maxTemplates = 100;

  Future<List<RouteTemplate>> fetchTemplates() async {
    final uid = SupabaseService.currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('route_templates')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(_maxTemplates);
    return (rows as List)
        .map((r) => RouteTemplate.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<RouteTemplate> createTemplate({
    required String name,
    String? originName,
    LatLngPoint? originPoint,
    String? destinationName,
    LatLngPoint? destinationPoint,
    String? routePolyline,
  }) async {
    final uid = SupabaseService.currentUserId;
    final row = await _client
        .from('route_templates')
        .insert({
          'user_id': uid,
          'name': name,
          'origin_name': originName,
          'origin_point': originPoint?.toGeoJson(),
          'destination_name': destinationName,
          'destination_point': destinationPoint?.toGeoJson(),
          'route_polyline': routePolyline,
        })
        .select()
        .single();
    return RouteTemplate.fromJson(row);
  }

  Future<void> deleteTemplate(String id) async {
    await _client.from('route_templates').delete().eq('id', id);
  }
}
