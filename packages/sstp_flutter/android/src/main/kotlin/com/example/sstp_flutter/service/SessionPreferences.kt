package com.example.sstp_flutter.service

import android.content.SharedPreferences
import java.util.concurrent.CopyOnWriteArraySet

/** In-memory preferences owned by one VPN session; never consults global preferences. */
internal class SessionPreferences(initial: Map<String, *> = emptyMap<String, Any?>()) : SharedPreferences {
    private val values: MutableMap<String, Any?> = LinkedHashMap<String, Any?>().also { target ->
        initial.forEach { entry -> target[entry.key] = entry.value }
    }
    private val listeners = CopyOnWriteArraySet<SharedPreferences.OnSharedPreferenceChangeListener>()
    @Synchronized override fun getAll(): Map<String, *> = HashMap(values)
    @Synchronized override fun getString(key: String, defValue: String?) = values[key] as? String ?: defValue
    @Synchronized override fun getStringSet(key: String, defValues: Set<String>?) = (values[key] as? Set<*>)?.filterIsInstance<String>()?.toSet() ?: defValues
    @Synchronized override fun getInt(key: String, defValue: Int) = (values[key] as? Number)?.toInt() ?: (values[key] as? String)?.toIntOrNull() ?: defValue
    @Synchronized override fun getLong(key: String, defValue: Long) = (values[key] as? Number)?.toLong() ?: (values[key] as? String)?.toLongOrNull() ?: defValue
    @Synchronized override fun getFloat(key: String, defValue: Float) = (values[key] as? Number)?.toFloat() ?: (values[key] as? String)?.toFloatOrNull() ?: defValue
    @Synchronized override fun getBoolean(key: String, defValue: Boolean) = values[key] as? Boolean ?: defValue
    @Synchronized override fun contains(key: String) = values.containsKey(key)
    override fun edit(): SharedPreferences.Editor = Editor()
    override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) { listeners += listener }
    override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener) { listeners -= listener }
    private inner class Editor : SharedPreferences.Editor {
        private val updates = LinkedHashMap<String, Any?>(); private val removals = mutableSetOf<String>(); private var clearAll = false
        override fun putString(k: String, v: String?) = apply { updates[k] = v }
        override fun putStringSet(k: String, v: Set<String>?) = apply { updates[k] = v?.toSet() }
        override fun putInt(k: String, v: Int) = apply { updates[k] = v }
        override fun putLong(k: String, v: Long) = apply { updates[k] = v }
        override fun putFloat(k: String, v: Float) = apply { updates[k] = v }
        override fun putBoolean(k: String, v: Boolean) = apply { updates[k] = v }
        override fun remove(k: String) = apply { removals += k }
        override fun clear() = apply { clearAll = true; removals.clear(); updates.clear() }
        override fun commit(): Boolean { applyChanges(); return true }
        override fun apply() = applyChanges()
        private fun applyChanges() {
            val changed = LinkedHashSet<String>()
            synchronized(this@SessionPreferences) {
                if (clearAll) { changed += values.keys; values.clear() }
                removals.forEach { if (values.remove(it) != null) changed += it }
                updates.forEach { (k, v) -> if (!values.containsKey(k) || values[k] != v) { values[k] = v; changed += k } }
            }
            changed.forEach { k -> listeners.forEach { it.onSharedPreferenceChanged(this@SessionPreferences, k) } }
        }
    }
}
