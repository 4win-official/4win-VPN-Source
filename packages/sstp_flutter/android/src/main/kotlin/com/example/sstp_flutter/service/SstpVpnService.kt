package com.example.sstp_flutter.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.SystemClock
import android.service.quicksettings.TileService
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.documentfile.provider.DocumentFile
import androidx.preference.PreferenceManager
import com.example.sstp_flutter.FlutterCaller
import com.example.sstp_flutter.R
import com.example.sstp_flutter.TrafficRateSampler
import com.example.sstp_flutter.VpnConnectionObserver
import com.example.sstp_flutter.client.ClientBridge
import com.example.sstp_flutter.client.control.ControlClient
import com.example.sstp_flutter.client.control.LogWriter
import com.example.sstp_flutter.connectionStatus
import com.example.sstp_flutter.dnsCount
import com.example.sstp_flutter.dnsEnabled
import com.example.sstp_flutter.errorConnection
import com.example.sstp_flutter.notifyFlutter
import com.example.sstp_flutter.manuallyDisconnected
import com.example.sstp_flutter.preference.OscPrefKey
import com.example.sstp_flutter.preference.accessor.getBooleanPrefValue
import com.example.sstp_flutter.preference.accessor.getIntPrefValue
import com.example.sstp_flutter.preference.accessor.getURIPrefValue
import com.example.sstp_flutter.preference.accessor.resetReconnectionLife
import com.example.sstp_flutter.preference.accessor.setBooleanPrefValue
import com.example.sstp_flutter.preference.accessor.setIntPrefValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID


internal const val ACTION_VPN_CONNECT = "com.example.sstp_flutter.connect"
internal const val ACTION_VPN_DISCONNECT = "com.example.sstp_flutter.disconnect"
internal const val ACTION_VPN_RECONNECT = "com.example.sstp_flutter.reconnect"
private const val EXTRA_NOTIFICATION_SESSION =
    "com.example.sstp_flutter.notification_session"

internal const val NOTIFICATION_CHANNEL_NAME = "com.example.sstp_flutter.notification.channel"

internal const val NOTIFICATION_ERROR_ID = 1
internal const val NOTIFICATION_RECONNECT_ID = 2
internal const val NOTIFICATION_DISCONNECT_ID = 3

class SstpVpnService : VpnService() {
    private lateinit var prefs: SharedPreferences
    private lateinit var listener: SharedPreferences.OnSharedPreferenceChangeListener
    private lateinit var notificationManager: NotificationManagerCompat
    internal lateinit var scope: CoroutineScope

    internal var logWriter: LogWriter? = null
    private var controlClient: ControlClient?  = null

    private var jobReconnect: Job? = null
    private var notificationSessionToken: String? = null
    private var lastReconnectToken: String? = null
    private var notificationActionInProgress = false
    private var activeSessionPrefs: SessionPreferences? = null
    private var sessionGeneration = 0L
    private var observedHomeStatusPrefs: SharedPreferences? = null
    private var homeStatusListener: SharedPreferences.OnSharedPreferenceChangeListener? = null
    private var homeStatusListenerGeneration = 0L
    @Volatile private var trafficNotificationVisible = false
    private val trafficRateSampler = TrafficRateSampler()
    private val trafficLock = Any()
    private var trafficSamplerJob: Job? = null
    @Volatile private var activeTrafficOwner: Any? = null
    private var trafficUploadBytes = 0L
    private var trafficDownloadBytes = 0L
    private val nativeSessionLock = Any()
    private var nativeSessionId: String? = null
    private var nativeConnectedAtElapsedRealtime: Long? = null

    companion object {
        @Volatile private var liveInstance: SstpVpnService? = null
        @Volatile var isReconnecting: Boolean = false
            private set

        /** Read by the host app without confusing this standalone service with Mix. */
        fun state(context: android.content.Context): Map<String, Any> {
            val prefs = PreferenceManager.getDefaultSharedPreferences(context.applicationContext)
            val running = prefs.getBoolean(OscPrefKey.ROOT_STATE.name, false)
            val service = liveInstance
            return if (service != null) {
                service.snapshotState(running)
            } else {
                mapOf(
                    "running" to running,
                    "reconnecting" to (running && isReconnecting),
                    "connected" to running
                )
            }
        }
    }

    private fun setRootState(state: Boolean) {
        setBooleanPrefValue(state, OscPrefKey.ROOT_STATE, prefs)
    }

    private fun requestTileListening() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            TileService.requestListeningState(this,
                ComponentName(this, SstpTileService::class.java)
            )
        }
    }

    override fun onCreate() {
        super.onCreate()
        liveInstance = this
        notificationManager = NotificationManagerCompat.from(this)

        prefs = PreferenceManager.getDefaultSharedPreferences(this)

        listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == OscPrefKey.ROOT_STATE.name) {
                val newState = getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs)
                if(newState){
//                    FlutterCaller().connecting()
                }else{
                    resetTraffic()
                    VpnConnectionObserver.notifyState(this, false)
                    val tempMap : HashMap<String,Any>  = HashMap()
                    connectionStatus = OscPrefKey.Disconnected.name
                    tempMap.put("status",connectionStatus)
                    tempMap.put("dns", dnsEnabled)
                    tempMap.put("dnsCount", dnsCount)
                    tempMap.put("error", errorConnection)

                    notifyFlutter("connectResponse", tempMap)
                    errorConnection = false
                }
                println("listener onCreate sstp service $newState")
                setBooleanPrefValue(newState, OscPrefKey.HOME_CONNECTOR, prefs)
                requestTileListening()
            }
        }

        prefs.registerOnSharedPreferenceChangeListener(listener)

        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // A sticky recreation has no Intent. Recover only an active session;
        // an explicit disconnect clears ROOT_STATE before stopping the service.
        if (intent == null) {
            if (controlClient != null) return Service.START_STICKY
            if (!getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs)) {
                stopSelf()
                return Service.START_NOT_STICKY
            }
            return onStartCommand(Intent(this, SstpVpnService::class.java)
                .setAction(ACTION_VPN_CONNECT), flags, startId)
        }
        return when (intent.action) {
            ACTION_VPN_CONNECT -> {
                val token = intent.getStringExtra(EXTRA_NOTIFICATION_SESSION)
                if (token != null && token != notificationSessionToken) {
                    return Service.START_STICKY
                }
                manuallyDisconnected = false

                FlutterCaller().connecting()
                sessionGeneration++
                detachHomeStatusListener()
                controlClient?.kill(false, null)
                activeSessionPrefs = SessionPreferences(prefs.all.toMap())

                resetNativeSession()
                resetTraffic()
                beForegrounded()
                resetReconnectionLife(activeSessionPrefs ?: prefs)
                if (getBooleanPrefValue(OscPrefKey.LOG_DO_SAVE_LOG, activeSessionPrefs ?: prefs)) {
                    prepareLogWriter()
                }

                logWriter?.write("Establish VPN connection")

                initializeClient(activeSessionPrefs ?: return Service.START_STICKY)

                setRootState(true)

                Service.START_STICKY
            }

            ACTION_VPN_RECONNECT -> {
                // Only the displayed notification may restart this session.
                val token = intent.getStringExtra(EXTRA_NOTIFICATION_SESSION)
                if (token != notificationSessionToken || !getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs) ||
                    token == lastReconnectToken || notificationActionInProgress) return Service.START_STICKY
                lastReconnectToken = token
                notificationActionInProgress = true
                isReconnecting = true
                val generation = sessionGeneration
                scope.launch {
                    jobReconnect?.cancelAndJoin()
                    controlClient?.shutdownForReconnect()
                    if (generation != sessionGeneration || !getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs)) return@launch
                    controlClient = null
                    resetNativeSession()
                    resetTraffic()
                    beForegrounded()
                    initializeClient(activeSessionPrefs ?: return@launch)
                    setRootState(true)
                    notificationActionInProgress = false
                    isReconnecting = false
                }
                Service.START_STICKY
            }

            else -> {
                val token = intent.getStringExtra(EXTRA_NOTIFICATION_SESSION)
                if (token != null && token != notificationSessionToken) {
                    return Service.START_STICKY
                }
                if(intent?.getBooleanExtra("manuallyDisconnected",false) == true){
                    manuallyDisconnected = true
                }
                // Only accepted notification tokens reach this branch when a
                // token is supplied; stale actions returned above.  Broadcast
                // before teardown so Flutter can invalidate its live session.
                sendBroadcast(Intent("com.forwin.vpn.VPN_DISCONNECTED")
                    .setPackage(packageName)
                    .putExtra("protocol", "sstp"))
                sessionGeneration++
                isReconnecting = false
                notificationActionInProgress = false
                jobReconnect?.cancel()
                setRootState(false)
                connectionStatus = OscPrefKey.Disconnected.name
                controlClient?.disconnect()
                controlClient = null

                close()

                val tempMap : HashMap<String,Any>  = HashMap()
                connectionStatus = OscPrefKey.Disconnected.name
                tempMap.put("status",connectionStatus)
                tempMap.put("dns", dnsEnabled)
                tempMap.put("dnsCount", dnsCount)
                tempMap.put("error", errorConnection)

                notifyFlutter("connectResponse", tempMap)
                errorConnection = false

                Service.START_NOT_STICKY
            }
        }
    }

    private fun initializeClient(sessionPrefs: SharedPreferences = activeSessionPrefs ?: SessionPreferences(prefs.all.toMap())) {
        beginNativeSession()
        detachHomeStatusListener()
        activeSessionPrefs = sessionPrefs as? SessionPreferences ?: activeSessionPrefs
        val observedPrefs = sessionPrefs
        val generation = sessionGeneration
        val listenerGeneration = homeStatusListenerGeneration + 1
        homeStatusListenerGeneration = listenerGeneration
        val registeredHomeStatusListener = SharedPreferences.OnSharedPreferenceChangeListener { source, key ->
            if (key == OscPrefKey.HOME_STATUS.name &&
                source === observedPrefs &&
                observedHomeStatusPrefs === observedPrefs &&
                homeStatusListenerGeneration == listenerGeneration &&
                sessionGeneration == generation &&
                activeSessionPrefs === observedPrefs
            ) {
                val connected = observedPrefs.getString(OscPrefKey.HOME_STATUS.name, "")?.isNotEmpty() == true
                if (connected) markNativeConnected()
                VpnConnectionObserver.notifyState(this, connected)
            }
        }
        homeStatusListener = registeredHomeStatusListener
        observedHomeStatusPrefs = observedPrefs
        observedPrefs.registerOnSharedPreferenceChangeListener(registeredHomeStatusListener)
        VpnConnectionObserver.notifyStarting(this)
        val bridge = ClientBridge(this, sessionPrefs = sessionPrefs)
        synchronized(trafficLock) {
            activeTrafficOwner = bridge
        }
        controlClient = ControlClient(bridge).also {
            it.launchJobMain()
        }
    }

    private fun beginNativeSession() {
        synchronized(nativeSessionLock) {
            nativeSessionId = UUID.randomUUID().toString()
            nativeConnectedAtElapsedRealtime = null
        }
    }

    private fun resetNativeSession() {
        synchronized(nativeSessionLock) {
            nativeSessionId = null
            nativeConnectedAtElapsedRealtime = null
        }
    }

    private fun markNativeConnected() {
        synchronized(nativeSessionLock) {
            if (nativeSessionId != null && nativeConnectedAtElapsedRealtime == null) {
                nativeConnectedAtElapsedRealtime = SystemClock.elapsedRealtime()
            }
        }
    }

    private fun snapshotState(running: Boolean): Map<String, Any> {
        val state = linkedMapOf<String, Any>(
            "running" to running,
            "reconnecting" to (running && isReconnecting),
            "connected" to running
        )
        synchronized(nativeSessionLock) {
            nativeSessionId?.let { id ->
                state["sessionId"] = id
                nativeConnectedAtElapsedRealtime?.let { started ->
                    state["elapsedMillis"] = (SystemClock.elapsedRealtime() - started).coerceAtLeast(0L)
                    synchronized(trafficLock) {
                        state["uplink"] = trafficUploadBytes
                        state["downlink"] = trafficDownloadBytes
                    }
                }
            }
        }
        return state
    }

    private fun detachHomeStatusListener() {
        homeStatusListenerGeneration++
        val observedPrefs = observedHomeStatusPrefs
        val listener = homeStatusListener
        if (observedPrefs != null && listener != null) {
            observedPrefs.unregisterOnSharedPreferenceChangeListener(listener)
        }
        observedHomeStatusPrefs = null
        homeStatusListener = null
    }

    private fun prepareLogWriter() {
        val currentDateTime = SimpleDateFormat("yyyyMMddHHmmss", Locale.getDefault()).format(Date())
        val filename = "log_osc_${currentDateTime}.txt"

        val prefURI = getURIPrefValue(OscPrefKey.LOG_DIR, prefs)
        if (prefURI == null) {
            makeNotification(NOTIFICATION_ERROR_ID, "LOG: ERR_NULL_PREFERENCE")
            return
        }

        val dirURI = DocumentFile.fromTreeUri(this, prefURI)
        if (dirURI == null) {
            makeNotification(NOTIFICATION_ERROR_ID, "LOG: ERR_NULL_DIRECTORY")
            return
        }

        val fileURI = dirURI.createFile("text/plain", filename)
        if (fileURI == null) {
            makeNotification(NOTIFICATION_ERROR_ID, "LOG: ERR_NULL_FILE")
            return
        }

        val stream = contentResolver.openOutputStream(fileURI.uri, "wa")
        if (stream == null) {
            makeNotification(NOTIFICATION_ERROR_ID, "LOG: ERR_NULL_STREAM")
            return
        }

        logWriter = LogWriter(stream)
    }

    internal fun launchJobReconnect() {
        VpnConnectionObserver.notifyState(this, false)
        resetTraffic()
        val generation = sessionGeneration
        jobReconnect = scope.launch {
            try {
                    val sessionPrefs = activeSessionPrefs ?: return@launch
                    getIntPrefValue(OscPrefKey.RECONNECTION_LIFE, sessionPrefs).also {
                        val life = it - 1
                        setIntPrefValue(life, OscPrefKey.RECONNECTION_LIFE, sessionPrefs)

                    val message = "Reconnection will be tried (LIFE = $life)"
                    makeNotification(NOTIFICATION_RECONNECT_ID, message)
                    logWriter?.report(message)
                }

                delay(getIntPrefValue(OscPrefKey.RECONNECTION_INTERVAL, sessionPrefs) * 1000L)

                if (generation == sessionGeneration && getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs)) {
                    initializeClient(sessionPrefs)
                }
            } catch (_: CancellationException) { }
            finally {
                isReconnecting = false
                cancelNotification(NOTIFICATION_RECONNECT_ID)
            }
        }
    }

    private fun buildNotification(throughput: String? = null): android.app.Notification {
        val sessionToken = notificationSessionToken ?: UUID.randomUUID().toString().also { notificationSessionToken = it }
        val disconnectIntent = Intent(this, SstpVpnService::class.java).setAction(ACTION_VPN_DISCONNECT)
            .setData(android.net.Uri.parse("sstp://disconnect/$sessionToken"))
            .putExtra(EXTRA_NOTIFICATION_SESSION, sessionToken).putExtra("manuallyDisconnected", true)
        val reconnectIntent = Intent(this, SstpVpnService::class.java).setAction(ACTION_VPN_RECONNECT)
            .setData(android.net.Uri.parse("sstp://reconnect/$sessionToken"))
            .putExtra(EXTRA_NOTIFICATION_SESSION, sessionToken)
        val showNotification = prefs.getBoolean(OscPrefKey.NOTIFICATION_DO_SHOW_DISCONNECT.name, false)
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_NAME).also { builder ->
            builder.priority = NotificationCompat.PRIORITY_DEFAULT
            builder.setOngoing(true).setAutoCancel(false).setOnlyAlertOnce(true).setSmallIcon(R.drawable.baseline_vpn_key_24)
            builder.setContentTitle(prefs.getString(OscPrefKey.NotificationText.name, "") ?: "")
            builder.setContentText(throughput ?: "")
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(throughput ?: ""))
            if (showNotification) {
                builder.addAction(0, "Reconnect", PendingIntent.getService(this, 302, reconnectIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                builder.addAction(0, "Disconnect", PendingIntent.getService(this, 301, disconnectIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            }
        }.build()
    }

    private fun beForegrounded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notificationManager.createNotificationChannel(NotificationChannel(NOTIFICATION_CHANNEL_NAME, NOTIFICATION_CHANNEL_NAME, NotificationManager.IMPORTANCE_DEFAULT))
        }
        notificationSessionToken = UUID.randomUUID().toString()
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) startForeground(NOTIFICATION_DISCONNECT_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NOTIFICATION_DISCONNECT_ID, notification)
        trafficNotificationVisible = true
    }

    internal fun recordTraffic(owner: Any, uploadBytes: Long, downloadBytes: Long) {
        synchronized(trafficLock) {
            if (owner !== activeTrafficOwner) return
            // Parallel TUN readers/writers may report snapshots out of order.
            trafficUploadBytes = maxOf(trafficUploadBytes, uploadBytes)
            trafficDownloadBytes = maxOf(trafficDownloadBytes, downloadBytes)
        }
    }

    private fun resetTraffic() {
        trafficSamplerJob?.cancel()
        trafficSamplerJob = null
        synchronized(trafficLock) {
            activeTrafficOwner = null
            trafficUploadBytes = 0L
            trafficDownloadBytes = 0L
            trafficRateSampler.reset()
        }
    }

    internal fun startTrafficSampling() {
        trafficSamplerJob?.cancel()
        val owner = synchronized(trafficLock) {
            trafficRateSampler.reset()
            trafficRateSampler.sample(trafficUploadBytes, trafficDownloadBytes, SystemClock.elapsedRealtime())
            activeTrafficOwner
        } ?: return
        trafficSamplerJob = scope.launch {
            while (connectionStatus == OscPrefKey.Connected.name &&
                getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs)) {
                delay(1000L)
                // Reset and publication share a lock: a cancelled session can
                // never publish a late notification after stopForeground().
                synchronized(trafficLock) {
                    if (owner === activeTrafficOwner && connectionStatus == OscPrefKey.Connected.name &&
                        getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs)) {
                        val text = trafficRateSampler.sample(
                            trafficUploadBytes, trafficDownloadBytes, SystemClock.elapsedRealtime()
                        )
                        if (text != null) notificationManager.notify(
                            NOTIFICATION_DISCONNECT_ID, buildNotification(text))
                    }
                }
            }
        }
    }

    internal fun makeNotification(id: Int, message: String) {
        println("err msg : $message")
        errorConnection = true
        VpnConnectionObserver.notifyState(this, false)

    }

    internal fun cancelNotification(id: Int) {
        notificationManager.cancel(id)
    }

    internal fun onReconnectFinished() {
        isReconnecting = false
        notificationActionInProgress = false
        if (connectionStatus == OscPrefKey.Connected.name) startTrafficSampling()
    }

    internal fun closeIfCurrent(owner: ControlClient) {
        if (controlClient === owner) close()
    }

    internal fun close() {
        resetNativeSession()
        resetTraffic()
        trafficNotificationVisible = false
        detachHomeStatusListener()
        VpnConnectionObserver.notifyState(this, false)
        setRootState(false)
        connectionStatus = OscPrefKey.Disconnected.name
        stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        resetNativeSession()
        resetTraffic()
        trafficNotificationVisible = false
        detachHomeStatusListener()
        VpnConnectionObserver.notifyState(this, false)
        logWriter?.write("Terminate VPN connection")
        logWriter?.close()
        logWriter = null

        controlClient?.kill(false, null)
        controlClient = null

        scope.cancel()

        if (liveInstance === this) liveInstance = null
        setRootState(false)
        prefs.unregisterOnSharedPreferenceChangeListener(listener)
        super.onDestroy()
    }
}
