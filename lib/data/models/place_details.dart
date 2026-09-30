/// One Google photo of a place. [name] is the resource name the backend's
/// `/maps/places/photo` proxy turns into image bytes; [author] is the
/// attribution Google requires us to show when present.
class PlacePhoto {
  final String name;
  final String? author;

  const PlacePhoto({required this.name, this.author});

  static PlacePhoto? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    return PlacePhoto(name: name, author: json['author'] as String?);
  }
}

/// Richer per-place metadata, fetched on demand from Google when a user opens
/// a single search result (Mapbox supplies the search results themselves).
class PlaceDetails {
  final String name;
  final String? address;
  final double? rating;
  final int? userRatingCount;
  final bool? openNow;
  final List<String> weekdayHours;
  final String? priceLevel;
  final String? phone;
  final String? website;
  final List<PlacePhoto> photos;

  const PlaceDetails({
    required this.name,
    this.address,
    this.rating,
    this.userRatingCount,
    this.openNow,
    this.weekdayHours = const [],
    this.priceLevel,
    this.phone,
    this.website,
    this.photos = const [],
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) => PlaceDetails(
        name: json['name'] as String? ?? 'Unnamed place',
        address: json['address'] as String?,
        rating: (json['rating'] as num?)?.toDouble(),
        userRatingCount: (json['userRatingCount'] as num?)?.toInt(),
        openNow: json['openNow'] as bool?,
        weekdayHours:
            (json['weekdayHours'] as List?)?.cast<String>() ?? const <String>[],
        priceLevel: json['priceLevel'] as String?,
        phone: json['phone'] as String?,
        website: json['website'] as String?,
        photos: (json['photos'] as List? ?? const [])
            .map(PlacePhoto.fromJson)
            .whereType<PlacePhoto>()
            .toList(),
      );

  /// Google returns price levels as `PRICE_LEVEL_MODERATE` etc.; render them as
  /// the usual `$`…`$$$$` shorthand.
  String? get priceLabel => switch (priceLevel) {
        'PRICE_LEVEL_INEXPENSIVE' => r'$',
        'PRICE_LEVEL_MODERATE' => r'$$',
        'PRICE_LEVEL_EXPENSIVE' => r'$$$',
        'PRICE_LEVEL_VERY_EXPENSIVE' => r'$$$$',
        _ => null,
      };

  /// e.g. "★ 4.6 (3,812)" — or null when Google has no rating for the place.
  String? get ratingLabel {
    if (rating == null) return null;
    final count = userRatingCount;
    final reviews = count == null ? '' : ' (${_thousands(count)})';
    return '★ ${rating!.toStringAsFixed(1)}$reviews';
  }

  static String _thousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
