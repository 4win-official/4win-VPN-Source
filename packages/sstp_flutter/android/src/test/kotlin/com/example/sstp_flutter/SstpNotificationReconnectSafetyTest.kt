package com.example.sstp_flutter

import android.content.Intent
import androidx.preference.PreferenceManager
import com.example.sstp_flutter.preference.OscPrefKey
import com.example.sstp_flutter.preference.accessor.setBooleanPrefValue
import com.example.sstp_flutter.service.SstpVpnService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RuntimeEnvironment
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SstpNotificationReconnectSafetyTest {
    @Test
    fun notificationHasEnglishReconnectAndDisconnectActions() {
        val context = RuntimeEnvironment.getApplication()
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        prefs.edit().putBoolean(OscPrefKey.NOTIFICATION_DO_SHOW_DISCONNECT.name, true).commit()
        val controller = Robolectric.buildService(SstpVpnService::class.java).create()
        val service = controller.get()
        SstpVpnService::class.java.getDeclaredMethod("beForegrounded").apply {
            isAccessible = true
            invoke(service)
        }
        val notification = shadowOf(service).lastForegroundNotification
        assertEquals(listOf("Reconnect", "Disconnect"), notification.actions.map { it.title.toString() })
        controller.destroy()
    }

    @Test
    fun staleReconnectIntentDoesNotStartAnotherClient() {
        val context = RuntimeEnvironment.getApplication()
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        setBooleanPrefValue(true, OscPrefKey.ROOT_STATE, prefs)
        val controller = Robolectric.buildService(SstpVpnService::class.java).create()
        val service = controller.get()
        SstpVpnService::class.java.getDeclaredMethod("beForegrounded").apply {
            isAccessible = true
            invoke(service)
        }
        val tokenField = SstpVpnService::class.java.getDeclaredField("notificationSessionToken").apply {
            isAccessible = true
        }
        val staleToken = tokenField.get(service) as String
        SstpVpnService::class.java.getDeclaredMethod("beForegrounded").apply {
            isAccessible = true
            invoke(service)
        }
        service.onStartCommand(
            Intent(context, SstpVpnService::class.java)
                .setAction("com.example.sstp_flutter.reconnect")
                .putExtra("com.example.sstp_flutter.notification_session", staleToken),
            0,
            2,
        )
        val controlClient = SstpVpnService::class.java.getDeclaredField("controlClient").apply {
            isAccessible = true
        }.get(service)
        assertNull(controlClient)
        controller.destroy()
    }
}
