import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app/hanium_app.dart';
import 'core/services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  runApp(const HaniumApp());
}
