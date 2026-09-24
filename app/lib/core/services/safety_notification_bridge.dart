import 'dart:async';

import 'package:flutter/services.dart';

import '../models/safety_models.dart';

class SafetyNotificationBridge {
  const SafetyNotificationBridge._();

  static const MethodChannel _channel = MethodChannel(
    'hanium_app/safety_notifications',
  );

  static Future<void> showAlert(
    AlertEvent alert, {
    bool allowNormal = false,
  }) async {
    if (alert.resolved) return;
    if (!allowNormal && alert.status == SafetyStatus.normal) return;

    final urgent = alert.urgent || alert.status == SafetyStatus.danger;
    try {
      await _channel.invokeMethod<bool>('show', {
        'id': alert.id,
        'title': alert.title,
        'body': alert.message,
        'urgent': urgent,
      });
    } catch (_) {
      // Native notifications are a presentation aid; app state still updates.
    }
  }
}