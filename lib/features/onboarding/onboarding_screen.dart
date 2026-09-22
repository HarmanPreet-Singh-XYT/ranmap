import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/avatars.dart';
import '../../core/router/auth_state_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/error_text.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/services/supabase_service.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _usernameCtrl = TextEditingController();
  String _selectedAvatar = kAvatarOptions.first.id;
  String _selectedVehicle = kVehicleOptions.first.id;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final username = _usernameCtrl.text.trim();
    if (username.length < 3) {
      setState(() => _error = 'Username must be at least 3 characters');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ProfileRepository();
    try {
      final available = await repo.isUsernameAvailable(username);
      if (!available) {
        setState(() {
          _error = 'That username is taken';
          _saving = false;
        });
        return;
      }

      final uid = SupabaseService.currentUserId;
      await repo.createProfile(Profile(
        id: uid,
        username: username,
        avatarId: _selectedAvatar,
        vehicleType: _selectedVehicle,
      ));
      ref.invalidate(myProfileProvider);
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your profile')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Choose a username', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameCtrl,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
              ),
            ),
            const SizedBox(height: 24),
            Text('Pick your avatar', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _AvatarGrid(
              selected: _selectedAvatar,
              onSelect: (id) => setState(() => _selectedAvatar = id),
            ),
            const SizedBox(height: 24),
            Text('Pick your vehicle', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _VehicleGrid(
              selected: _selectedVehicle,
              onSelect: (id) => setState(() => _selectedVehicle = id),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.danger)),
            ],
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saving ? null : _finish,
              child: _saving
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarGrid extends StatelessWidget {
  const _AvatarGrid({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: kAvatarOptions.map((avatar) {
        final isSelected = avatar.id == selected;
        return Semantics(
          selected: isSelected,
          button: true,
          label: avatar.label,
          child: GestureDetector(
            onTap: () => onSelect(avatar.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppTheme.primaryContainer : Colors.grey.shade100,
                border: Border.all(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                  width: 3,
                ),
              ),
              child: Center(
                child: Text(
                  avatar.label.substring(0, 1),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _VehicleGrid extends StatelessWidget {
  const _VehicleGrid({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: kVehicleOptions.map((vehicle) {
        final isSelected = vehicle.id == selected;
        return ChoiceChip(
          label: Text(vehicle.label),
          selected: isSelected,
          onSelected: (_) => onSelect(vehicle.id),
          selectedColor: AppTheme.primaryContainer,
          labelStyle: TextStyle(
            color: isSelected ? AppTheme.primary : Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        );
      }).toList(),
    );
  }
}
