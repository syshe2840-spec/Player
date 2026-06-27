package com.vezoo.player

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val THUMB_CH  = "ir.subteam.subtitle_player/thumbnail"
    private val PIP_CH    = "ir.subteam.subtitle_player/pip"
    private val NOTIF_CH_ID = "player_ctrl"
    private val NOTIF_ID  = 42
    private val A_PLAY    = "com.vezoo.PLAY"
    private val A_PAUSE   = "com.vezoo.PAUSE"
    private val A_CLOSE   = "com.vezoo.CLOSE"

    private val executor  = Executors.newCachedThreadPool()
    private val handler   = Handler(Looper.getMainLooper())
    private var pipCh: MethodChannel? = null
    private var playing   = false
    private var title     = "پلیر"
    private var playerActive = false  // فقط وقتی پلیر باز باشه PiP مجاز
    // cache برای thumbnail
    private val thumbCache = HashMap<String, ByteArray?>()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            val action = when(i?.action) {
                A_PLAY -> "play"; A_PAUSE -> "pause"; A_CLOSE -> "close"; else -> return
            }
            pipCh?.invokeMethod("playerAction", mapOf("action" to action))
        }
    }

    override fun configureFlutterEngine(fe: FlutterEngine) {
        super.configureFlutterEngine(fe)
        createNotifChannel()
        requestNotifPermission()

        // ── Thumbnail ──
        MethodChannel(fe.dartExecutor.binaryMessenger, THUMB_CH).setMethodCallHandler { call, result ->
            if (call.method != "getThumbnail") { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path") ?: run { handler.post { result.success(null) }; return@setMethodCallHandler }
            val timeMs = call.argument<Int>("timeMs") ?: 1000
            val cacheKey = "$path@$timeMs"
            if (thumbCache.containsKey(cacheKey)) { handler.post { result.success(thumbCache[cacheKey]) }; return@setMethodCallHandler }
            executor.execute { handler.post { result.success(genThumb(path, timeMs.toLong() * 1000L).also { thumbCache[cacheKey] = it }) } }
        }

        // ── PiP + Notification ──
        pipCh = MethodChannel(fe.dartExecutor.binaryMessenger, PIP_CH).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        playing = call.argument<Boolean>("playing") ?: false
                        title = call.argument<String>("title") ?: title
                        val ok = try { enterPip(); true } catch (e: Exception) { android.util.Log.e("PiP","enterPip failed: $e"); false }
                        result.success(ok)
                    }
                    "updateState" -> { playing = call.argument<Boolean>("playing") ?: false; playerActive = true; title = call.argument<String>("title") ?: title; showNotif(); if (Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode) updatePipParams(); result.success(null) }
                    "hideNotif" -> { nm().cancel(NOTIF_ID); playerActive = false; playing = false; result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }

        val f = IntentFilter().apply { addAction(A_PLAY); addAction(A_PAUSE); addAction(A_CLOSE) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, f, Context.RECEIVER_EXPORTED)
        else registerReceiver(receiver, f)
    }

    private fun requestNotifPermission() {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
        }
    }

    private fun nm() = getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    private fun createNotifChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            nm().createNotificationChannel(NotificationChannel(NOTIF_CH_ID, "کنترل پلیر", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        }
    }

    private fun pi(action: String, code: Int) = PendingIntent.getBroadcast(this, code, Intent(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun showNotif() {
        val notif = NotificationCompat.Builder(this, NOTIF_CH_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title).setContentText(if (playing) "در حال پخش" else "متوقف")
            .setPriority(NotificationCompat.PRIORITY_LOW).setOngoing(playing)
            .addAction(if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, if (playing) "توقف" else "پخش", pi(if (playing) A_PAUSE else A_PLAY, 1))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "بستن", pi(A_CLOSE, 2))
            .build()
        nm().notify(NOTIF_ID, notif)
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT < 26) throw RuntimeException("API < 26, PiP not supported")
        val p = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).also { if (Build.VERSION.SDK_INT >= 26) it.setActions(buildActions()) }.build()
        val result = enterPictureInPictureMode(p)
        android.util.Log.d("PiP","enterPictureInPictureMode result: $result")
    }

    private fun buildActions(): List<android.app.RemoteAction> {
        if (Build.VERSION.SDK_INT < 26) return emptyList()
        return listOf(
            android.app.RemoteAction(android.graphics.drawable.Icon.createWithResource(this, if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play), if (playing) "توقف" else "پخش", "", pi(if (playing) A_PAUSE else A_PLAY, 3)),
            android.app.RemoteAction(android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel), "بستن", "", pi(A_CLOSE, 4))
        )
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < 26) return
        setPictureInPictureParams(PictureInPictureParams.Builder().setActions(buildActions()).build())
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, cfg: android.content.res.Configuration?) {
        super.onPictureInPictureModeChanged(inPip, cfg)
        pipCh?.invokeMethod("pipModeChanged", mapOf("inPip" to inPip))
    }

    override fun onStart() {
        super.onStart()
        // نوتیفیکیشن رو از onStart بزن (بعد از اینکه permission درخواست شد)
        if (playing) showNotif()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // فقط وقتی پلیر باز و در حال پخش است PiP فعال شود
        if (playing && playerActive && Build.VERSION.SDK_INT >= 26) try { enterPip() } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try { unregisterReceiver(receiver) } catch (_: Exception) {}
        nm().cancel(NOTIF_ID)
        super.onDestroy()
    }

    private fun genThumb(path: String, timeUs: Long): ByteArray? {
        val r = MediaMetadataRetriever()
        return try {
            if (!File(path).exists()) return null
            r.setDataSource(applicationContext, Uri.fromFile(File(path)))
            var bmp: Bitmap? = null
            val times = if (timeUs > 0) longArrayOf(timeUs, 0L) else longArrayOf(500_000L, 0L)
            for (t in times) { bmp = r.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC); if (bmp != null) break }
            bmp ?: return null
            val out = ByteArrayOutputStream()
            Bitmap.createScaledBitmap(bmp, 160, 90, true).compress(Bitmap.CompressFormat.JPEG, 75, out)
            out.toByteArray()
        } catch (_: Exception) { null } finally { try { r.release() } catch (_: Exception) {} }
    }
}
