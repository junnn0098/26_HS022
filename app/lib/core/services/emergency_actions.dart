import 'package:flutter/services.dart';

class EmergencyActions {
  const EmergencyActions._();

  static const _channel = MethodChannel('hanium_app/emergency_actions');

  static String normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  static Future<bool> dial(String phone) async {
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('dial', {'phone': normalized}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> sms(String phone, String message) async {
    final normalized = normalizePhone(phone);
    if (normalized.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('sms', {
            'phone': normalized,
            'message': message,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
