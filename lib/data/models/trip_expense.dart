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
  final DateTime loggedAt;

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
  })  : id = '',
        loggedAt = DateTime.now();

  factory TripExpense.fromJson(Map<String, dynamic> json) => TripExpense(
        id: json['id'] as String,
        tripId: json['trip_id'] as String,
        userId: json['user_id'] as String,
        category: json['category'] as String? ?? 'fuel',
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'USD',
        fuelLiters: (json['fuel_liters'] as num?)?.toDouble(),
        odometerKm: (json['odometer_km'] as num?)?.toDouble(),
        note: json['note'] as String?,
        loggedAt: DateTime.parse(json['logged_at'] as String),
      );

  Map<String, dynamic> toInsertJson() => {
        'trip_id': tripId,
        'user_id': userId,
        'category': category,
        'amount': amount,
        'currency': currency,
        'fuel_liters': fuelLiters,
        'odometer_km': odometerKm,
        'note': note,
      };
}
