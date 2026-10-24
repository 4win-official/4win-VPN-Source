package com.forwin.vpn

import android.content.Context
import gi.Seq
import java.util.Collections
import java.util.IdentityHashMap

/** Shared runtime initialization state for the :psiphon process only. */
internal object PsiphonNativeRuntime {
    private const val NATIVE_LIBRARY = "psiphon-gojni"
    @Volatile private var initializationFailure: Throwable? = null

    /** Loads the relocated gomobile runtime and returns its first initialization failure, if any. */
    fun initialize(context: Context): Throwable? {
        return try {
            Seq.setContext(context.applicationContext)
            System.loadLibrary(NATIVE_LIBRARY)
            initializationFailure
        } catch (error: Throwable) {
            synchronized(this) {
                if (initializationFailure == null) initializationFailure = error
                initializationFailure
            }
        }
    }

    /** Fails before Psiphon Java bindings use an unsuccessfully initialized runtime. */
    fun requireInitialized() {
        initializationFailure?.let { failure ->
            throw IllegalStateException(
                "Psiphon native runtime unavailable",
                failure,
            )
        }
    }

    /** Compact, useful cause chain for UI status and the native log buffer. */
    fun describe(error: Throwable): String {
        val seen = Collections.newSetFromMap(IdentityHashMap<Throwable, Boolean>())
        val parts = ArrayList<String>()
        var current: Throwable? = error
        while (current != null && parts.size < 6 && seen.add(current)) {
            val type = current.javaClass.simpleName.ifBlank { current.javaClass.name }
            val message = current.message?.trim()?.takeIf { it.isNotEmpty() }
            parts += if (message == null) type else "$type: $message"
            current = current.cause
        }
        return parts.joinToString(" <- ").take(600).ifBlank { "unknown native runtime error" }
    }
}
