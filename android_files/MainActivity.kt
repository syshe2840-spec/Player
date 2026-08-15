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
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Rational
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import java.io.BufferedOutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class MainActivity : FlutterActivity() {

    private val THUMB_CH  = "ir.subteam.subtitle_player/thumbnail"
    private val PIP_CH    = "ir.subteam.subtitle_player/pip"
    private val VEZ_CH    = "com.vezoo.player/vezoo"
    private val WHISPER_CH = "com.vezoo.player/whisper"
    private val extractCancel = AtomicBoolean(false)
    private val NOTIF_CH_ID = "player_ctrl"
    private val NOTIF_ID  = 42
    private val AI_NOTIF_CH_ID = "ai_progress"
    private val AI_NOTIF_ID = 43
    private var aiNotifTitle = "زیرنویس AI"
    private val A_PLAY    = "com.vezoo.PLAY"
    private val A_PAUSE   = "com.vezoo.PAUSE"
    private val A_CLOSE   = "com.vezoo.CLOSE"
    private val A_AI_CANCEL = "com.vezoo.AI_CANCEL"
    private var whisperCh: MethodChannel? = null
    private var aiCancelSink: io.flutter.plugin.common.EventChannel.EventSink? = null

    private val APP_HALF = byteArrayOf(
        0x56,0x45,0x5A,0x4F,0x4F,0x5F,0x41,0x50,
        0x50,0x5F,0x48,0x41,0x4C,0x46,0x5F,0x32,
        0x30,0x32,0x34,0x5F,0x56,0x31,0x5F,0x53,
        0x45,0x43,0x52,0x45,0x54,0x21,0x21,0x21,
    )
    companion object {
        init { System.loadLibrary("vezoo") }
    }
    private external fun nativeGcmDecrypt(key: ByteArray, data: ByteArray): ByteArray?
    private external fun nativeGcmEncrypt(key: ByteArray, data: ByteArray): ByteArray?
    private external fun nativeHkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, outLen: Int): ByteArray?

    private val HKDF_SALT = "vezoo-master-salt-v1".toByteArray()
    private val HKDF_INFO = "vezoo-master-key-v1".toByteArray()
    private val MAGIC = byteArrayOf(0x56,0x45,0x5A,0x4F,0x4F,0x01)
    private val KS_ALIAS = "vezoo_wrap_key"
    private val PREFS_NAME = "vezoo_secure"

    private val executor  = Executors.newCachedThreadPool()
    private val handler   = Handler(Looper.getMainLooper())
    private var pipCh: MethodChannel? = null
    private var playing   = false
    private var title     = "Vezoo"
    private var playerActive = false
    private val thumbCache = HashMap<String, ByteArray?>()

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, i: Intent?) {
            if (i?.action == A_AI_CANCEL) {
                nm().cancel(AI_NOTIF_ID)
                handler.post { aiCancelSink?.success("cancel") }
                return
            }
            val action = when(i?.action) {
                A_PLAY->"play"; A_PAUSE->"pause"; A_CLOSE->"close"; else->return
            }
            pipCh?.invokeMethod("playerAction", mapOf("action" to action))
        }
    }

    // ── Vosk ──
    private var voskService: VoskService? = null
    private var voskSink: io.flutter.plugin.common.EventChannel.EventSink? = null
    private var voskCallbackChannel: io.flutter.plugin.common.MethodChannel? = null
    private var pendingVoskLang: String? = null
    private var geminiService: GeminiLiveService? = null
    private var pendingGeminiLang: String? = null
    private var pendingGeminiDub: Boolean = false
    private var cachedProjection: android.media.projection.MediaProjection? = null
    private var pendingGeminiCfg: GeminiConfig? = null
    private val PROJ_REQ_VOSK = 9999
    private val PROJ_REQ_GEMINI = 9998

    // ── Android STT ──
    private var androidSttService: AndroidBuiltinSttService? = null
    private var androidSttCallback: io.flutter.plugin.common.MethodChannel? = null

    override fun configureFlutterEngine(fe: FlutterEngine) {
        super.configureFlutterEngine(fe)
        createNotifChannel()
        requestNotifPermission()

        // ── Network VPN Bypass ──
        val connectivityMgr = getSystemService(android.net.ConnectivityManager::class.java)
        io.flutter.plugin.common.MethodChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/network")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setIptvBypassVpn" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        if (android.os.Build.VERSION.SDK_INT >= 23) {
                            val nets = connectivityMgr?.allNetworks ?: emptyArray()
                            val targetNet = if (enabled) {
                                nets.firstOrNull { net ->
                                    val caps = connectivityMgr?.getNetworkCapabilities(net)
                                    caps != null &&
                                    caps.hasCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                                    !caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN)
                                }
                            } else null
                            connectivityMgr?.bindProcessToNetwork(targetNet)
                            android.util.Log.d("Network", "VPN bypass=$enabled net=$targetNet")
                            if (enabled && targetNet != null) {
                                val linkProps = connectivityMgr?.getLinkProperties(targetNet)
                                val iface = linkProps?.interfaceName ?: ""
                                android.util.Log.d("Network", "Direct iface=$iface")
                                result.success(iface)
                            } else {
                                result.success("")
                            }
                        } else result.success(false)
                    }
                    "getNetworkInfo" -> {
                        val nets = connectivityMgr?.allNetworks?.map { net ->
                            val caps = connectivityMgr.getNetworkCapabilities(net)
                            val isVpn = caps?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_VPN) ?: false
                            "$net:${if(isVpn) "VPN" else "direct"}"
                        }
                        result.success(nets?.joinToString(", ") ?: "none")
                    }
                    else -> result.notImplemented()
                }
            }

        // ── yt-dlp ──
        YtDlpService.init(this)
        YtDlpService.update(this) { status -> android.util.Log.d("YtDlp", "Update: $status") }
        val ytDlpService = YtDlpService(this)
        io.flutter.plugin.common.MethodChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/ytdlp")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStreamUrl" -> ytDlpService.getStreamUrl(
                        call.argument<String>("url") ?: "",
                        result,
                        call.argument<String>("cookiePath")
                    )
                    "getFormats"   -> ytDlpService.getFormats(call.argument<String>("url") ?: "", result)
                    "updateYtDlp"  -> ytDlpService.updateYtDlp(result)
                    "getVersion"   -> {
                        try {
                            val v = com.yausername.youtubedl_android.YoutubeDL.getInstance().version(this)
                            result.success(v ?: "نامشخص")
                        } catch(e: Exception) { result.success("نامشخص") }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Gemini Live Translation ──
    io.flutter.plugin.common.MethodChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/gemini_live")
        .setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val apiKey = call.argument<String>("apiKey") ?: run { result.error("NO_KEY","",null); return@setMethodCallHandler }
                    val lang = call.argument<String>("lang") ?: "fa"
                    val dubMode = call.argument<Boolean>("dubMode") ?: false
                    pendingGeminiLang = lang
                    pendingGeminiDub = dubMode
                    geminiService?.stop()
                    geminiService = GeminiLiveService(apiKey)
                    val cfg = GeminiConfig(
                        targetLang = lang, model = call.argument<String>("model") ?: "gemini-3.5-live-translate-preview",
                        dubMode = dubMode, voice = call.argument<String>("voice") ?: "Charon",
                        silenceDurationMs = call.argument<Int>("silenceMs") ?: 350,
                        prefixPaddingMs = call.argument<Int>("prefixMs") ?: 20,
                        startSensitivity = call.argument<String>("startSens") ?: "START_SENSITIVITY_HIGH",
                        endSensitivity = call.argument<String>("endSens") ?: "END_SENSITIVITY_HIGH",
                        chunkMs = call.argument<Int>("chunkMs") ?: 100)
                    pendingGeminiCfg = cfg
                    // اگه projection قبلی هنوز معتبره، استفاده کن
                    val existing = cachedProjection
                    if (existing != null && SharedAudioService.isRunning()) {
                        android.util.Log.d("Gemini", "Reusing existing MediaProjection")
                        Thread { geminiService?.start(cfg, existing) }.start()
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val svcIntent = android.content.Intent(this, MediaProjectionService::class.java)
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
                        startForegroundService(svcIntent) else startService(svcIntent)
                    android.os.SystemClock.sleep(300)
                    val mgr = getSystemService(android.media.projection.MediaProjectionManager::class.java)
                    if (mgr != null) startActivityForResult(mgr.createScreenCaptureIntent(), PROJ_REQ_GEMINI)
                    else geminiService?.start(GeminiConfig(
                            targetLang=lang, dubMode=dubMode,
                            silenceDurationMs=call.argument<Int>("silenceMs") ?: 350,
                            prefixPaddingMs=call.argument<Int>("prefixMs") ?: 20,
                            startSensitivity=call.argument<String>("startSens") ?: "START_SENSITIVITY_HIGH",
                            endSensitivity=call.argument<String>("endSens") ?: "END_SENSITIVITY_HIGH",
                            chunkMs=call.argument<Int>("chunkMs") ?: 100), null)
                    result.success(null)
                }
                "sendAudio" -> {
                    @Suppress("UNCHECKED_CAST")
                    val bytes = (call.argument<Any>("data") as? ByteArray) ?: return@setMethodCallHandler
                    geminiService?.sendAudio(bytes)
                    result.success(null)
                }
                "stop" -> {
                    geminiService?.stop(); geminiService = null
                    // رها کردن MediaProjection
                    cachedProjection?.stop(); cachedProjection = null
                    result.success(null)
                }
                "getNextEvent" -> result.success(geminiService?.getNextEvent())
                "clearBuffer" -> {
                    geminiService?.clearBuffer()
                    result.success(null)
                }
                "setDubVolume" -> {
                    val vol = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    geminiService?.setDubVolume(vol); result.success(null)
                }
                "setOrigVolume" -> {
                    val vol = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    geminiService?.setOrigVolume(vol); result.success(null)
                }
                else -> result.notImplemented()
            }
        }

    // ── Android Built-in STT ──
        androidSttCallback = io.flutter.plugin.common.MethodChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/android_stt_callback")
        io.flutter.plugin.common.MethodChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/android_stt")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startAndroidStt" -> {
                        val lang = call.argument<String>("lang") ?: "fa"
                        androidSttService = AndroidBuiltinSttService(this)
                        androidSttService?.setCallback(androidSttCallback)
                        androidSttService?.start(lang)
                        result.success(null)
                    }
                    "stopAndroidStt" -> { androidSttService?.stop(); result.success(null) }
                    "getAndroidSttNextEvent" -> result.success(androidSttService?.getNextEvent())
                    else -> result.notImplemented()
                }
            }

        // ── Vosk STT ──
        io.flutter.plugin.common.EventChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/vosk_events")
            .setStreamHandler(object : io.flutter.plugin.common.EventChannel.StreamHandler {
                override fun onListen(args: Any?, s: io.flutter.plugin.common.EventChannel.EventSink?) {
                    voskSink = s }
                override fun onCancel(args: Any?) {}
            })
        voskCallbackChannel = io.flutter.plugin.common.MethodChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/vosk_callback")

        io.flutter.plugin.common.MethodChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/vosk")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMediaProjection" -> {
                        val lang = call.argument<String>("lang") ?: "en"
                        val modelId = call.argument<String>("modelId")
                        voskService = VoskService(this, voskCallbackChannel)
                        pendingVoskLang = lang
                        // اگه SharedAudioService فعاله (Gemini در حال اجراست)
                        // Vosk بدون projection جدید start میشه
                        if (SharedAudioService.isRunning()) {
                            android.util.Log.d("Vosk", "Using SharedAudioService — skip MediaProjection")
                            Thread { voskService?.start(lang, null, modelId) }.start()
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val svcIntent = android.content.Intent(this, MediaProjectionService::class.java)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O)
                            startForegroundService(svcIntent) else startService(svcIntent)
                        android.os.SystemClock.sleep(500)
                        val mgr = getSystemService(android.media.projection.MediaProjectionManager::class.java)
                        if (mgr != null) startActivityForResult(mgr.createScreenCaptureIntent(), PROJ_REQ_VOSK)
                        else Thread { voskService?.start(lang, null, modelId) }.start()
                        result.success(null)
                    }
                    "startDirect" -> {
                        val lang = call.argument<String>("lang") ?: "en"
                        val modelId = call.argument<String>("modelId")
                        voskService = VoskService(this, voskCallbackChannel)
                        Thread {
                            // صبر تا SharedAudioService آماده بشه (max 5s)
                            var waited = 0
                            while (!SharedAudioService.isRunning() && waited < 5000) {
                                Thread.sleep(200); waited += 200
                            }
                            android.util.Log.d("Vosk", "SharedAudio running=${SharedAudioService.isRunning()} after ${waited}ms")
                            voskService?.start(lang, null, modelId)
                        }.start()
                        result.success(null)
                    }
                    "stop" -> {
                        voskService?.stop()
                        // پایان دادن به MediaProjection foreground service
                        stopService(android.content.Intent(this, MediaProjectionService::class.java))
                        result.success(null)
                    }
                    "getNextEvent" -> result.success(voskService?.getNextEvent())
                    "extractModel" -> {
                        val zipPath = call.argument<String>("zipPath") ?: ""
                        val destDir = call.argument<String>("destDir") ?: ""
                        try {
                            val zf = java.util.zip.ZipFile(zipPath)
                            val entries = zf.entries()
                            while (entries.hasMoreElements()) {
                                val entry = entries.nextElement()
                                val outFile = java.io.File(destDir, entry.name)
                                if (entry.isDirectory) { outFile.mkdirs(); continue }
                                outFile.parentFile?.mkdirs()
                                zf.getInputStream(entry).use { inp -> outFile.outputStream().use { out -> inp.copyTo(out) } }
                            }
                            zf.close(); result.success(null)
                        } catch (e: Exception) { result.error("EXTRACT_ERROR", e.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Deepgram ──
        io.flutter.plugin.common.EventChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/deepgram_events")
            .setStreamHandler(object : io.flutter.plugin.common.EventChannel.StreamHandler {
                private var deepgramSink: io.flutter.plugin.common.EventChannel.EventSink? = null
                private var deepgramService: DeepgramService? = null
                override fun onListen(a: Any?, sink: io.flutter.plugin.common.EventChannel.EventSink?) {
                    deepgramSink = sink; deepgramService?.setSink(sink) }
                override fun onCancel(a: Any?) { deepgramSink = null }
            })
        MethodChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/deepgram").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val lang = call.argument<String>("language") ?: "multi"
                    val workerUrl = (call.argument<String>("workerUrl") ?: "").trimEnd('/')
                    val streamUrl = call.argument<String>("streamUrl") ?: ""
                    val svc = DeepgramService(this, workerUrl)
                    svc.setStreamUrl(streamUrl)
                    Thread { svc.start(lang) }.start()
                    result.success(null)
                }
                "stop" -> { result.success(null) }
                else -> result.notImplemented()
            }
        }

        // ── Thumbnail ──
        MethodChannel(fe.dartExecutor.binaryMessenger, THUMB_CH).setMethodCallHandler { call, result ->
            if (call.method != "getThumbnail") { result.notImplemented(); return@setMethodCallHandler }
            val path = call.argument<String>("path") ?: run { handler.post { result.success(null) }; return@setMethodCallHandler }
            val timeMs = call.argument<Int>("timeMs") ?: 1000
            val key = "$path@$timeMs"
            if (thumbCache.containsKey(key)) { handler.post { result.success(thumbCache[key]) }; return@setMethodCallHandler }
            executor.execute { handler.post { result.success(genThumb(path, timeMs.toLong() * 1000L).also { thumbCache[key] = it }) } }
        }

        // ── PiP + Notification ──
        pipCh = MethodChannel(fe.dartExecutor.binaryMessenger, PIP_CH).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterPip" -> { playing = call.argument<Boolean>("playing") ?: false; playerActive = true; title = call.argument<String>("title") ?: title; enterPip(); result.success(true) }
                    "updateState" -> { playing = call.argument<Boolean>("playing") ?: false; playerActive = true; title = call.argument<String>("title") ?: title; showNotif(); if (Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode) updatePipParams(); result.success(null) }
                    "hideNotif" -> { nm().cancel(NOTIF_ID); playerActive = false; playing = false; result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }

        // ── Whisper Audio Extraction ──
        whisperCh = MethodChannel(fe.dartExecutor.binaryMessenger, WHISPER_CH)
        whisperCh!!.setMethodCallHandler { call, result ->

        io.flutter.plugin.common.EventChannel(fe.dartExecutor.binaryMessenger, "com.vezoo.player/ai_cancel")
            .setStreamHandler(object : io.flutter.plugin.common.EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: io.flutter.plugin.common.EventChannel.EventSink?) { aiCancelSink = sink }
                override fun onCancel(args: Any?) { aiCancelSink = null }
            })

            when (call.method) {
                "extractAudio" -> {
                    val input = call.argument<String>("input") ?: run { result.error("NO_INPUT","",null); return@setMethodCallHandler }
                    val output = call.argument<String>("output") ?: run { result.error("NO_OUTPUT","",null); return@setMethodCallHandler }
                    extractCancel.set(false)
                    executor.execute {
                        try { extractAudioWav(input, output, extractCancel); handler.post { result.success(output) } }
                        catch (e: Exception) { handler.post { result.error("EXTRACT_FAILED", e.message, null) } }
                    }
                }
                "getModelsDir" -> result.success(java.io.File(filesDir, "whisper_models").also { it.mkdirs() }.absolutePath)
                "backupModels" -> {
                    val destDir = call.argument<String>("destDir") ?: run { result.error("NO_PATH","",null); return@setMethodCallHandler }
                    executor.execute {
                        try {
                            val dest = java.io.File(destDir).also { it.mkdirs() }
                            val copied = mutableListOf<String>()
                            listOf(java.io.File(filesDir, "whisper_models")).forEach { dir ->
                                if (!dir.exists()) return@forEach
                                dir.walkTopDown().forEach { f ->
                                    if (f.isFile && (f.extension == "bin" || f.name.contains("ggml"))) {
                                        f.copyTo(java.io.File(dest, f.name), overwrite = true)
                                        if (!copied.contains(f.name)) copied.add(f.name)
                                    }
                                }
                            }
                            if (copied.isEmpty()) handler.post { result.error("NO_FILES","هیچ فایلی یافت نشد",null) }
                            else handler.post { result.success(copied) }
                        } catch (e: Exception) { handler.post { result.error("BACKUP_FAILED", e.message, null) } }
                    }
                }
                "importModel" -> {
                    val srcPath = call.argument<String>("path") ?: run { result.error("NO_PATH","",null); return@setMethodCallHandler }
                    val modelsDirPath = call.argument<String>("modelsDir")
                    executor.execute {
                        try {
                            val src = java.io.File(srcPath)
                            val targetDir = java.io.File(modelsDirPath ?: "${filesDir.absolutePath}/whisper_models").also { it.mkdirs() }
                            val dst = java.io.File(targetDir, src.name)
                            src.copyTo(dst, overwrite = true)
                            handler.post { result.success(dst.absolutePath) }
                        } catch (e: Exception) { handler.post { result.error("IMPORT_FAILED", e.message, null) } }
                    }
                }
                "extractAudioRange" -> {
                    val input = call.argument<String>("input") ?: run { result.error("NO_INPUT","",null); return@setMethodCallHandler }
                    val output = call.argument<String>("output") ?: run { result.error("NO_OUTPUT","",null); return@setMethodCallHandler }
                    val startMs = (call.argument<Int>("startMs") ?: 0).toLong()
                    val durMs   = (call.argument<Int>("durationMs") ?: 30000).toLong()
                    extractCancel.set(false)
                    executor.execute {
                        try { extractAudioWavRange(input, output, extractCancel, startMs, durMs); handler.post { result.success(output) } }
                        catch (e: Exception) { handler.post { result.error("EXTRACT_RANGE_FAILED", e.message, null) } }
                    }
                }
                "cancelExtraction" -> { extractCancel.set(true); result.success(null) }
                "getCacheDir" -> result.success(cacheDir.absolutePath)
                "getDeviceInfo" -> {
                    try {
                        val am = getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                        val mi = android.app.ActivityManager.MemoryInfo()
                        am.getMemoryInfo(mi)
                        result.success((mi.totalMem / (1024 * 1024)).toInt())
                    } catch (e: Throwable) { result.error("DEVICE_INFO_FAILED", e.message, null) }
                }
                "getVideoDuration" -> {
                    val path = call.argument<String>("path") ?: run { result.error("NO_PATH","",null); return@setMethodCallHandler }
                    executor.execute {
                        try {
                            val r = MediaMetadataRetriever()
                            if (path.startsWith("http://") || path.startsWith("https://"))
                                r.setDataSource(path, mapOf("User-Agent" to "Vezoo/1.0"))
                            else r.setDataSource(applicationContext, Uri.fromFile(File(path)))
                            val dur = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                            r.release(); handler.post { result.success(dur.toInt()) }
                        } catch (e: Throwable) { handler.post { result.error("DURATION_FAILED", e.message, null) } }
                    }
                }
                "startLiveSubService" -> {
                    val t = call.argument<String>("title") ?: "زیرنویس زنده"
                    val tx = call.argument<String>("text") ?: "در حال پردازش..."
                    val intent = Intent(this, LiveSubService::class.java).apply { putExtra("title", t); putExtra("text", tx) }
                    if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                    LiveSubServiceHelper.onServiceDestroyed = { handler.post { whisperCh?.invokeMethod("liveSubServiceDestroyed", null) } }
                    result.success(null)
                }
                "stopLiveSubService" -> { LiveSubServiceHelper.onServiceDestroyed = null; stopService(Intent(this, LiveSubService::class.java)); result.success(null) }
                "showAiProgress" -> { showAiProgressNotif(call.argument<String>("title") ?: "زیرنویس AI", 0, "Starting..."); result.success(null) }
                "updateAiProgress" -> { showAiProgressNotif(null, call.argument<Int>("percent") ?: 0, call.argument<String>("status") ?: ""); result.success(null) }
                "hideAiProgress" -> { nm().cancel(AI_NOTIF_ID); result.success(null) }
                "v2InitContext" -> {
                    val modelPath = call.argument<String>("modelPath") ?: run { result.error("NO_MODEL","",null); return@setMethodCallHandler }
                    executor.execute {
                        try { val ctx = WhisperV2Bridge.nativeInitContext(modelPath); handler.post { if (ctx != 0L) result.success(ctx) else result.error("INIT_FAILED","ptr is 0",null) } }
                        catch (e: Throwable) { handler.post { result.error("INIT_EXCEPTION", e.message, null) } }
                    }
                }
                "v2FreeContext" -> { val ctx = (call.argument<Number>("ctx") ?: 0).toLong(); executor.execute { try { WhisperV2Bridge.nativeFreeContext(ctx) } catch (_: Throwable) {}; handler.post { result.success(null) } } }
                "v2Transcribe" -> {
                    val ctx = (call.argument<Number>("ctx") ?: 0).toLong()
                    val wavPath = call.argument<String>("wavPath") ?: run { result.error("NO_WAV","",null); return@setMethodCallHandler }
                    val lang = call.argument<String>("lang") ?: "en"
                    val threads = call.argument<Int>("threads") ?: 4
                    val translate = call.argument<Boolean>("translate") ?: false
                    executor.execute {
                        try { val text = WhisperV2Bridge.nativeTranscribeWav(ctx, wavPath, lang, threads, translate); handler.post { result.success(text) } }
                        catch (e: Throwable) { handler.post { result.error("TRANSCRIBE_EXCEPTION", e.message, null) } }
                    }
                }
                "v2SystemInfo" -> { try { result.success(WhisperV2Bridge.nativeGetSystemInfo()) } catch (e: Throwable) { result.error("SYSINFO_EXCEPTION", e.message, null) } }
                else -> result.notImplemented()
            }
        }

        // ── VEZ Crypto ──
        MethodChannel(fe.dartExecutor.binaryMessenger, VEZ_CH).setMethodCallHandler { call, result ->
            when (call.method) {
                "initMasterKey" -> {
                    try {
                        val serverHalf = Base64.decode(call.argument<String>("server_half") ?: throw Exception("missing"), Base64.DEFAULT)
                        val masterKey = hkdf(serverHalf + APP_HALF, HKDF_SALT, HKDF_INFO, 32)
                        storeMasterKey(masterKey); handler.post { result.success(true) }
                    } catch (e: Exception) { handler.post { result.error("INIT_FAILED", e.message, null) } }
                }
                "hasMasterKey" -> handler.post { result.success(loadMasterKey() != null) }
                "decryptVez" -> {
                    val inputPath = call.argument<String>("input") ?: run { result.error("NO_INPUT","",null); return@setMethodCallHandler }
                    val outputPath = call.argument<String>("output") ?: run { result.error("NO_OUTPUT","",null); return@setMethodCallHandler }
                    executor.execute {
                        try { val mk = loadMasterKey() ?: throw Exception("Key not found"); decryptVez(inputPath, outputPath, mk); handler.post { result.success(outputPath) } }
                        catch (e: Exception) { handler.post { result.error("DECRYPT_FAILED", e.message, null) } }
                    }
                }
                "getCacheDir" -> handler.post { result.success(cacheDir.absolutePath) }
                "getVezMeta" -> {
                    val path = call.argument<String>("path") ?: run { result.error("NO_PATH","",null); return@setMethodCallHandler }
                    executor.execute {
                        try { val mk = loadMasterKey() ?: throw Exception("Key not found"); handler.post { result.success(readVezMeta(path, mk)) } }
                        catch (e: Exception) { handler.post { result.error("META_FAILED", e.message, null) } }
                    }
                }
                else -> result.notImplemented()
            }
        }

        val f = IntentFilter().apply { addAction(A_PLAY); addAction(A_PAUSE); addAction(A_CLOSE); addAction(A_AI_CANCEL) }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, f, Context.RECEIVER_EXPORTED)
        else registerReceiver(receiver, f)
    }

    private fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray =
        nativeHkdf(ikm, salt, info, length) ?: throw Exception("HKDF failed")

    private fun gcmDecrypt(key: ByteArray, data: ByteArray): ByteArray =
        nativeGcmDecrypt(key, data) ?: throw Exception("GCM decrypt failed")

    private fun ensureWrapKey() {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(KS_ALIAS)) {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(KS_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
                generateKey()
            }
        }
    }

    private fun storeMasterKey(masterKey: ByteArray) {
        ensureWrapKey()
        val wk = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }.getKey(KS_ALIAS, null) as SecretKey
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, wk)
        val enc = cipher.doFinal(masterKey)
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString("mk_iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .putString("mk_data", Base64.encodeToString(enc, Base64.NO_WRAP)).apply()
    }

    private fun loadMasterKey(): ByteArray? {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val iv   = Base64.decode(prefs.getString("mk_iv",   null) ?: return null, Base64.NO_WRAP)
        val data = Base64.decode(prefs.getString("mk_data", null) ?: return null, Base64.NO_WRAP)
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(KS_ALIAS)) return null
        val wk = ks.getKey(KS_ALIAS, null) as SecretKey
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.DECRYPT_MODE, wk, GCMParameterSpec(128, iv))
        return cipher.doFinal(data)
    }

    private fun extractAudioWav(videoPath: String, outputPath: String, cancel: AtomicBoolean) {
        val extractor = MediaExtractor()
        if (videoPath.startsWith("http")) extractor.setDataSource(videoPath, mapOf("User-Agent" to "Vezoo/1.0"))
        else extractor.setDataSource(videoPath)
        var audioIdx = -1; lateinit var audioFmt: MediaFormat
        for (i in 0 until extractor.trackCount) { val fmt = extractor.getTrackFormat(i); if (fmt.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) { audioIdx = i; audioFmt = fmt; break } }
        require(audioIdx >= 0) { "No audio track" }
        extractor.selectTrack(audioIdx)
        val origRate = audioFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE); val channels = audioFmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val codec = MediaCodec.createDecoderByType(audioFmt.getString(MediaFormat.KEY_MIME)!!); codec.configure(audioFmt, null, null, 0); codec.start()
        val bufInfo = MediaCodec.BufferInfo(); var pcm = ShortArray(1_000_000); var pcmLen = 0; var inputDone = false
        try {
            while (!cancel.get()) {
                if (!inputDone) { val inIdx = codec.dequeueInputBuffer(10_000); if (inIdx >= 0) { val buf = codec.getInputBuffer(inIdx)!!; val sz = extractor.readSampleData(buf, 0); if (sz < 0) { codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true } else { codec.queueInputBuffer(inIdx, 0, sz, extractor.sampleTime, 0); extractor.advance() } } }
                val outIdx = codec.dequeueOutputBuffer(bufInfo, 10_000)
                if (outIdx >= 0) {
                    val buf = codec.getOutputBuffer(outIdx)!!; val s = ShortArray(bufInfo.size / 2); buf.order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(s); codec.releaseOutputBuffer(outIdx, false)
                    if (channels >= 2) { val oc = s.size / channels; if (pcmLen + oc > pcm.size) pcm = pcm.copyOf(pcm.size * 2); var i = 0; while (i + 1 < s.size) { pcm[pcmLen++] = ((s[i].toInt() + s[i + 1].toInt()) / 2).toShort(); i += channels } }
                    else { if (pcmLen + s.size > pcm.size) pcm = pcm.copyOf(pcm.size * 2); System.arraycopy(s, 0, pcm, pcmLen, s.size); pcmLen += s.size }
                    if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally { codec.stop(); codec.release(); extractor.release() }
        if (cancel.get()) throw Exception("cancelled")
        val trimmed = pcm.copyOf(pcmLen); val out = if (origRate == 16000) trimmed else resamplePcm(trimmed, origRate, 16000); writeWav(outputPath, out, 16000)
    }

    private fun extractAudioWavRange(videoPath: String, outputPath: String, cancel: AtomicBoolean, startMs: Long, durationMs: Long) {
        val extractor = MediaExtractor()
        if (videoPath.startsWith("http")) extractor.setDataSource(videoPath, mapOf("User-Agent" to "Vezoo/1.0"))
        else extractor.setDataSource(videoPath)
        var audioIdx = -1; lateinit var audioFmt: MediaFormat
        for (i in 0 until extractor.trackCount) { val fmt = extractor.getTrackFormat(i); if (fmt.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true) { audioIdx = i; audioFmt = fmt; break } }
        require(audioIdx >= 0) { "No audio track" }
        extractor.selectTrack(audioIdx); extractor.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        val origRate = audioFmt.getInteger(MediaFormat.KEY_SAMPLE_RATE); val channels = audioFmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val codec = MediaCodec.createDecoderByType(audioFmt.getString(MediaFormat.KEY_MIME)!!); codec.configure(audioFmt, null, null, 0); codec.start()
        val bufInfo = MediaCodec.BufferInfo(); val endUs = (startMs + durationMs) * 1000L; var pcm = ShortArray(500_000); var pcmLen = 0; var inputDone = false
        try {
            while (!cancel.get()) {
                if (!inputDone) { val inIdx = codec.dequeueInputBuffer(10_000); if (inIdx >= 0) { val buf = codec.getInputBuffer(inIdx)!!; val sz = extractor.readSampleData(buf, 0); val st = extractor.sampleTime; if (sz < 0 || st >= endUs) { codec.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); inputDone = true } else { codec.queueInputBuffer(inIdx, 0, sz, st, 0); extractor.advance() } } }
                val outIdx = codec.dequeueOutputBuffer(bufInfo, 10_000)
                if (outIdx >= 0) {
                    val buf = codec.getOutputBuffer(outIdx)!!; val s = ShortArray(bufInfo.size / 2); buf.order(java.nio.ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(s); codec.releaseOutputBuffer(outIdx, false)
                    if (channels >= 2) { if (pcmLen + s.size/channels > pcm.size) pcm = pcm.copyOf(pcm.size * 2); var i = 0; while (i + 1 < s.size) { pcm[pcmLen++] = ((s[i].toInt() + s[i+1].toInt()) / 2).toShort(); i += channels } }
                    else { if (pcmLen + s.size > pcm.size) pcm = pcm.copyOf(pcm.size * 2); System.arraycopy(s, 0, pcm, pcmLen, s.size); pcmLen += s.size }
                    if (bufInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally { codec.stop(); codec.release(); extractor.release() }
        if (cancel.get()) throw Exception("cancelled")
        val trimmed = pcm.copyOf(pcmLen); val out = if (origRate == 16000) trimmed else resamplePcm(trimmed, origRate, 16000); writeWav(outputPath, out, 16000)
    }

    private fun resamplePcm(src: ShortArray, from: Int, to: Int): ShortArray {
        val out = ShortArray((src.size.toLong() * to / from).toInt()); val ratio = from.toDouble() / to.toDouble()
        for (i in out.indices) { val pos = i * ratio; val idx = pos.toInt().coerceIn(0, src.size - 1); val a = src[idx].toDouble(); val b = src.getOrElse(idx + 1) { src.last() }.toDouble(); out[i] = (a + (b - a) * (pos - idx)).toInt().coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort() }
        return out
    }

    private fun writeWav(path: String, pcm: ShortArray, rate: Int) {
        val dataSize = pcm.size * 2
        java.io.RandomAccessFile(path, "rw").use { f ->
            f.write(byteArrayOf(82,73,70,70)); f.wLe32(dataSize + 36); f.write(byteArrayOf(87,65,86,69)); f.write(byteArrayOf(102,109,116,32))
            f.wLe32(16); f.wLe16(1); f.wLe16(1); f.wLe32(rate); f.wLe32(rate * 2); f.wLe16(2); f.wLe16(16)
            f.write(byteArrayOf(100,97,116,97)); f.wLe32(dataSize)
            for (s in pcm) { f.write(s.toInt() and 0xFF); f.write((s.toInt() shr 8) and 0xFF) }
        }
    }
    private fun java.io.RandomAccessFile.wLe32(v: Int) { write(v and 0xFF); write((v shr 8) and 0xFF); write((v shr 16) and 0xFF); write((v shr 24) and 0xFF) }
    private fun java.io.RandomAccessFile.wLe16(v: Int) { write(v and 0xFF); write((v shr 8) and 0xFF) }

    private fun readFull(fis: FileInputStream, len: Int): ByteArray {
        val buf = ByteArray(len); var off = 0
        while (off < len) { val n = fis.read(buf, off, len - off); if (n == -1) break; off += n }
        return buf
    }
    private fun readInt(fis: FileInputStream): Int {
        val b = ByteArray(4); fis.read(b)
        return ((b[0].toInt() and 0xFF) shl 24) or ((b[1].toInt() and 0xFF) shl 16) or ((b[2].toInt() and 0xFF) shl 8) or (b[3].toInt() and 0xFF)
    }

    private fun parseHeader(path: String, masterKey: ByteArray): Triple<ByteArray, String, FileInputStream> {
        val fis = FileInputStream(path); val magic = readFull(fis, 6)
        if (!magic.contentEquals(MAGIC)) throw Exception("Not a VEZOO file")
        fis.read(); val fileKey = gcmDecrypt(masterKey, readFull(fis, readInt(fis)))
        val metaJson = String(gcmDecrypt(fileKey, readFull(fis, readInt(fis))), Charsets.UTF_8)
        return Triple(fileKey, metaJson, fis)
    }

    private fun readVezMeta(path: String, masterKey: ByteArray): Map<String, Any> {
        val (_, metaJson, fis) = parseHeader(path, masterKey); fis.close()
        val map = mutableMapOf<String, Any>()
        metaJson.replace("{","").replace("}","").split(",").forEach { pair ->
            val kv = pair.split(":"); if (kv.size >= 2) { val k = kv[0].trim().replace("\"",""); val v = kv.drop(1).joinToString(":").trim().replace("\"",""); map[k] = v.toLongOrNull() ?: v.toBooleanStrictOrNull() ?: v }
        }
        return map
    }

    private fun decryptVez(inputPath: String, outputPath: String, masterKey: ByteArray) {
        val (fileKey, _, fis) = parseHeader(inputPath, masterKey)
        BufferedOutputStream(FileOutputStream(outputPath), 1024 * 1024).use { out ->
            val sizeBuf = ByteArray(4)
            while (fis.read(sizeBuf) == 4) {
                val chunkLen = ((sizeBuf[0].toInt() and 0xFF) shl 24) or ((sizeBuf[1].toInt() and 0xFF) shl 16) or ((sizeBuf[2].toInt() and 0xFF) shl 8) or (sizeBuf[3].toInt() and 0xFF)
                if (chunkLen <= 0 || chunkLen > 20 * 1024 * 1024) break
                out.write(gcmDecrypt(fileKey, readFull(fis, chunkLen)))
            }
        }; fis.close()
    }

    private fun requestNotifPermission() {
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED)
            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
    }
    private fun nm() = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    private fun createNotifChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            nm().createNotificationChannel(NotificationChannel(NOTIF_CH_ID, "کنترل پلیر", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
            nm().createNotificationChannel(NotificationChannel(AI_NOTIF_CH_ID, "پیشرفت زیرنویس AI", NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) })
        }
    }
    private fun showAiProgressNotif(newTitle: String?, percent: Int, status: String) {
        if (newTitle != null) aiNotifTitle = newTitle
        nm().notify(AI_NOTIF_ID, NotificationCompat.Builder(this, AI_NOTIF_CH_ID)
            .setSmallIcon(android.R.drawable.ic_popup_sync).setContentTitle(aiNotifTitle).setContentText(status)
            .setProgress(100, percent.coerceIn(0, 100), percent <= 0).setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(percent < 100).setOnlyAlertOnce(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", pi(A_AI_CANCEL, 5)).build())
    }
    private fun pi(action: String, code: Int) = PendingIntent.getBroadcast(this, code, Intent(action), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun showNotif() {
        nm().notify(NOTIF_ID, NotificationCompat.Builder(this, NOTIF_CH_ID)
            .setSmallIcon(android.R.drawable.ic_media_play).setContentTitle(title).setContentText(if (playing) "Playing" else "Paused")
            .setPriority(NotificationCompat.PRIORITY_LOW).setOngoing(playing)
            .addAction(if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play, if (playing) "Pause" else "Play", pi(if (playing) A_PAUSE else A_PLAY, 1))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Close", pi(A_CLOSE, 2)).build())
    }
    private fun enterPip() {
        if (Build.VERSION.SDK_INT < 26) return
        val p = PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).also { if (Build.VERSION.SDK_INT >= 26) it.setActions(buildActions()) }.build()
        enterPictureInPictureMode(p)
    }
    private fun buildActions(): List<android.app.RemoteAction> {
        if (Build.VERSION.SDK_INT < 26) return emptyList()
        return listOf(
            android.app.RemoteAction(android.graphics.drawable.Icon.createWithResource(this, if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play), if (playing) "Pause" else "Play", "", pi(if (playing) A_PAUSE else A_PLAY, 3)),
            android.app.RemoteAction(android.graphics.drawable.Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel), "Close", "", pi(A_CLOSE, 4))
        )
    }
    private fun updatePipParams() { if (Build.VERSION.SDK_INT >= 26) setPictureInPictureParams(PictureInPictureParams.Builder().setActions(buildActions()).build()) }
    override fun onPictureInPictureModeChanged(inPip: Boolean, cfg: android.content.res.Configuration?) { super.onPictureInPictureModeChanged(inPip, cfg); pipCh?.invokeMethod("pipModeChanged", mapOf("inPip" to inPip)) }
    override fun onUserLeaveHint() { super.onUserLeaveHint(); if (playing && playerActive && Build.VERSION.SDK_INT >= 26) try { enterPip() } catch (_: Exception) {} }
    override fun onStart() { super.onStart(); if (playing) showNotif() }
    override fun onDestroy() { try { unregisterReceiver(receiver) } catch (_: Exception) {}; nm().cancel(NOTIF_ID); super.onDestroy() }

    @Suppress("DEPRECATION")
    override fun onActivityResult(req: Int, result: Int, data: android.content.Intent?) {
        super.onActivityResult(req, result, data)
        if (req == PROJ_REQ_GEMINI && result == android.app.Activity.RESULT_OK && data != null) {
            val mgr = getSystemService(android.media.projection.MediaProjectionManager::class.java)
            val projection = mgr?.getMediaProjection(result, data)
            pendingGeminiLang?.let { lang ->
                pendingGeminiLang = null
                cachedProjection = projection  // cache projection
                val pendingCfg = pendingGeminiCfg ?: GeminiConfig(targetLang=lang, dubMode=pendingGeminiDub)
                Thread {
                    try { geminiService?.start(pendingCfg, projection) }
                    catch (e: Throwable) { android.util.Log.e("Gemini", "start failed: ${e.message}") }
                }.start()
            }
        }
        if (req == PROJ_REQ_VOSK && result == android.app.Activity.RESULT_OK && data != null) {
            val mgr = getSystemService(android.media.projection.MediaProjectionManager::class.java)
            val projection = mgr?.getMediaProjection(result, data)
            pendingVoskLang?.let { lang ->
                pendingVoskLang = null
                Thread {
                    try { voskService?.start(lang, projection) }
                    catch (e: Throwable) { android.util.Log.e("Vosk", "start failed: ${e.message}") }
                }.start()
            }
        }
    }
}

private fun genThumb(path: String, timeUs: Long): ByteArray? {
    val r = MediaMetadataRetriever()
    return try {
        if (!java.io.File(path).exists()) return null
        r.setDataSource(path)
        var bmp: Bitmap? = null
        for (t in longArrayOf(timeUs, 0L)) { bmp = r.getFrameAtTime(t, MediaMetadataRetriever.OPTION_CLOSEST_SYNC); if (bmp != null) break }
        bmp ?: return null
        val out = java.io.ByteArrayOutputStream()
        Bitmap.createScaledBitmap(bmp, 160, 90, true).compress(Bitmap.CompressFormat.JPEG, 75, out)
        out.toByteArray()
    } catch (_: Exception) { null } finally { try { r.release() } catch (_: Exception) {} }
}
