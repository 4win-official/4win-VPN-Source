package com.forwin.vpn

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import go.Seq

/**
 * Initializes the gomobile runtime before any Psiphon Java binding is created.
 * This provider runs in the Psiphon VPN process, where the shared go.Seq
 * runtime must have an Android Context before PsiphonTunnel starts.
 */
class GomobileRuntimeInitializer : ContentProvider() {
    override fun onCreate(): Boolean {
        try {
            Seq.setContext(context?.applicationContext)
        } catch (_: Throwable) {
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
