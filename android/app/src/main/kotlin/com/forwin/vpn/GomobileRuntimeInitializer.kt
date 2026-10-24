package com.forwin.vpn

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.util.Log

/**
 * Initializes the RELOCATED Psiphon gomobile runtime before any Psiphon Java
 * binding is created.
 *
 * IMPORTANT: this provider runs ONLY in the `:psiphon` process (see
 * AndroidManifest). `gi.Seq` is the Psiphon-specific copy of gomobile's
 * bridge class, relocated from `go` → `gi` at build time by the Gradle
 * `relocatePsiphonAar` task (see app/build.gradle.kts). Its static
 * initializer loads ONLY `libpsiphon-gojni.so` — never Xray's
 * `libgojni.so` — so the `:psiphon` process hosts exactly one Go runtime.
 * The Xray runtime (`go.Seq` + `libgojni.so`) stays in the main and
 * `:psiphonbridge` processes, where it also runs alone.
 */
class GomobileRuntimeInitializer : ContentProvider() {
    override fun onCreate(): Boolean {
        val appContext = context?.applicationContext ?: return true
        val failure = PsiphonNativeRuntime.initialize(appContext)
        if (failure != null) {
            Log.e(
                "GomobileRuntimeInitializer",
                "Psiphon native runtime initialization failed: ${PsiphonNativeRuntime.describe(failure)}",
                failure,
            )
        }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<String>?,
        selection: String?,
        selectionArgs: Array<String>?,
        sortOrder: String?
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<String>?): Int = 0
}
