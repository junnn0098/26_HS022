import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../app/app_config.dart';
import '../models/app_role.dart';

class SafetyRepository {
  SafetyRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>?> getJson(String path) async {
    try {
      final response = await _client
          .get(AppConfig.httpUri(path))
          .timeout(AppConfig.apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> postJson(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async {
    try {
      final response = await _client
          .post(
            AppConfig.httpUri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(AppConfig.apiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  WebSocketChannel openLocationSocket() {
    return WebSocketChannel.connect(AppConfig.wsUri('/ws/location'));
  }

  Future<Map<String, dynamic>?> state() => getJson('/state');
  Future<Map<String, dynamic>?> health() => getJson('/health');
  Future<Map<String, dynamic>?> latestLocation() => getJson('/location/latest');
  Future<Map<String, dynamic>?> alerts() => getJson('/alerts');

  Future<Map<String, dynamic>?> resolveAlerts() => postJson('/alerts/resolve');

  Future<Map<String, dynamic>?> triggerScenario({
    required String status,
    double? x,
    double? y,
    String? room,
    int seconds = 20,
  }) {
    return postJson('/scenario', {
      'status': status,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (room != null) 'room': room,
      'seconds': seconds,
      'holdMs': seconds * 1000,
      'source': 'app-demo',
    });
  }

  Future<Map<String, dynamic>?> updateSetting(String key, Object? value) {
    return postJson('/settings', {key: value});
  }

  Future<Map<String, dynamic>?> registerDeviceToken(
    String token, {
    required AppRole role,
  }) {
    return postJson('/device/register', {
      'token': token,
      'role': role.serverValue,
    });
  }

  Future<Map<String, dynamic>?> notifyCareRecipientSafe({
    required String room,
  }) {
    return postJson('/care-recipient/safe', {'room': room});
  }

  void close() => _client.close();
}
