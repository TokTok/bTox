package chat.tox.btox.call_media

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Runs while a call goes on: Android lets an app use the microphone and the
 * camera in the background only from a foreground service of their types.
 */
class CallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, intent?.getStringExtra(EXTRA_CHANNEL) ?: "Calls", NotificationManager.IMPORTANCE_LOW),
        )
        val icon =
            resources.getIdentifier("ic_bg_service_small", "drawable", packageName).takeIf { it != 0 }
                ?: applicationInfo.icon
        val notification =
            Notification.Builder(this, CHANNEL)
                .setSmallIcon(icon)
                .setContentTitle(intent?.getStringExtra(EXTRA_TITLE))
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_CALL)
                .setContentIntent(
                    packageManager.getLaunchIntentForPackage(packageName)?.let {
                        PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
                    },
                )
                .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val camera =
                if (intent?.getBooleanExtra(EXTRA_CAMERA, false) == true) {
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
                } else {
                    0
                }
            startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or camera)
        } else {
            startForeground(NOTIFICATION, notification)
        }
        pending--
        if (pending == 0 && stopWhenStarted) {
            stopWhenStarted = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL = "btox_call"
        private const val NOTIFICATION = 0xca11
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_CHANNEL = "channel"
        private const val EXTRA_CAMERA = "camera"

        // Starts not yet taken by onStartCommand. Stopped before it calls
        // startForeground, the service would make Android end the app, so a
        // stop then waits for it.
        private var pending = 0
        private var stopWhenStarted = false

        /** Starts it, or changes whether it uses the [camera]. */
        fun start(context: Context, title: String, channel: String, camera: Boolean) {
            context.startForegroundService(
                Intent(context, CallService::class.java)
                    .putExtra(EXTRA_TITLE, title)
                    .putExtra(EXTRA_CHANNEL, channel)
                    .putExtra(EXTRA_CAMERA, camera),
            )
            pending++
            stopWhenStarted = false
        }

        fun stop(context: Context) {
            if (pending > 0) {
                stopWhenStarted = true
            } else {
                context.stopService(Intent(context, CallService::class.java))
            }
        }
    }
}
