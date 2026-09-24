import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/avatars.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../data/models/profile.dart';
import '../../data/providers/repository_providers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _usernameCtrl;
  late String _avatarId;
  late String _vehicleType;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _usernameCtrl = TextEditingController(text: widget.profile.username);
    _avatarId = widget.profile.avatarId;
    _vehicleType = widget.profile.vehicleType;
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    if (username.length < 3) {
      setState(() => _error = 'Username must be at least 3 characters');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(profileRepositoryProvider);
    try {
      if (username.toLowerCase() != widget.profile.username.toLowerCase()) {
        final available = await repo.isUsernameAvailable(username);
        if (!available) {
          setState(() {
            _error = 'That username is taken';
            _saving = false;
          });
          return;
        }
      }

      await repo.updateProfile(widget.profile.copyWith(
        username: username,
        avatarId: _avatarId,
        vehicleType: _vehicleType,
      ));
      ref.invalidate(myProfileProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Username', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameCtrl,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(labelText: 'Username', prefixText: '@'),
            ),
            const SizedBox(height: 24),
            Text('Avatar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kAvatarOptions.map((avatar) {
                final selected = avatar.id == _avatarId;
                return Semantics(
                  selected: selected,
                  button: true,
                  label: avatar.label,
                  child: GestureDetector(
                    onTap: () => setState(() => _avatarId = avatar.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected ? AppTheme.primaryContainer : Colors.grey.shade100,
                        border: Border.all(
                          color: selected ? AppTheme.primary : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          avatar.label.substring(0, 1),
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Text('Vehicle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kVehicleOptions.map((vehicle) {
                final selected = vehicle.id == _vehicleType;
                return ChoiceChip(
                  label: Text(vehicle.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _vehicleType = vehicle.id),
                  selectedColor: AppTheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: selected ? AppTheme.primary : Colors.black87,
                    fontWeight: FontWeight.w600,
                  ),
                );
              }).toList(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
