package com.example.hanium_app

import android.Manifest
import android.app.Notification
import android.app.PendingIntent
import android.content.pm.PackageManager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.os.Build

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val emergencyChannel = "hanium_app/emergency_actions"
    private val warningNotificationChannelId = "hanium_warning_alerts_v2"
    private val safetyNotificationChannel = "hanium_app/safety_notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createWarningNotificationChannel()

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            safetyNotificationChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val rawId = call.argument<Number>("id")
                    val title = call.argument<String>("title").orEmpty()
                    val body = call.argument<String>("body").orEmpty()
                    val urgent = call.argument<Boolean>("urgent") ?: false
                    val id = rawId?.toInt() ?: (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
                    showSafetyNotification(id, title, body, urgent, result)
                }

                else -> result.notImplemented()
            }
        }
    }


    private fun showSafetyNotification(
        id: Int,
        title: String,
        body: String,
        urgent: Boolean,
        result: MethodChannel.Result
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2001)
            result.success(false)
            return
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(this, id, it, pendingFlags)
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, warningNotificationChannelId)
        } else {
            Notification.Builder(this)
        }

        builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title.ifBlank { "Hanium safety alert" })
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setOngoing(false)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(if (urgent) Notification.PRIORITY_MAX else Notification.PRIORITY_HIGH)

        pendingIntent?.let { builder.setContentIntent(it) }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            val warningSoundUri = Uri.parse("android.resource://" + packageName + "/raw/hanium_warning_alert")
            builder.setSound(warningSoundUri)
            builder.setVibrate(
                if (urgent) longArrayOf(0, 350, 150, 350, 150, 600)
                else longArrayOf(0, 250, 120, 250)
            )
        }

        val manager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            getSystemService(NotificationManager::class.java)
        } else {
            @Suppress("DEPRECATION")
            getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        }
        manager.notify(id, builder.build())
        result.success(true)
    }
    private fun createWarningNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val warningSoundUri = Uri.parse("android.resource://" + packageName + "/raw/hanium_warning_alert")
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val channel = NotificationChannel(
            warningNotificationChannelId,
            "Hanium warning alerts",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Loud warning sound for urgent safety alerts."
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 350, 150, 350, 150, 600)
            setSound(warningSoundUri, audioAttributes)
        }

        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
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
