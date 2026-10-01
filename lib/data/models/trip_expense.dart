import 'trip.dart';

class TripExpense {
  const TripExpense({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.amount,
    this.category = 'fuel',
    this.currency = 'USD',
    this.fuelLiters,
    this.odometerKm,
    this.note,
    this.lat,
    this.lng,
    this.placeName,
    this.attachments = const [],
    required this.loggedAt,
  });

  final String id;
  final String tripId;
  final String userId;
  final String category; // fuel | food | toll | lodging | other
  final double amount;
  final String currency;
  final double? fuelLiters;
  final double? odometerKm;
  final String? note;

  /// Optional: where the money was spent, so a receipt can be checked against
  /// the route.
  final double? lat;
  final double? lng;

  /// Optional: what the picked location was called.
  final String? placeName;

  /// Bill/sticker images, in the order they were added. Each is a storage path
  /// in the shared `map-media` bucket (`trip_expense_media`, 0053), readable by
  /// everyone on the trip. Free accounts may attach one; Pro ten; Extreme
  /// twenty-five — enforced in the database.
  final List<String> attachments;

  final DateTime loggedAt;

  bool get hasLocation => lat != null && lng != null;

  /// A not-yet-created expense, for building the insert payload. [id] and
  /// [loggedAt] are unset because Postgres generates them.
  TripExpense.draft({
    required this.tripId,
    required this.userId,
    required this.amount,
    this.category = 'fuel',
    this.currency = 'USD',
    this.fuelLiters,
    this.odometerKm,
    this.note,
    this.lat,
    this.lng,
    this.placeName,
    this.attachments = const [],
  }) : id = '',
       loggedAt = DateTime.now();

  /// The attachments live in their own table, so the caller — which has just
  /// fetched them for a whole trip — supplies them.
  factory TripExpense.fromJson(
    Map<String, dynamic> json, {
    List<String> attachments = const [],
  }) {
    final point = LatLngPoint.fromPostgrest(json['point']);
    return TripExpense(
      id: json['id'] as String,
      tripId: json['trip_id'] as String,
      userId: json['user_id'] as String,
      category: json['category'] as String? ?? 'fuel',
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'USD',
      fuelLiters: (json['fuel_liters'] as num?)?.toDouble(),
      odometerKm: (json['odometer_km'] as num?)?.toDouble(),
      note: json['note'] as String?,
      lat: point?.lat,
      lng: point?.lng,
      placeName: json['place_name'] as String?,
      attachments: attachments,
      loggedAt: DateTime.parse(json['logged_at'] as String),
    );
  }

  /// A copy carrying [attachments] — used after the child rows are fetched.
  TripExpense withAttachments(List<String> attachments) => TripExpense(
    id: id,
    tripId: tripId,
    userId: userId,
    amount: amount,
    category: category,
    currency: currency,
    fuelLiters: fuelLiters,
    odometerKm: odometerKm,
    note: note,
    lat: lat,
    lng: lng,
    placeName: placeName,
    attachments: attachments,
    loggedAt: loggedAt,
  );

  /// The payload for `trip_expenses` — and, because it is the same map, for the
  /// offline outbox. The attachment list rides along so a queued expense replays
  /// with its images, so the write path must go through [toRowJson] for the row
  /// itself: there is no `attachments` column to insert.
  Map<String, dynamic> toInsertJson() => {
    ...toRowJson(),
    'attachments': attachments,
  };

  /// Just the `trip_expenses` columns.
  Map<String, dynamic> toRowJson() => {
    'trip_id': tripId,
    'user_id': userId,
    'category': category,
    'amount': amount,
    'currency': currency,
    'fuel_liters': fuelLiters,
    'odometer_km': odometerKm,
    'note': note,
    'point': hasLocation ? LatLngPoint(lat!, lng!).toEwkt() : null,
    'place_name': placeName,
  };
}
