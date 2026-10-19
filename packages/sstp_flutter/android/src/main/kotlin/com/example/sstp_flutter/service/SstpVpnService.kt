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
import android.service.quicksettings.TileService
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.documentfile.provider.DocumentFile
import androidx.preference.PreferenceManager
import com.example.sstp_flutter.FlutterCaller
import com.example.sstp_flutter.R
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

    companion object {
        @Volatile var isReconnecting: Boolean = false
            private set

        /** Read by the host app without confusing this standalone service with Mix. */
        fun state(context: android.content.Context): Map<String, Any> {
            val prefs = PreferenceManager.getDefaultSharedPreferences(context.applicationContext)
            val running = prefs.getBoolean(OscPrefKey.ROOT_STATE.name, false)
            return mapOf(
                "running" to running,
                "reconnecting" to (running && isReconnecting),
                "connected" to running
            )
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
        notificationManager = NotificationManagerCompat.from(this)

        prefs = PreferenceManager.getDefaultSharedPreferences(this)

        listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == OscPrefKey.ROOT_STATE.name) {
                val newState = getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs)
                if(newState){
//                    FlutterCaller().connecting()
                }else{
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
                controlClient?.kill(false, null)
                activeSessionPrefs = SessionPreferences(prefs.all.toMap())

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
        activeSessionPrefs = sessionPrefs as? SessionPreferences ?: activeSessionPrefs
        controlClient = ControlClient(ClientBridge(this, sessionPrefs = sessionPrefs)).also {
            it.launchJobMain()
        }
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

    private fun beForegrounded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel(
                NOTIFICATION_CHANNEL_NAME,
                NOTIFICATION_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            ).also {
                notificationManager.createNotificationChannel(it)
            }
        }

        notificationSessionToken = UUID.randomUUID().toString()
        val sessionToken = notificationSessionToken
        val disconnectIntent = Intent(this, SstpVpnService::class.java)
            .setAction(ACTION_VPN_DISCONNECT)
            .setData(android.net.Uri.parse("sstp://disconnect/$sessionToken"))
            .putExtra(EXTRA_NOTIFICATION_SESSION, sessionToken)
            .putExtra("manuallyDisconnected", true)
        val reconnectIntent = Intent(this, SstpVpnService::class.java)
            .setAction(ACTION_VPN_RECONNECT)
            .setData(android.net.Uri.parse("sstp://reconnect/$sessionToken"))
            .putExtra(EXTRA_NOTIFICATION_SESSION, sessionToken)
        val pendingIntent = PendingIntent.getService(
            this,
            301,
            disconnectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val reconnectPendingIntent = PendingIntent.getService(
            this,
            302,
            reconnectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notificationText = prefs.getString(OscPrefKey.NotificationText.name,"")
        val showNotification = prefs.getBoolean(OscPrefKey.NOTIFICATION_DO_SHOW_DISCONNECT.name,false)
        println("notificationText : $notificationText")
        println("showNotification : $showNotification")



        val builder = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_NAME).also {
            it.priority = NotificationCompat.PRIORITY_DEFAULT
            it.setOngoing(true)
            it.setAutoCancel(false)
            it.setSmallIcon(R.drawable.baseline_vpn_key_24)
            it.setContentTitle(notificationText)
            if(showNotification){
                it.addAction(0, "Reconnect", reconnectPendingIntent)
                it.addAction(0, "Disconnect", pendingIntent)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_DISCONNECT_ID, builder.build(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_DISCONNECT_ID, builder.build())
        }
    }

    internal fun makeNotification(id: Int, message: String) {
        println("err msg : $message")
        errorConnection = true

    }

    internal fun cancelNotification(id: Int) {
        notificationManager.cancel(id)
    }

    internal fun onReconnectFinished() {
        isReconnecting = false
        notificationActionInProgress = false
    }

    internal fun closeIfCurrent(owner: ControlClient) {
        if (controlClient === owner) close()
    }

    internal fun close() {
        setRootState(false)
        connectionStatus = OscPrefKey.Disconnected.name
        stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        logWriter?.write("Terminate VPN connection")
        logWriter?.close()
        logWriter = null

        controlClient?.kill(false, null)
        controlClient = null

        scope.cancel()

        setRootState(false)
        prefs.unregisterOnSharedPreferenceChangeListener(listener)
        super.onDestroy()
    }
}
