import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_store.dart';

/// The person to text when an SOS fires and there's no data to reach the crew.
/// Stored in the platform keystore/keychain (never uploaded), so it works
/// offline and isn't left in plaintext on the device.
class EmergencyContact {
  const EmergencyContact({this.name, this.phone});

  final String? name;
  final String? phone;

  bool get isSet => phone != null && phone!.isNotEmpty;

  String get label => name?.isNotEmpty == true ? name! : 'Emergency contact';
}

class EmergencyContactNotifier extends Notifier<EmergencyContact> {
  @override
  EmergencyContact build() {
    final store = ref.watch(secureStoreProvider);
    return EmergencyContact(
      name: store.emergencyContactName,
      phone: store.emergencyContactPhone,
    );
  }

  Future<void> save({String? name, String? phone}) async {
    await ref
        .read(secureStoreProvider)
        .setEmergencyContact(name: name, phone: phone);
    state = EmergencyContact(name: name, phone: phone);
  }
}

final emergencyContactProvider =
    NotifierProvider<EmergencyContactNotifier, EmergencyContact>(
      EmergencyContactNotifier.new,
    );
