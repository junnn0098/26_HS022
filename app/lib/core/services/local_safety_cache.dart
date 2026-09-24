import '../models/safety_models.dart';
import 'local_safety_cache_stub.dart'
    if (dart.library.io) 'local_safety_cache_io.dart' as platform_cache;

class LocalSafetyCache {
  const LocalSafetyCache();

  Future<SafetySnapshot?> load() => platform_cache.loadSnapshot();

  Future<void> save(SafetySnapshot snapshot) => platform_cache.saveSnapshot(snapshot);

  Future<void> clear() => platform_cache.clearSnapshot();
}
