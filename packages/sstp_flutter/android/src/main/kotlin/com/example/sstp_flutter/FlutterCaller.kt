package com.example.sstp_flutter

import android.os.Handler
import android.os.Looper
import com.example.sstp_flutter.preference.OscPrefKey

/** Drop UI events while detached; never let UI lifetime control the tunnel. */
internal fun notifyFlutter(method: String, arguments: Any?) {
    val channel = flutterChannel ?: return
    Handler(Looper.getMainLooper()).post {
        // A queued event must not reach an engine that has since been detached.
        if (flutterChannel === channel) channel.invokeMethod(method, arguments)
    }
}

class FlutterCaller {
    fun connect() {
        if (connectionStatus == OscPrefKey.Connected.name) return
        connectionStatus = OscPrefKey.Connected.name
        notifyFlutter("connectResponse", hashMapOf(
            "status" to connectionStatus,
            "ip" to assignedIp
        ))
    }

    fun connecting() {
        connectionStatus = OscPrefKey.Connecting.name
        notifyFlutter("connectResponse", hashMapOf("status" to connectionStatus))
    }

    suspend fun DownloadSpeed(downloadSpeed: Int, totalDownload: Int) {
        notifyFlutter("downloadSpeed", listOf(downloadSpeed, totalDownload))
    }

    suspend fun UploadSpeed(uploadSpeed: Int, totalUpload: Int) {
        notifyFlutter("uploadSpeed", listOf(uploadSpeed, totalUpload))
    }
}
