package com.example.hanium_app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val emergencyChannel = "hanium_app/emergency_actions"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            emergencyChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "dial" -> {
                    val phone = call.argument<String>("phone").orEmpty()
                    if (phone.isBlank()) {
                        result.error("EMPTY_PHONE", "연락처가 비어 있어요.", null)
                        return@setMethodCallHandler
                    }
                    openDialer(phone, result)
                }

                "sms" -> {
                    val phone = call.argument<String>("phone").orEmpty()
                    val message = call.argument<String>("message").orEmpty()
                    if (phone.isBlank()) {
                        result.error("EMPTY_PHONE", "연락처가 비어 있어요.", null)
                        return@setMethodCallHandler
                    }
                    openSms(phone, message, result)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun openDialer(phone: String, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_DIAL).apply {
            data = Uri.parse("tel:$phone")
        }

        try {
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("NO_DIALER", "전화 앱을 찾을 수 없어요.", null)
        }
    }

    private fun openSms(phone: String, message: String, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_SENDTO).apply {
            data = Uri.parse("smsto:$phone")
            putExtra("sms_body", message)
        }

        try {
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("NO_SMS_APP", "문자 앱을 찾을 수 없어요.", null)
        }
    }
}
