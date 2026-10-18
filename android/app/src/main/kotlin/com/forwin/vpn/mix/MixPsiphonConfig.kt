package com.forwin.vpn.mix

import org.json.JSONObject
import java.io.File

/** Psiphon's SDK otherwise migrates the app's standalone datastore by default.
 * Each ordinal gets its own persistent data root; no native database is shared
 * between two Psiphon processes or with standalone mode.
 */
internal object MixPsiphonConfig {
    fun root(filesDir: File, hopId: String): File {
        val ordinal = hopId.toIntOrNull()
        require(ordinal != null && ordinal in 0..49 && hopId == ordinal.toString()) { "Invalid Mix Psiphon stage" }
        return File(filesDir, "mix-psiphon/stage-$hopId")
    }

    fun build(config: JSONObject, root: File, port: Int, upstream: String?, bootstrap: JSONObject = JSONObject()): JSONObject {
        require(port in 1..65535) { "Invalid Mix Psiphon SOCKS port" }
        val result = JSONObject(bootstrap.toString())
        // Keep explicit per-hop options without mutating either input. The
        // packaged public bootstrap supplies the IDs, version and signed list
        // that the core requires; the SDK does NOT invent those defaults.
        config.keys().forEach { key -> result.put(key, config.get(key)) }
        // Never allow the SDK to migrate or open standalone state. Its default
        // migration source is supplied by the private HostService context too.
        listOf("DataStoreDirectory", "RemoteServerListDownloadFilename",
            "MigrateDataStoreDirectory", "MigrateRemoteServerListDownloadFilename",
            "MigrateObfuscatedServerListDownloadDirectory").forEach { result.remove(it) }
        result.put("DataRootDirectory", File(root, "tunnel-core").absolutePath)
            .put("LocalSocksProxyPort", port).put("LocalHttpProxyPort", 0)
        if (upstream == null) result.remove("UpstreamProxyURL")
        else result.put("UpstreamProxyURL", upstream)
        return result
    }
}
