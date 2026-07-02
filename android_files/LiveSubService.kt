package com.vezoo.player

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * LiveSubService — Foreground Service برای زیرنویس زنده
 * وقتی اپ minimize شد پردازش ادامه میده
 * وقتی اپ کامل بسته شد (onDestroy) → service هم kill میشه و پردازش متوقف میشه
 */
class LiveSubService : Service() {
    companion object {
        const val NOTIF_ID = 55
        const val CH_ID = "live_sub_service"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForeground(NOTIF_ID, buildNotif("زیرنویس زنده", "در حال پردازش..."))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra("title") ?: "زیرنویس زنده"
        val text  = intent?.getStringExtra("text")  ?: "در حال پردازش..."
        startForeground(NOTIF_ID, buildNotif(title, text))
        return START_NOT_STICKY // وقتی kill شد restart نشه
    }

    override fun onDestroy() {
        // وقتی اپ کامل بسته شد، زیرنویس زنده هم cancel میشه
        // پیام به MainActivity از طریق static flag
        LiveSubServiceHelper.notifyServiceDestroyed()
        super.onDestroy()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(CH_ID, "زیرنویس زنده", NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun buildNotif(title: String, text: String): Notification =
        NotificationCompat.Builder(this, CH_ID)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle(title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
}

/** کمکی برای اطلاع‌رسانی بین Service و MainActivity */
object LiveSubServiceHelper {
    var onServiceDestroyed: (() -> Unit)? = null

    fun notifyServiceDestroyed() {
        onServiceDestroyed?.invoke()
    }
}

