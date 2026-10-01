import 'dart:typed_data';

class LatLngPoint {
  const LatLngPoint(this.lat, this.lng);

  final double lat;
  final double lng;

  /// Parses a PostGIS `geography(point)` value as returned by PostgREST,
  /// e.g. `{"type":"Point","coordinates":[lng,lat]}`.
  factory LatLngPoint.fromGeoJson(Map<String, dynamic> json) {
    final coords = json['coordinates'] as List<dynamic>;
    return LatLngPoint((coords[1] as num).toDouble(), (coords[0] as num).toDouble());
  }

  /// Parses a PostGIS `geometry`/`geography` column as PostgREST serializes it.
  ///
  /// PostgREST returns the value either as a GeoJSON object
  /// (`{"type":"Point","coordinates":[lng,lat]}`) or — depending on the server
  /// version and the request's `Accept` header — as the hex-encoded EWKB string
  /// (e.g. `0101000020E6100000…`). This handles both, passes null through, and
  /// yields null (rather than throwing) for anything it can't decode, so one
  /// odd row can't break a whole list.
  static LatLngPoint? fromPostgrest(Object? value) {
    if (value == null) return null;
    if (value is Map) {
      final map = value.cast<String, dynamic>();
      return map['coordinates'] is List ? LatLngPoint.fromGeoJson(map) : null;
    }
    if (value is String) return _fromEwkbHex(value);
    return null;
  }

  /// Like [fromPostgrest] but for required columns: throws a [FormatException]
  /// (which callers already treat as "skip this row") instead of a bare
  /// null-check error when the value can't be decoded.
  static LatLngPoint requirePostgrest(Object? value) =>
      fromPostgrest(value) ??
      (throw const FormatException('Missing or undecodable point'));

  /// Decodes a little/big-endian EWKB Point hex string (`…E6100000<x><y>`),
  /// where x is longitude and y is latitude. Returns null for any non-Point or
  /// malformed payload.
  static LatLngPoint? _fromEwkbHex(String hex) {
    final bytes = _decodeHex(hex);
    if (bytes == null || bytes.length < 21) return null;
    final data = ByteData.sublistView(bytes);
    final endian = bytes[0] == 1 ? Endian.little : Endian.big;
    var offset = 1;
    final typeWord = data.getUint32(offset, endian);
    offset += 4;
    // Bit 0x20000000 marks an embedded SRID word (PostGIS EWKB).
    if ((typeWord & 0x20000000) != 0) offset += 4;
    if ((typeWord & 0xff) != 1) return null; // only Point is handled
    if (offset + 16 > bytes.length) return null;
    final lng = data.getFloat64(offset, endian);
    final lat = data.getFloat64(offset + 8, endian);
    return LatLngPoint(lat, lng);
  }

  static Uint8List? _decodeHex(String hex) {
    if (hex.isEmpty || hex.length.isOdd) return null;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final hi = _hexDigit(hex.codeUnitAt(i * 2));
      final lo = _hexDigit(hex.codeUnitAt(i * 2 + 1));
      if (hi < 0 || lo < 0) return null;
      out[i] = (hi << 4) | lo;
    }
    return out;
  }

  static int _hexDigit(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30; // 0-9
    if (c >= 0x61 && c <= 0x66) return c - 0x57; // a-f
    if (c >= 0x41 && c <= 0x46) return c - 0x37; // A-F
    return -1;
  }

  Map<String, dynamic> toGeoJson() => {
        'type': 'Point',
        'coordinates': [lng, lat],
      };

  /// The point as PostGIS EWKT (`SRID=4326;POINT(lng lat)`).
  ///
  /// Use this for writes, not [toGeoJson]: PostgREST hands a JSON string
  /// straight to the column's geometry input, which parses WKT/EWKT — a GeoJSON
  /// object is rejected with `parse error - invalid geometry`. (The AI
  /// `save_place` tool writes the same EWKT form server-side.)
  String toEwkt() => 'SRID=4326;POINT($lng $lat)';
}

enum TripStatus { planned, active, completed, cancelled }

TripStatus _statusFromString(String? value) {
  return TripStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => TripStatus.planned,
  );
}

class Trip {
  const Trip({
    required this.id,
    required this.createdBy,
    required this.title,
    this.groupId,
    this.status = TripStatus.planned,
    this.originName,
    this.originPoint,
    this.destinationName,
    this.destinationPoint,
    this.scheduledStart,
    this.startedAt,
    this.endedAt,
    this.routePolyline,
    this.currency = 'USD',
  });

  /// A not-yet-created trip, for building the insert payload. [id] is unset
  /// because Postgres generates it; [TripRepository.createTrip] never reads
  /// [id] off a draft.
  const Trip.draft({
    required this.createdBy,
    required this.title,
    this.groupId,
    this.scheduledStart,
    this.originName,
    this.originPoint,
    this.destinationName,
    this.destinationPoint,
    this.routePolyline,
    this.currency = 'USD',
  })  : id = '',
        status = TripStatus.planned,
        startedAt = null,
        endedAt = null;

  final String id;
  final String? groupId;
  final String createdBy;
  final String title;
  final TripStatus status;
  final String? originName;
  final LatLngPoint? originPoint;
  final String? destinationName;
  final LatLngPoint? destinationPoint;
  final DateTime? scheduledStart;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? routePolyline;

  /// A trip that was started and then paused. Pausing keeps the trip in the
  /// `planned` state (so it stops being live and still counts against the trip
  /// cap) but leaves [startedAt] set, which is what tells it apart from a trip
  /// that has never run.
  bool get isPaused => status == TripStatus.planned && startedAt != null;

  /// ISO 4217 code the trip's expenses and ledger are denominated in.
  final String currency;

  factory Trip.fromJson(Map<String, dynamic> json) => Trip(
        id: json['id'] as String,
        groupId: json['group_id'] as String?,
        createdBy: json['created_by'] as String,
        title: json['title'] as String,
        status: _statusFromString(json['status'] as String?),
        originName: json['origin_name'] as String?,
        originPoint: LatLngPoint.fromPostgrest(json['origin_point']),
        destinationName: json['destination_name'] as String?,
        destinationPoint: LatLngPoint.fromPostgrest(json['destination_point']),
        scheduledStart: json['scheduled_start'] != null
            ? DateTime.parse(json['scheduled_start'] as String)
            : null,
        startedAt: json['started_at'] != null ? DateTime.parse(json['started_at'] as String) : null,
        endedAt: json['ended_at'] != null ? DateTime.parse(json['ended_at'] as String) : null,
        routePolyline: json['route_polyline'] as String?,
        currency: json['currency'] as String? ?? 'USD',
      );
}
