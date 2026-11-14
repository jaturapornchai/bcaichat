package com.bcaichat.app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.net.URLEncoder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject

/**
 * Starts [BcRealtimeAlertService] on boot or package update when a signed-in
 * user session exists in FlutterSharedPreferences.
 */
class BcBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (
            action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val jwt = prefs.getString("flutter.bcaichat_jwt_token", null)
        if (!jwt.isNullOrEmpty()) {
            BcRealtimeAlertService.startOrSync(context.applicationContext)
        }
    }
}

/**
 * Persistent self-hosted WebSocket foreground service for Android.
 * Keeps real-time chat delivery active when MainActivity is closed or when
 * the phone screen is turned off, waking the device with lock-screen alerts
 * and the user's selected sound.
 */
class BcRealtimeAlertService : Service() {
    companion object {
        private const val TAG = "BcRealtimeAlertService"
        private const val PREFS_NAME = "FlutterSharedPreferences"

        const val ACTION_START = "com.bcaichat.app.action.START_REALTIME_ALERTS"
        const val ACTION_SYNC = "com.bcaichat.app.action.SYNC_REALTIME_ALERTS"
        const val ACTION_STOP = "com.bcaichat.app.action.STOP_REALTIME_ALERTS"

        private const val FOREGROUND_CHANNEL_ID = "bc_fg_realtime_v1"
        private const val MSG_CHANNEL_PREFIX = "bc_msg_v2_"
        private const val FOREGROUND_NOTIFICATION_ID = 9100
        private const val AI_USER_ID = "user_ai"

        private val SOUND_CODES = listOf(
            "ting",
            "pop",
            "chime",
            "marimba",
            "bell",
            "soft",
            "urgent",
            "robot",
            "none",
        )

        private val SOUND_LABELS = mapOf(
            "ting" to "ติ๊ง",
            "pop" to "ป๊อป",
            "chime" to "กริ๊งสองจังหวะ",
            "marimba" to "มาริมบา",
            "bell" to "ระฆังใส",
            "soft" to "นุ่มนวล",
            "urgent" to "ด่วนมาก",
            "robot" to "หุ่นยนต์ AI",
            "none" to "ไม่มีเสียง",
        )

        @Volatile
        var isServiceRunning: Boolean = false
            private set

        fun startOrSync(context: Context): Boolean {
            return try {
                val appCtx = context.applicationContext
                val intent = Intent(appCtx, BcRealtimeAlertService::class.java).apply {
                    action = if (isServiceRunning) ACTION_SYNC else ACTION_START
                }
                ContextCompat.startForegroundService(appCtx, intent)
                true
            } catch (e: Throwable) {
                Log.w(TAG, "Unable to start foreground service: ${e.message}")
                false
            }
        }

        fun stop(context: Context): Boolean {
            return try {
                val appCtx = context.applicationContext
                appCtx.stopService(Intent(appCtx, BcRealtimeAlertService::class.java))
                true
            } catch (e: Throwable) {
                Log.w(TAG, "Unable to stop foreground service: ${e.message}")
                false
            }
        }
    }

    private data class RoomMeta(
        val name: String,
        val type: String,
        val isMuted: Boolean,
    )

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val roomCache = ConcurrentHashMap<String, RoomMeta>()
    private val seenMessageIds = LinkedHashSet<String>()

    private lateinit var powerManager: PowerManager
    private lateinit var notificationManager: NotificationManager

    private var wsClient: OkHttpClient? = null
    private var httpClient: OkHttpClient? = null
    private var webSocket: WebSocket? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var wifiLock: WifiManager.WifiLock? = null

    @Volatile
    private var destroyed = false

    @Volatile
    private var activeJwt: String? = null

    @Volatile
    private var activeApiBase: String? = null

    @Volatile
    private var connectedUserId: String? = null

    private var wsGeneration = 0
    private var retryCount = 0
    private var pendingReconnect: Runnable? = null

    override fun onCreate() {
        super.onCreate()
        isServiceRunning = true
        powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        wsClient = OkHttpClient.Builder()
            .pingInterval(20, TimeUnit.SECONDS)
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.MILLISECONDS)
            .retryOnConnectionFailure(true)
            .build()

        httpClient = OkHttpClient.Builder()
            .connectTimeout(3, TimeUnit.SECONDS)
            .readTimeout(3, TimeUnit.SECONDS)
            .callTimeout(4, TimeUnit.SECONDS)
            .build()

        ensureChannels()
        acquireWifiLock()
        registerNetworkCallback()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannels()
        startForegroundCompat()

        if (intent?.action == ACTION_STOP) {
            teardownAndStopSelf()
            return START_NOT_STICKY
        }

        val session = readSession()
        if (session.jwt.isNullOrEmpty()) {
            teardownAndStopSelf()
            return START_NOT_STICKY
        }

        val changed = session.jwt != activeJwt || session.apiBase != activeApiBase
        activeJwt = session.jwt
        activeApiBase = session.apiBase
        if (session.userId.isNotEmpty()) {
            connectedUserId = session.userId
        }

        if (changed || webSocket == null) {
            retryCount = 0
            reconnectNow()
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val jwt = readSession().jwt
        if (!jwt.isNullOrEmpty() && !destroyed) {
            try {
                val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                val restartIntent = Intent(applicationContext, BcRealtimeAlertService::class.java).apply {
                    action = ACTION_START
                }
                val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    PendingIntent.getForegroundService(
                        applicationContext,
                        9101,
                        restartIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                } else {
                    PendingIntent.getService(
                        applicationContext,
                        9101,
                        restartIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                }
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.ELAPSED_REALTIME_WAKEUP,
                    SystemClock.elapsedRealtime() + 2_000L,
                    pi,
                )
            } catch (e: Throwable) {
                Log.w(TAG, "onTaskRemoved restart scheduling failed: ${e.message}")
            }
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        destroyed = true
        isServiceRunning = false
        cancelPendingReconnect()
        closeWebSocket()
        unregisterNetworkCallback()
        releaseWifiLock()
        ioExecutor.shutdownNow()
        try {
            wsClient?.dispatcher?.executorService?.shutdown()
            httpClient?.dispatcher?.executorService?.shutdown()
        } catch (_: Throwable) {
        }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun teardownAndStopSelf() {
        cancelPendingReconnect()
        closeWebSocket()
        unregisterNetworkCallback()
        releaseWifiLock()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun startForegroundCompat() {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            this,
            FOREGROUND_NOTIFICATION_ID,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, FOREGROUND_CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("BC Ai Chat พร้อมรับข้อความตลอดเวลา")
            .setContentText("แจ้งเตือนทันทีแม้ปิดแอปหรือปิดหน้าจอ")
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_SECRET)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(pi)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                FOREGROUND_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
            )
        } else {
            ServiceCompat.startForeground(
                this,
                FOREGROUND_NOTIFICATION_ID,
                notification,
                0,
            )
        }
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val fgChannel = NotificationChannel(
            FOREGROUND_CHANNEL_ID,
            "การเชื่อมต่อแชทเบื้องหลัง",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "รักษาการเชื่อมต่อรับข้อความแบบเรียลไทม์เมื่อปิดแอปหรือปิดหน้าจอ"
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        notificationManager.createNotificationChannel(fgChannel)

        val audioAttr = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        for (code in SOUND_CODES) {
            val label = SOUND_LABELS[code] ?: code
            val channel = NotificationChannel(
                "$MSG_CHANNEL_PREFIX$code",
                "ข้อความแชทเบื้องหลัง · $label",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "แจ้งเตือนข้อความใหม่ทันทีแม้ปิดแอปหรือปิดหน้าจอ"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableLights(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 240, 120, 240)
                if (code == "none") {
                    setSound(null, null)
                } else {
                    val uri = Uri.parse("android.resource://$packageName/raw/alert_$code")
                    setSound(uri, audioAttr)
                }
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private data class SessionData(
        val jwt: String?,
        val userId: String,
        val deviceId: String,
        val apiBase: String,
    )

    private fun readSession(): SessionData {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val jwt = prefs.getString("flutter.bcaichat_jwt_token", null)
        val rawUser = prefs.getString("flutter.bcaichat_user_json", null)
        var userId = ""
        if (!rawUser.isNullOrEmpty()) {
            try {
                userId = JSONObject(rawUser).optString("id", "")
            } catch (_: Throwable) {
            }
        }
        val deviceId = prefs.getString("flutter.bcaichat_device_id", null)
            ?.takeIf { it.isNotEmpty() }
            ?: "android"
        val effective = prefs.getString("flutter.bcaichat_effective_api_base", null)
        val fallback = prefs.getString("flutter.bcaichat_api_base", null)
        val apiBase = normalizeBaseUrl(effective ?: fallback ?: "http://10.0.2.2:8096")
        return SessionData(jwt = jwt, userId = userId, deviceId = deviceId, apiBase = apiBase)
    }

    private fun normalizeBaseUrl(raw: String): String {
        var trimmed = raw.trim()
        while (trimmed.endsWith("/")) {
            trimmed = trimmed.substring(0, trimmed.length - 1)
        }
        return if (trimmed.isEmpty()) "http://10.0.2.2:8096" else trimmed
    }

    private fun deriveWsUrl(httpBase: String): String {
        val uri = try {
            Uri.parse(httpBase)
        } catch (_: Throwable) {
            null
        }
        val scheme = uri?.scheme
        val host = uri?.host
        if (scheme.isNullOrEmpty() || host.isNullOrEmpty()) {
            return "ws://127.0.0.1:8096/ws"
        }
        val wsScheme = if (scheme == "https") "wss" else "ws"
        val portPart = if (uri.port != -1) ":${uri.port}" else ""
        val pathPart = uri.path?.takeIf { it.isNotEmpty() && it != "/" } ?: ""
        return "$wsScheme://$host$portPart$pathPart/ws"
    }

    private fun acquireWifiLock() {
        try {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WifiManager.WIFI_MODE_FULL_LOW_LATENCY
            } else {
                @Suppress("DEPRECATION")
                WifiManager.WIFI_MODE_FULL_HIGH_PERF
            }
            wifiLock = wm.createWifiLock(mode, "bcaichat:realtime_wifi").apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Throwable) {
            Log.w(TAG, "WifiLock acquire failed: ${e.message}")
        }
    }

    private fun releaseWifiLock() {
        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (_: Throwable) {
        }
        wifiLock = null
    }

    private fun registerNetworkCallback() {
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val cb = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    mainHandler.post {
                        if (!destroyed && !activeJwt.isNullOrEmpty() && webSocket == null) {
                            retryCount = 0
                            reconnectNow()
                        }
                    }
                }
            }
            cm.registerNetworkCallback(NetworkRequest.Builder().build(), cb)
            networkCallback = cb
        } catch (e: Throwable) {
            Log.w(TAG, "NetworkCallback register failed: ${e.message}")
        }
    }

    private fun unregisterNetworkCallback() {
        val cb = networkCallback ?: return
        networkCallback = null
        try {
            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            cm.unregisterNetworkCallback(cb)
        } catch (_: Throwable) {
        }
    }

    private fun cancelPendingReconnect() {
        pendingReconnect?.let { mainHandler.removeCallbacks(it) }
        pendingReconnect = null
    }

    private fun closeWebSocket() {
        wsGeneration++
        try {
            webSocket?.close(1000, "reconnect")
        } catch (_: Throwable) {
        }
        webSocket = null
    }

    private fun reconnectNow() {
        if (destroyed) return
        cancelPendingReconnect()
        closeWebSocket()

        val session = readSession()
        val jwt = session.jwt
        if (jwt.isNullOrEmpty()) {
            teardownAndStopSelf()
            return
        }
        activeJwt = jwt
        activeApiBase = session.apiBase
        if (session.userId.isNotEmpty()) {
            connectedUserId = session.userId
        }

        val gen = wsGeneration
        val encodedToken = URLEncoder.encode(jwt, "UTF-8")
        val rawDevice = "${session.deviceId}_bg".take(64)
        val encodedDevice = URLEncoder.encode(rawDevice, "UTF-8")
        val wsUrl = "${deriveWsUrl(session.apiBase)}?token=$encodedToken&device=$encodedDevice"

        val request = Request.Builder().url(wsUrl).build()
        val client = wsClient ?: return

        webSocket = client.newWebSocket(
            request,
            object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    if (gen != wsGeneration || destroyed) {
                        webSocket.close(1000, "stale")
                        return
                    }
                    retryCount = 0
                    ioExecutor.execute { refreshRoomsCache(session.apiBase, jwt) }
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    if (gen != wsGeneration || destroyed) return
                    ioExecutor.execute { handleWsPayload(text) }
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    if (gen != wsGeneration) return
                    mainHandler.post { handleSocketDisconnect(gen) }
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    if (gen != wsGeneration) return
                    mainHandler.post { handleSocketDisconnect(gen) }
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    if (gen != wsGeneration) return
                    mainHandler.post { handleSocketDisconnect(gen) }
                }
            },
        )
    }

    private fun handleSocketDisconnect(expectedGen: Int) {
        if (expectedGen == wsGeneration) {
            webSocket = null
            scheduleReconnect()
        }
    }

    private fun scheduleReconnect() {
        if (destroyed || pendingReconnect != null) return
        val jwt = readSession().jwt
        if (jwt.isNullOrEmpty()) return

        val delays = longArrayOf(2_000L, 4_000L, 8_000L, 15_000L)
        val idx = retryCount.coerceAtMost(delays.size - 1)
        retryCount++
        val delayMs = delays[idx]

        val task = Runnable {
            pendingReconnect = null
            reconnectNow()
        }
        pendingReconnect = task
        mainHandler.postDelayed(task, delayMs)
    }

    private fun refreshRoomsCache(apiBase: String, jwt: String) {
        try {
            val req = Request.Builder()
                .url("$apiBase/api/conversations?folder=all")
                .header("Authorization", "Bearer $jwt")
                .get()
                .build()
            httpClient?.newCall(req)?.execute()?.use { resp ->
                if (!resp.isSuccessful) return
                val body = resp.body?.string() ?: return
                val arr = JSONArray(body)
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    val id = obj.optString("id", "")
                    if (id.isEmpty()) continue
                    val name = obj.optString("name", "")
                    val type = obj.optString("type", obj.optString("kind", "direct"))
                    val isMuted = obj.optBoolean("is_muted", false)
                    roomCache[id] = RoomMeta(name = name, type = type, isMuted = isMuted)
                }
            }
        } catch (_: Throwable) {
        }
    }

    private fun handleWsPayload(raw: String) {
        val payload = try {
            JSONObject(raw)
        } catch (_: Throwable) {
            return
        }

        when (payload.optString("event", "")) {
            "connected" -> {
                val uid = payload.optString("user_id", "")
                if (uid.isNotEmpty()) {
                    connectedUserId = uid
                }
            }
            "conversation_updated" -> {
                val session = readSession()
                val jwt = session.jwt
                if (!jwt.isNullOrEmpty()) {
                    refreshRoomsCache(session.apiBase, jwt)
                }
            }
            "new_message" -> {
                val msg = payload.optJSONObject("message") ?: return
                processIncomingMessage(msg)
            }
        }
    }

    private fun processIncomingMessage(msg: JSONObject) {
        val cpuWakeLock = try {
            powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "bcaichat:msg_cpu").apply {
                setReferenceCounted(false)
                acquire(8_000L)
            }
        } catch (_: Throwable) {
            null
        }

        try {
            val msgId = msg.optString("id", "")
            if (msgId.isNotEmpty()) {
                synchronized(seenMessageIds) {
                    if (seenMessageIds.contains(msgId)) return
                    seenMessageIds.add(msgId)
                    if (seenMessageIds.size > 200) {
                        val first = seenMessageIds.firstOrNull()
                        if (first != null) seenMessageIds.remove(first)
                    }
                }
            }

            val session = readSession()
            val myUserId = session.userId.ifEmpty { connectedUserId.orEmpty() }
            val senderId = msg.optString("sender_id", "")
            val msgType = msg.optString("type", "text")
            val isUnsent = msg.optBoolean("is_unsent", false)
            if ((myUserId.isNotEmpty() && senderId == myUserId) || msgType == "system" || isUnsent) {
                return
            }

            val interactive = powerManager.isInteractive
            if (MainActivity.isForegroundResumed && interactive) {
                return
            }

            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val popupEnabled = prefs.getBoolean("flutter.bcaichat_alert_popup", true)
            if (!popupEnabled) return

            val convId = msg.optString("conversation_id", "")
            if (convId.isEmpty()) return

            var room = roomCache[convId]
            if (room == null && !session.jwt.isNullOrEmpty()) {
                refreshRoomsCache(session.apiBase, session.jwt)
                room = roomCache[convId]
            }
            if (room?.isMuted == true) return

            val senderName = msg.optString("sender_name", "ข้อความใหม่").ifEmpty { "ข้อความใหม่" }
            val rawContent = msg.optString("content", "")
            val isConfidential = msg.optBoolean("is_confidential", false) ||
                rawContent.startsWith("[ลับส่วนตัว]") ||
                rawContent.startsWith("[ลับเฉพาะองค์กร]")
            val preview = when {
                isConfidential -> "ส่งข้อความลับ 🔒"
                msgType == "image" -> "ส่งรูปภาพ"
                msgType == "file" -> {
                    val fileName = msg.optJSONObject("attachment")?.optString("file_name", "").orEmpty()
                    if (fileName.isEmpty()) "ส่งไฟล์" else "ส่งไฟล์ $fileName"
                }
                msgType == "sticker" -> "ส่งสติกเกอร์"
                msgType == "audio" -> "ส่งข้อความเสียง"
                msgType == "poll" -> "สร้างแบบโหวต"
                msgType == "event" -> "สร้างนัดหมาย"
                msgType == "rich_card" -> "ส่งการ์ดโต้ตอบ"
                else -> {
                    val trimmed = rawContent.trim()
                    if (trimmed.length > 120) "${trimmed.substring(0, 120)}…" else trimmed
                }
            }.ifEmpty { "มีข้อความใหม่" }

            val priority = msg.optString("priority", "normal")
            val prioritizedBody = if (priority == "urgent") "⚡ ด่วน: $preview" else preview
            val isGroup = room != null && room.type != "direct"
            val title = if (isGroup) room?.name?.ifEmpty { senderName } ?: senderName else senderName
            val finalBody = if (isGroup) "$senderName: $prioritizedBody" else prioritizedBody

            val soundEnabled = prefs.getBoolean("flutter.bcaichat_alert_sound", true)
            val chosenSound = when {
                !soundEnabled || priority == "silent" -> "none"
                priority == "urgent" ->
                    prefs.getString("flutter.bcaichat_alert_sound_urgent", "urgent") ?: "urgent"
                senderId == AI_USER_ID ->
                    prefs.getString("flutter.bcaichat_alert_sound_ai", "robot") ?: "robot"
                else ->
                    prefs.getString("flutter.bcaichat_alert_sound_normal", "ting") ?: "ting"
            }
            val soundCode = if (chosenSound in SOUND_CODES) chosenSound else "ting"

            val openIntent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("conversation_id", convId)
            }
            val reqCode = ((convId.hashCode() and 0x7fffffff) % 800000) + 10000
            val openPi = PendingIntent.getActivity(
                this,
                reqCode,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val notification = NotificationCompat.Builder(this, "$MSG_CHANNEL_PREFIX$soundCode")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(finalBody)
                .setStyle(NotificationCompat.BigTextStyle().bigText(finalBody))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_MESSAGE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setDefaults(NotificationCompat.DEFAULT_LIGHTS)
                .setContentIntent(openPi)
                .build()

            notificationManager.notify(reqCode, notification)

            if (!interactive) {
                try {
                    @Suppress("DEPRECATION")
                    val screenWl = powerManager.newWakeLock(
                        PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                            PowerManager.ACQUIRE_CAUSES_WAKEUP or
                            PowerManager.ON_AFTER_RELEASE,
                        "bcaichat:screen_wake",
                    )
                    screenWl.acquire(5_000L)
                } catch (_: Throwable) {
                }
            }
        } finally {
            try {
                if (cpuWakeLock?.isHeld == true) {
                    cpuWakeLock.release()
                }
            } catch (_: Throwable) {
            }
        }
    }
}
