package com.example.sstp_flutter

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Looper
import androidx.preference.PreferenceManager
import com.example.sstp_flutter.client.control.ControlClient
import com.example.sstp_flutter.preference.OscPrefKey
import com.example.sstp_flutter.service.ACTION_VPN_DISCONNECT
import com.example.sstp_flutter.service.SstpVpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
@LooperMode(LooperMode.Mode.PAUSED)
class SstpFlutterPluginTest {
    private lateinit var plugin: SstpFlutterPlugin
    private lateinit var engine: FlutterPlugin.FlutterPluginBinding
    private lateinit var messenger: BinaryMessenger
    private val context: Context get() = RuntimeEnvironment.getApplication()

    @Before fun attachEngine() {
        PreferenceManager.getDefaultSharedPreferences(context).edit().clear().commit()
        plugin = SstpFlutterPlugin()
        messenger = mock(BinaryMessenger::class.java)
        engine = mock(FlutterPlugin.FlutterPluginBinding::class.java)
        `when`(engine.applicationContext).thenReturn(context)
        `when`(engine.binaryMessenger).thenReturn(messenger)
        plugin.onAttachedToEngine(engine)
        connectionStatus = OscPrefKey.Connected.name
        manuallyDisconnected = false
    }

    @After fun clearChannel() { flutterChannel = null }

    @Test fun recentsDetachReleasesListenersWithoutDisconnecting() {
        val activity = mock(ActivityPluginBinding::class.java)
        val listener = mock(PluginRegistry.ActivityResultListener::class.java)
        plugin.onAttachedToActivity(activity)
        plugin.activityResultListener = listener
        plugin.onDetachedFromActivity()
        verify(activity).removeActivityResultListener(listener)
        assertNull(plugin.activityResultListener)
        assertEquals(OscPrefKey.Connected.name, connectionStatus)
        assertFalse(manuallyDisconnected)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
        plugin.onDetachedFromActivity() // idempotent
    }

    @Test fun configurationChangeCanReattachAndDetachAgain() {
        plugin.onAttachedToActivity(mock(ActivityPluginBinding::class.java))
        plugin.onDetachedFromActivityForConfigChanges()
        val replacement = mock(ActivityPluginBinding::class.java)
        plugin.onReattachedToActivityForConfigChanges(replacement)
        val listener = mock(PluginRegistry.ActivityResultListener::class.java)
        plugin.activityResultListener = listener
        plugin.onDetachedFromActivity()
        verify(replacement).removeActivityResultListener(listener)
        assertEquals(OscPrefKey.Connected.name, connectionStatus)
    }

    @Test fun engineDetachDropsQueuedEventsAndLeavesTunnelStateAlone() {
        notifyFlutter("connectResponse", mapOf("status" to "Connected"))
        plugin.onDetachedFromEngine(engine)
        clearInvocations(messenger)
        shadowOf(Looper.getMainLooper()).idle()
        verifyNoInteractions(messenger)
        assertNull(flutterChannel)
        assertEquals(OscPrefKey.Connected.name, connectionStatus)
        assertNull(shadowOf(RuntimeEnvironment.getApplication()).nextStartedService)
    }

    @Test fun backgroundCallbacksAreSafeWithoutAnyEngine() {
        plugin.onDetachedFromEngine(engine)
        FlutterCaller().connecting()
        FlutterCaller().connect()
        notifyFlutter("downloadSpeed", listOf(1, 2))
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(OscPrefKey.Connected.name, connectionStatus)
    }

    @Test fun callbacksResumeOnNewEngine() {
        plugin.onDetachedFromEngine(engine)
        plugin.onAttachedToEngine(engine)
        val channel = mock(MethodChannel::class.java)
        flutterChannel = channel
        FlutterCaller().connecting()
        shadowOf(Looper.getMainLooper()).idle()
        verify(channel).invokeMethod("connectResponse", hashMapOf("status" to "Connecting"))
    }

    @Test fun explicitDisconnectIsNotStickyAndCannotRestart() {
        val controller = Robolectric.buildService(SstpVpnService::class.java).create()
        val service = controller.get()
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        prefs.edit().putBoolean(OscPrefKey.ROOT_STATE.name, true).commit()
        val intent = Intent(context, SstpVpnService::class.java)
            .setAction(ACTION_VPN_DISCONNECT).putExtra("manuallyDisconnected", true)
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(intent, 0, 1))
        assertTrue(manuallyDisconnected)
        assertFalse(prefs.getBoolean(OscPrefKey.ROOT_STATE.name, true))
        assertEquals(Service.START_NOT_STICKY, service.onStartCommand(null, 0, 2))
        assertTrue(shadowOf(service).isStoppedBySelf)
        controller.destroy()
    }

    @Test fun stickyCallbackDoesNotReplaceAnExistingTunnel() {
        val controller = Robolectric.buildService(SstpVpnService::class.java).create()
        val service = controller.get()
        val core = mock(ControlClient::class.java)
        SstpVpnService::class.java.getDeclaredField("controlClient").apply {
            isAccessible = true
            set(service, core)
        }
        assertEquals(Service.START_STICKY, service.onStartCommand(null, 0, 2))
        verifyNoInteractions(core)
        controller.destroy()
    }

    @Test fun taskRemovalDoesNotStopOrKillAnExistingTunnel() {
        val controller = Robolectric.buildService(SstpVpnService::class.java).create()
        val service = controller.get()
        val core = mock(ControlClient::class.java)
        SstpVpnService::class.java.getDeclaredField("controlClient").apply {
            isAccessible = true
            set(service, core)
        }
        service.onTaskRemoved(Intent())
        verifyNoInteractions(core)
        assertFalse(shadowOf(service).isStoppedBySelf)
        controller.destroy()
    }

    @Test fun foregroundNotificationIsOngoingAndUsesVpnServiceType() {
        val controller = Robolectric.buildService(SstpVpnService::class.java).create()
        val service = controller.get()
        SstpVpnService::class.java.getDeclaredMethod("beForegrounded").apply {
            isAccessible = true
            invoke(service)
        }
        val notification = shadowOf(service).lastForegroundNotification
        assertNotNull(notification)
        assertTrue(notification.flags and android.app.Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals(android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            service.foregroundServiceType)
        controller.destroy()
    }
}
