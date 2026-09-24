import 'dart:convert';
import 'dart:io';

import '../models/safety_models.dart';

const _fileName = 'hanium_safety_last_snapshot.json';

Future<File> _cacheFile() async {
  final directory = Directory.systemTemp;
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return File('${directory.path}${Platform.pathSeparator}$_fileName');
}

Future<SafetySnapshot?> loadSnapshot() async {
  try {
    final file = await _cacheFile();
    if (!await file.exists()) return null;
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return SafetySnapshot.fromCacheJson(Map<String, dynamic>.from(decoded));
  } catch (_) {
    return null;
  }
}

Future<void> saveSnapshot(SafetySnapshot snapshot) async {
  try {
    final file = await _cacheFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(snapshot.toCacheJson()), flush: true);
  } catch (_) {
    // 캐시는 보조 기능이라 실패해도 앱 동작은 계속 유지한다.
  }
}

Future<void> clearSnapshot() async {
  try {
    final file = await _cacheFile();
    if (await file.exists()) await file.delete();
  } catch (_) {
    // 캐시 삭제 실패는 무시한다.
  }
}
