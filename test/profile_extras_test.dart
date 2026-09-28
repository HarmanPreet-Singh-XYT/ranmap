import 'package:flutter_test/flutter_test.dart';
import 'package:ranmap/data/models/user_document.dart';
import 'package:ranmap/data/models/vehicle_service.dart';

void main() {
  group('VehicleService', () {
    test('defaults to a 10,000 km interval at zero', () {
      const service = VehicleService();
      expect(service.intervalKm, 10000);
      expect(service.lastServiceKm, 0);
    });

    test('reads stored values', () {
      final service = VehicleService.fromJson(const {
        'interval_km': 15000,
        'last_service_km': 3200.5,
      });
      expect(service.intervalKm, 15000);
      expect(service.lastServiceKm, 3200.5);
    });
  });

  group('UserDocument.fromJson', () {
    test('reads a document with an expiry', () {
      final doc = UserDocument.fromJson(const {
        'id': 'd1',
        'name': 'Insurance',
        'kind': 'insurance',
        'storage_path': 'u1/123.jpg',
        'created_at': '2026-09-28T10:00:00Z',
        'expires_at': '2027-09-28T10:00:00Z',
      });

      expect(doc.name, 'Insurance');
      expect(doc.kind, 'insurance');
      expect(doc.storagePath, 'u1/123.jpg');
      expect(doc.expiresAt, DateTime.parse('2027-09-28T10:00:00Z'));
    });

    test('defaults kind to other and expiry to null', () {
      final doc = UserDocument.fromJson(const {
        'id': 'd2',
        'name': 'Ticket',
        'storage_path': 'u1/456.jpg',
        'created_at': '2026-09-28T10:00:00Z',
      });
      expect(doc.kind, 'other');
      expect(doc.expiresAt, isNull);
    });
  });
}
