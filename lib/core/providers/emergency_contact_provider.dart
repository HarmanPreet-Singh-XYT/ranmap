import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_prefs_provider.dart';

/// The person to text when an SOS fires and there's no data to reach the crew.
/// Stored locally (never uploaded), so it works offline.
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
    final prefs = ref.watch(appPrefsProvider);
    return EmergencyContact(
      name: prefs.emergencyContactName,
      phone: prefs.emergencyContactPhone,
    );
  }

  Future<void> save({String? name, String? phone}) async {
    await ref
        .read(appPrefsProvider)
        .setEmergencyContact(name: name, phone: phone);
    state = EmergencyContact(name: name, phone: phone);
  }
}

final emergencyContactProvider =
    NotifierProvider<EmergencyContactNotifier, EmergencyContact>(
      EmergencyContactNotifier.new,
    );
