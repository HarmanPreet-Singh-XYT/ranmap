import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'data/services/supabase_service.dart';
import 'features/map/map_engine/map_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  MapEngine.bootstrap();
  await SupabaseService.initialize();
  runApp(const ProviderScope(child: RanmapApp()));
}
