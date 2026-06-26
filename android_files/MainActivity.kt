package ir.subteam.subtitle_player

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
    private val THUMB_CH = "ir.subteam.subtitle_player/thumbnail"
    private val PIP_CH   = "ir.subteam.subtitle_player/pip"
    private val NOTIF_CH = "player_controls"
    private val NOTIF_ID = 42
    private val ACT_PLAY  = "ir.subteam.PLAY"
    private val ACT_PAUSE = "ir.subteam.PAUSE"
    private val ACT_CLOSE = "ir.subteam.CLOSE"

    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pipCh: MethodChannel? = null
    private var playing = false
    private var videoTitle = "پلیر"

    // دریافت دکمه‌های نوتیفیکیشن / PiP
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val action = when (intent?.action) {
                ACT_PLAY -> "play"; ACT_PAUSE -> "pause"; ACT_CLOSE -> "close"; else -> return
            }
            pipCh?.invokeMethod("playerAction", mapOf("action" to action))
        }
    }

    override fun configureFlutterEngine(fe: FlutterEngine) {
        super.configureFlutterEngine(fe)
        createNotifChannel()

        // ── Thumbnail ──
        MethodChannel(fe.dartExecutor.binaryMessenger, THUMB_CH)
            .setMethodCallHandler { call, result ->
                if (call.method != "getThumbnail") { result.notImplemented(); return@setMethodCallHandler }
                val path = call.argument<String>("path")
                if (path == null) { mainHandler.post { result.success(null) }; return@setMethodCallHandler }
                executor.execute { mainHandler.post { result.success(generateThumbnail(path)) } }
            }

        // ── PiP + Notification ──
        pipCh = MethodChannel(fe.dartExecutor.binaryMessenger, PIP_CH).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> {
                        playing = call.argument<Boolean>("playing") ?: false
                        videoTitle = call.argument<String>("title") ?: videoTitle
                        enterPip(); result.success(true)
                    }
                    "updateState" -> {
                        playing = call.argument<Boolean>("playing") ?: false
                        videoTitle = call.argument<String>("title") ?: videoTitle
                        showNotif()
                        if (Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode) updatePipParams()
                        result.success(null)
                    }
                    "hideNotif" -> {
                        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        val filter = IntentFilter().apply { addAction(ACT_PLAY); addAction(ACT_PAUSE); addAction(ACT_CLOSE) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else registerReceiver(receiver, filter)
    }

    private fun pi(action: String, code: Int): PendingIntent = PendingIntent.getBroadcast(
        this, code, Intent(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun createNotifChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            val ch = NotificationChannel(NOTIF_CH, "کنترل پلیر", NotificationManager.IMPORTANCE_LOW)
            ch.setShowBadge(false)
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun showNotif() {
        val notif = NotificationCompat.Builder(this, NOTIF_CH)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(videoTitle)
            .setContentText(if (playing) "در حال پخش" else "متوقف")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(playing)
            .addAction(
                if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                if (playing) "توقف" else "پخش",
                pi(if (playing) ACT_PAUSE else ACT_PLAY, 1))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "بستن", pi(ACT_CLOSE, 2))
            .build()
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIF_ID, notif)
    }

    private fun enterPip() {
        if (Build.VERSION.SDK_INT < 26) return
        val params = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9))
        if (Build.VERSION.SDK_INT >= 26) params.setActions(buildPipActions())
        enterPictureInPictureMode(params.build())
    }

    private fun buildPipActions(): List<android.app.RemoteAction> {
        if (Build.VERSION.SDK_INT < 26) return emptyList()
        return listOf(
            android.app.RemoteAction(
                android.graphics.drawable.Icon.createWithResource(this,
                    if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play),
                if (playing) "توقف" else "پخش", "",
                pi(if (playing) ACT_PAUSE else ACT_PLAY, 3)),
            android.app.RemoteAction(
                android.graphics.drawable.Icon.createWithResource(this,
                    android.R.drawable.ic_menu_close_clear_cancel),
                "بستن", "", pi(ACT_CLOSE, 4))
        )
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < 26) return
        val params = PictureInPictureParams.Builder().setActions(buildPipActions()).build()
        setPictureInPictureParams(params)
    }

    override fun onPictureInPictureModeChanged(inPip: Boolean, cfg: android.content.res.Configuration?) {
        super.onPictureInPictureModeChanged(inPip, cfg)
        pipCh?.invokeMethod("pipModeChanged", mapOf("inPip" to inPip))
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Auto-enter PiP when user leaves app while playing
        if (playing && Build.VERSION.SDK_INT >= 26) enterPip()
    }

    override fun onDestroy() {
        try { unregisterReceiver(receiver) } catch (_: Exception) {}
        (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
        super.onDestroy()
    }

    private fun generateThumbnail(path: String): ByteArray? {
        val retriever = MediaMetadataRetriever()
        return try {
            if (!File(path).exists()) return null
            retriever.setDataSource(applicationContext, Uri.fromFile(File(path)))
            var bmp: Bitmap? = null
            for (t in longArrayOf(1_000_000L, 500_000L, 0L)) {
                bmp = retriever.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                if (bmp != null) break
            }
            bmp ?: return null
            val out = ByteArrayOutputStream()
            Bitmap.createScaledBitmap(bmp, 160, 90, true).compress(Bitmap.CompressFormat.JPEG, 75, out)
            out.toByteArray()
        } catch (_: Exception) { null }
        finally { try { retriever.release() } catch (_: Exception) {} }
    }
}

