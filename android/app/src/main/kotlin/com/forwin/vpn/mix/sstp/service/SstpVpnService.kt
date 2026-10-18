package com.forwin.vpn.mix.sstp.service

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.ParcelFileDescriptor
import com.forwin.vpn.mix.MixPacketStack
import com.forwin.vpn.mix.sstp.client.control.LogWriter
import com.forwin.vpn.mix.sstp.preference.DEFAULT_BOOLEAN_MAP
import com.forwin.vpn.mix.sstp.preference.DEFAULT_INT_MAP
import com.forwin.vpn.mix.sstp.preference.DEFAULT_SET_MAP
import com.forwin.vpn.mix.sstp.preference.DEFAULT_STRING_MAP
import com.forwin.vpn.mix.sstp.preference.OscPrefKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import java.net.InetAddress
import java.util.concurrent.CopyOnWriteArraySet

internal const val NOTIFICATION_ERROR_ID = 1
internal const val NOTIFICATION_RECONNECT_ID = 2

/** Original engine facade; intentionally does not extend VpnService or create a system TUN. */
internal class SstpVpnService(base: Context, host: String, user: String, pass: String, port: Int, private val mtu: Int, private val listenPort: Int, private val failure: (String) -> Unit) : ContextWrapper(base) {
    internal val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    internal var logWriter: LogWriter? = null
    internal var packetStack: MixPacketStack? = null
    internal var packetPeer: ParcelFileDescriptor? = null
    // Session credentials and state must never be written to Android preferences.
    internal val prefs: SharedPreferences = SessionPreferences().also { p ->
        p.edit().apply {
            // Defaults first; explicit connection values below must win.
            DEFAULT_BOOLEAN_MAP.forEach { (k, v) -> putBoolean(k.name, v) }
            DEFAULT_INT_MAP.forEach { (k, v) -> putString(k.name, v.toString()) }
            DEFAULT_STRING_MAP.forEach { (k, v) -> putString(k.name, v) }
            DEFAULT_SET_MAP.forEach { (k, v) -> putStringSet(k.name, v) }
            putString(OscPrefKey.HOME_HOSTNAME.name, host)
            putString(OscPrefKey.HOME_USERNAME.name, user)
            putString(OscPrefKey.HOME_PASSWORD.name, pass)
            putString(OscPrefKey.SSL_PORT.name, port.toString())
            putString(OscPrefKey.PPP_MTU.name, mtu.toString())
            putString(OscPrefKey.PPP_MRU.name, mtu.toString())
            putBoolean(OscPrefKey.PPP_MSCHAPv2_ENABLED.name, true)
            putBoolean(OscPrefKey.PPP_PAP_ENABLED.name, true)
            putBoolean(OscPrefKey.PPP_IPv4_ENABLED.name, true)
            putBoolean(OscPrefKey.PPP_IPv6_ENABLED.name, false)
            putBoolean(OscPrefKey.SSL_DO_VERIFY_CERT.name, true)
            putBoolean(OscPrefKey.SSL_DO_VERIFY.name, true)
            putBoolean(OscPrefKey.ROUTE_DO_ADD_DEFAULT_ROUTE.name, false)
            apply()
        }
    }
    internal inner class Builder {
        private val addresses = mutableListOf<Pair<InetAddress, Int>>(); private var requestedMtu = mtu
        internal fun addAddress(a: InetAddress, p: Int) { addresses += a to p }
        internal fun addDnsServer(a: InetAddress) = Unit
        internal fun addDnsServer(a: String) { if (a.isNotBlank()) InetAddress.getByName(a) }
        internal fun addRoute(a: String, p: Int) = Unit
        internal fun addAllowedApplication(p: String) = Unit
        internal fun setMtu(v: Int) { requestedMtu = v }
        internal fun setBlocking(v: Boolean) = Unit
        internal fun establish(): ParcelFileDescriptor {
            val ip = addresses.firstOrNull { it.first.address.size == 4 }?.first?.hostAddress ?: throw IllegalStateException("SSTP IPCP did not negotiate IPv4")
            val pair = MixPacketStack.createPacketPair()
            try {
                packetStack = MixPacketStack.start(pair.first, ip, "", requestedMtu.coerceIn(576, 65535), listenPort)
                packetPeer = pair.second
                return pair.second
            } catch (failure: Throwable) {
                pair.second.close()
                throw failure
            } finally { pair.first.close() }
        }
    }
    internal fun protect(socket: java.net.Socket) = true
    internal fun makeNotification(id: Int, message: String) { failure(message) }
    internal fun launchJobReconnect() { failure("SSTP reconnect requested") }
    internal fun close() {
        val peer = packetPeer
        val stack = packetStack
        packetPeer = null
        packetStack = null
        runCatching { peer?.close() }
        runCatching { stack?.close() }
        scope.cancel()
    }
}

/** Minimal in-memory SharedPreferences implementation for the vendored engine. */
private class SessionPreferences : SharedPreferences {
    private val values = LinkedHashMap<String, Any?>()
    private val listeners = CopyOnWriteArraySet<SharedPreferences.OnSharedPreferenceChangeListener>()
    @Synchronized override fun getAll(): Map<String, *> = HashMap(values)
    @Synchronized override fun getString(key: String, defValue: String?): String? = values[key] as? String ?: defValue
    @Synchronized override fun getStringSet(key: String, defValues: Set<String>?): Set<String>? = (values[key] as? Set<*>)?.filterIsInstance<String>()?.toSet() ?: defValues
    @Synchronized override fun getInt(key: String, defValue: Int): Int = (values[key] as? Number)?.toInt() ?: (values[key] as? String)?.toIntOrNull() ?: defValue
    @Synchronized override fun getLong(key: String, defValue: Long): Long = (values[key] as? Number)?.toLong() ?: (values[key] as? String)?.toLongOrNull() ?: defValue
    @Synchronized override fun getFloat(key: String, defValue: Float): Float = (values[key] as? Number)?.toFloat() ?: (values[key] as? String)?.toFloatOrNull() ?: defValue
    @Synchronized override fun getBoolean(key: String, defValue: Boolean): Boolean = values[key] as? Boolean ?: defValue
    @Synchronized override fun contains(key: String): Boolean = values.containsKey(key)
    override fun edit(): SharedPreferences.Editor = Editor()
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) { listeners += listener }
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) { listeners -= listener }
    private inner class Editor : SharedPreferences.Editor {
        private val updates = LinkedHashMap<String, Any?>(); private val removals = mutableSetOf<String>(); private var clearAll = false
        override fun putString(key: String, value: String?) = apply { updates[key] = value }
        override fun putStringSet(key: String, value: Set<String>?) = apply { updates[key] = value?.toSet() }
        override fun putInt(key: String, value: Int) = apply { updates[key] = value }
        override fun putLong(key: String, value: Long) = apply { updates[key] = value }
        override fun putFloat(key: String, value: Float) = apply { updates[key] = value }
        override fun putBoolean(key: String, value: Boolean) = apply { updates[key] = value }
        override fun remove(key: String) = apply { removals += key }
        override fun clear() = apply { clearAll = true; removals.clear(); updates.clear() }
        override fun commit(): Boolean { applyChanges(); return true }
        override fun apply() = applyChanges()
        private fun applyChanges() {
            val changed = LinkedHashSet<String>()
            synchronized(this@SessionPreferences) {
                if (clearAll) { changed += values.keys; values.clear() }
                removals.forEach { if (values.remove(it) != null) changed += it }
                updates.forEach { (key, value) -> if (!values.containsKey(key) || values[key] != value) { values[key] = value; changed += key } }
            }
            changed.forEach { key -> listeners.forEach { it.onSharedPreferenceChanged(this@SessionPreferences, key) } }
        }
    }
}
