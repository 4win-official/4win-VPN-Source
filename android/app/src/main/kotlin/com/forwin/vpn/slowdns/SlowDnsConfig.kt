package com.forwin.vpn.slowdns

import org.json.JSONObject
import java.net.Inet6Address
import java.net.InetAddress
import java.net.URI

/** The native boundary validates again; it never resolves a hostname to validate it. */
data class SlowDnsConfig(
    val name: String, val domain: String, val nameServer: String, val pubKey: String,
    val port: Int, val dnsTransport: Transport, val dohUrl: String?,
    val resolvers: List<Resolver>, val username: String?, val password: String?
) {
    enum class Transport { UDP, DOT, DOH }
    data class Resolver(val host: String, val port: Int) {
        init { require(validHost(host) && port in 1..65535) { "Invalid DNS resolver or port." } }
        fun authority() = if (host.contains(':')) "[$host]:$port" else "$host:$port"
    }
    companion object {
        private val label = Regex("[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?")
        private fun validDomain(value: String): Boolean {
            val name = value.removeSuffix(".")
            return name.length in 1..253 && name.split('.').all { it.length <= 63 && label.matches(it) }
        }
        private fun bareHost(value: String): String = value.removePrefix("[").removeSuffix("]")
        private fun validHost(value: String): Boolean {
            if (value.contains(':')) return value.matches(Regex("[0-9a-fA-F:]+")) &&
                runCatching { InetAddress.getByName(value) is Inet6Address }.getOrDefault(false)
            if (value.matches(Regex("[0-9.]+"))) {
                val parts = value.split('.')
                return parts.size == 4 && parts.all {
                    it.matches(Regex("0|[1-9][0-9]{0,2}")) && (it.toIntOrNull() ?: 256) <= 255
                }
            }
            return validDomain(value)
        }
        private fun optional(o: JSONObject, key: String): String? {
            if (!o.has(key) || o.isNull(key)) return null
            require(o.get(key) is String) { "Invalid $key." }
            return o.getString(key).takeIf { it.isNotEmpty() }
        }
        fun fromJson(raw: String) = fromJson(JSONObject(raw))
        fun fromJson(o: JSONObject): SlowDnsConfig {
            val transport = when (optional(o, "dnsTransport")?.lowercase() ?: "udp") {
                "udp" -> Transport.UDP; "dot" -> Transport.DOT; "doh" -> Transport.DOH
                else -> error("DNS transport must be udp, dot, or doh.")
            }
            val standardPort = when (transport) { Transport.UDP -> 53; Transport.DOT -> 853; Transport.DOH -> 443 }
            val port = if (o.isNull("port") || !o.has("port")) standardPort else o.getInt("port")
            require(port in 1..65535) { "Port must be between 1 and 65535." }
            val name = optional(o, "name")?.trim() ?: ""
            val domain = optional(o, "domain")?.trim()?.removeSuffix(".") ?: ""
            val key = optional(o, "pubKey")?.trim() ?: ""
            require(name.isNotEmpty()) { "Name is required." }
            require(validDomain(domain)) { "Invalid tunnel domain." }
            require(key.matches(Regex("[0-9a-fA-F]{64}"))) { "The server public key must be 64 hexadecimal characters." }
            val doh = optional(o, "dohUrl")?.trim()
            if (transport == Transport.DOH) {
                val url = runCatching { URI(doh ?: "") }.getOrNull()
                require(url != null && url.scheme == "https" && !url.host.isNullOrEmpty() &&
                    url.userInfo == null && url.fragment == null && (url.port == -1 || url.port in 1..65535) &&
                    validHost(bareHost(url.host))) { "DoH requires a valid HTTPS URL without credentials or a fragment." }
            }
            val primary = bareHost(optional(o, "nameServer")?.trim() ?: "")
            val candidates = if (transport == Transport.DOH) {
                // DoH uses its URL only; unrelated resolver IPs cannot downgrade it.
                listOf(Resolver(bareHost(URI(doh!!).host), port))
            } else {
                val all = mutableListOf(Resolver(primary, port))
                val extra = o.optJSONArray("resolvers")
                require(extra == null || extra.length() <= 31) { "Use at most 32 resolver candidates per profile." }
                if (extra != null) for (i in 0 until extra.length()) {
                    require(extra.get(i) is String) { "Resolvers must be bare IP addresses or hostnames." }
                    all.add(Resolver(bareHost(extra.getString(i).trim()), port))
                }
                all.distinct()
            }
            val user = optional(o, "username")
            val pass = optional(o, "password")
            require((user == null) == (pass == null)) { "Remote SOCKS5 username and password are required together." }
            if (user != null) require(user.toByteArray(Charsets.UTF_8).size in 1..255 &&
                pass!!.toByteArray(Charsets.UTF_8).size in 1..255) { "SOCKS5 credentials must be 1 to 255 UTF-8 bytes." }
            return SlowDnsConfig(name, domain, primary, key, port, transport,
                if (transport == Transport.DOH) doh else null, candidates, user, pass)
        }
    }
}

object SlowDnsCommand {
    fun executable(nativeLibraryDir: String) = "$nativeLibraryDir/libdnstt.so"
    fun build(config: SlowDnsConfig, resolver: SlowDnsConfig.Resolver, nativeLibraryDir: String, localPort: Int): List<String> {
        require(localPort in 1..65535)
        val transport = when (config.dnsTransport) {
            SlowDnsConfig.Transport.UDP -> listOf("-udp", resolver.authority())
            SlowDnsConfig.Transport.DOT -> listOf("-dot", resolver.authority())
            SlowDnsConfig.Transport.DOH -> listOf("-doh", config.dohUrl!!)
        }
        return listOf(executable(nativeLibraryDir)) + transport +
            listOf("-pubkey", config.pubKey, config.domain, "127.0.0.1:$localPort")
    }
}
