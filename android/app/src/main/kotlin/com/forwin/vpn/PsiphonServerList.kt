package com.forwin.vpn

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import kotlin.io.encoding.Base64

/** Native starts in any app process and Flutter's post-connect retry share one signed snapshot. */
internal object PsiphonServerList {
    private val queue = PsiphonRefreshQueue(Executors.newSingleThreadExecutor { task ->
        Thread(task, "psiphon-list-refresh").apply { isDaemon = true }
    })

    private fun store(context: Context, bootstrap: JSONObject) = PsiphonServerListStore(
        File(context.applicationContext.filesDir, "psiphon-server-list"),
        bootstrap.getString("RemoteServerListSignaturePublicKey"),
        { context.applicationContext.assets.open(PsiphonBootstrap.SERVER_LIST_ASSET) },
    )

    fun readLatest(context: Context, bootstrap: JSONObject): PsiphonBootstrap.ServerEntries =
        store(context, bootstrap).readLatest()

    fun readCatalog(context: Context, bootstrap: JSONObject): PsiphonServerListStore.Snapshot =
        store(context, bootstrap).readCatalog()

    sealed class RefreshResult {
        data class Finished(val updated: Boolean) : RefreshResult()
        object AlreadyRunning : RefreshResult()
    }

    /** Runs on the refresh executor; callback is never invoked on the caller/UI thread. */
    fun refreshNow(context: Context, callback: (RefreshResult) -> Unit) {
        val app = context.applicationContext
        if (!queue.tryRequest {
                var updated = false
                var busy = false
                try {
                    val acquired = PsiphonRefreshLock.runIfIdle(File(app.filesDir, "psiphon-server-list")) {
                        val bootstrap = app.assets.open("mix_psiphon_bootstrap.json").bufferedReader().use { JSONObject(it.readText()) }
                        val configured = bootstrap.getJSONArray("RemoteServerListURLs")
                        val urls = (0 until configured.length()).map {
                            String(Base64.decode(configured.getJSONObject(it).getString("URL")), Charsets.UTF_8)
                        }
                        updated = store(app, bootstrap).refresh(urls)
                    }
                    busy = !acquired
                } catch (_: Exception) { updated = false }
                callback(if (busy) RefreshResult.AlreadyRunning else RefreshResult.Finished(updated))
            }) {
            callback(RefreshResult.AlreadyRunning)
        }
    }

    /** Returns after scheduling; configuration, downloads and signature checks all run off-thread. */
    fun refreshInBackground(context: Context) {
        val app = context.applicationContext
        queue.request {
            try {
                PsiphonRefreshLock.runIfIdle(File(app.filesDir, "psiphon-server-list")) {
                    val bootstrap = app.assets.open("mix_psiphon_bootstrap.json").bufferedReader().use {
                        JSONObject(it.readText())
                    }
                    val configured = bootstrap.getJSONArray("RemoteServerListURLs")
                    val urls = (0 until configured.length()).map {
                        String(Base64.decode(configured.getJSONObject(it).getString("URL")), Charsets.UTF_8)
                    }
                    val updated = store(app, bootstrap).refresh(urls)
                    Log.i("PsiphonServerList", if (updated) "Verified server list refreshed"
                        else "Refresh unavailable; keeping last valid server list")
                }
            } catch (_: Exception) {
                Log.i("PsiphonServerList", "Refresh unavailable; keeping last valid server list")
            }
        }
    }
}
