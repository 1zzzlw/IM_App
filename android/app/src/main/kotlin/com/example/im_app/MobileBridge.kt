package com.example.im_app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class MobileBridge(private val context: Context, messenger: BinaryMessenger) {
    var activity: MainActivity? = null
    private val channel = MethodChannel(messenger, "im_app/mobile")
    private val manager = context.getSystemService(NotificationManager::class.java)
    private var permission: MethodChannel.Result? = null
    private var launch: Map<String, String>? = null
    private var initialized = false

    init {
        if (Build.VERSION.SDK_INT >= 26) {
            val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION).build()
            manager.createNotificationChannel(NotificationChannel("im_messages", "聊天消息", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(Uri.parse("android.resource://${context.packageName}/raw/im_message"), attributes)
                enableVibration(true)
            })
            manager.createNotificationChannel(NotificationChannel("im_messages_silent", "静音聊天消息", NotificationManager.IMPORTANCE_HIGH).apply {
                setSound(null, null)
            })
        }
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "initialize" -> {
                        initialized = true
                        result.success(mapOf("granted" to granted(), "launch" to launch))
                        launch = null
                    }
                    "requestPermission" -> {
                        val host = activity
                        if (Build.VERSION.SDK_INT >= 33 && !granted() && host != null) {
                            if (permission != null) result.success(false)
                            else {
                                permission = result
                                host.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 3101)
                            }
                        } else result.success(granted())
                    }
                    "notify" -> { show(call.arguments as Map<*, *>); result.success(null) }
                    "cancelNotifications" -> {
                        manager.activeNotifications.filter { it.id != ChatConnectionService.ID }.forEach { manager.cancel(it.id) }
                        result.success(null)
                    }
                    "background" -> {
                        val enabled = call.argument<Boolean>("enabled") == true
                        val service = Intent(context, ChatConnectionService::class.java)
                        if (!enabled) context.stopService(service)
                        else if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service)
                        else context.startService(service)
                        result.success(null)
                    }
                    "openSettings", "batterySettings" -> {
                        val intent = if (call.method == "batterySettings") Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                        (activity ?: context).startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("mobile_service", error.localizedMessage, null)
            }
        }
    }

    private fun granted(): Boolean = manager.areNotificationsEnabled()

    fun permissionResult(code: Int) {
        if (code == 3101) { permission?.success(granted()); permission = null }
    }

    fun handleIntent(intent: Intent?) {
        val conversation = intent?.getStringExtra("conversationId") ?: return
        val account = intent.getStringExtra("accountId") ?: return
        val data = mapOf("accountId" to account, "conversationId" to conversation)
        intent.removeExtra("conversationId")
        intent.removeExtra("accountId")
        if (initialized) channel.invokeMethod("notificationOpened", data) else launch = data
    }

    @Suppress("DEPRECATION")
    private fun show(data: Map<*, *>) {
        if (!granted()) return
        val conversation = data["conversationId"].toString()
        val id = ("${data["accountId"]}:$conversation".hashCode() and 0x7fffffff).coerceAtLeast(10)
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra("conversationId", conversation).putExtra("accountId", data["accountId"].toString())
        val pending = PendingIntent.getActivity(context, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val sound = data["sound"] == true
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, if (sound) "im_messages" else "im_messages_silent")
            else Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        builder.setSmallIcon(R.drawable.ic_stat_chat)
            .setContentTitle(data["title"].toString()).setContentText(data["body"].toString())
            .setStyle(Notification.BigTextStyle().bigText(data["body"].toString()))
            .setCategory(Notification.CATEGORY_MESSAGE).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setContentIntent(pending).setAutoCancel(true)
        if (Build.VERSION.SDK_INT < 26 && sound) builder.setSound(Uri.parse("android.resource://${context.packageName}/raw/im_message"))
        manager.notify(id, builder.build())
    }
}
