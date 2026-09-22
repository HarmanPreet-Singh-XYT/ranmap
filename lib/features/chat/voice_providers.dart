import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/voice_repository.dart';

final voiceRepositoryProvider = Provider<VoiceRepository>((ref) => VoiceRepository());
