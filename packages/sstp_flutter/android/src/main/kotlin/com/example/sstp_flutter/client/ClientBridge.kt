package com.example.sstp_flutter.client

import android.content.SharedPreferences
import com.example.sstp_flutter.preference.AppString
import com.example.sstp_flutter.preference.OscPrefKey
import com.example.sstp_flutter.preference.accessor.getBooleanPrefValue
import com.example.sstp_flutter.preference.accessor.getIntPrefValue
import com.example.sstp_flutter.preference.accessor.getStringPrefValue
import com.example.sstp_flutter.preference.getValidAllowedAppInfos
import com.example.sstp_flutter.service.SstpVpnService
import com.example.sstp_flutter.service.SessionPreferences
import com.example.sstp_flutter.terminal.IPTerminal
import com.example.sstp_flutter.terminal.SSLTerminal
import com.example.sstp_flutter.unit.ppp.option.AuthOption
import com.example.sstp_flutter.unit.ppp.option.AuthOptionMSChapv2
import com.example.sstp_flutter.unit.ppp.option.AuthOptionPAP
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.*


internal class ChapMessage {
    val serverChallenge = ByteArray(16)
    val clientChallenge = ByteArray(16)
    val serverResponse = ByteArray(42)
    val clientResponse = ByteArray(24)
}

internal enum class Where {
    SSL,
    PROXY,
    SSTP_DATA,
    SSTP_CONTROL,
    SSTP_REQUEST,
    SSTP_HASH,
    PPP,
    PAP,
    CHAP,
    LCP,
    LCP_MRU,
    LCP_AUTH,
    IPCP,
    IPCP_IP,
    IPV6CP,
    IPV6CP_IDENTIFIER,
    IP,
    IPv4,
    IPv6,
    ROUTE,
    INCOMING,
    OUTGOING,
}

internal data class ControlMessage(
    val from: Where,
    val result: Result
)
internal enum class Result {
    PROCEEDED,

    // common errors
    ERR_TIMEOUT,
    ERR_COUNT_EXHAUSTED,
    ERR_UNKNOWN_TYPE, // the data cannot be parsed
    ERR_UNEXPECTED_MESSAGE, // the data can be parsed, but it's received in the wrong time
    ERR_PARSING_FAILED,
    ERR_VERIFICATION_FAILED,

    // for SSTP
    ERR_NEGATIVE_ACKNOWLEDGED,
    ERR_ABORT_REQUESTED,
    ERR_DISCONNECT_REQUESTED,

    // for PPP
    ERR_TERMINATE_REQUESTED,
    ERR_PROTOCOL_REJECTED,
    ERR_CODE_REJECTED,
    ERR_AUTHENTICATION_FAILED,
    ERR_ADDRESS_REJECTED,
    ERR_OPTION_REJECTED,

    // for IP
    ERR_INVALID_ADDRESS,

    // for INCOMING
    ERR_INVALID_PACKET_SIZE,
}

internal class ClientBridge(
    internal val service: SstpVpnService,
    private val frozenPrefs: Map<String, *> = emptyMap<String, Any?>(),
    sessionPrefs: SharedPreferences? = null,
) {
    /** A bridge must never read mutable application preferences after connect. */
    internal val prefs: SharedPreferences = sessionPrefs ?: SessionPreferences(frozenPrefs)
    internal val builder = service.Builder()
    internal lateinit var handler: CoroutineExceptionHandler

    internal val controlMailbox = Channel<ControlMessage>(Channel.BUFFERED)

    internal var sslTerminal: SSLTerminal? = null
    internal var ipTerminal: IPTerminal? = null

    private fun stringPref(key: OscPrefKey): String = getStringPrefValue(key, prefs)
    private fun intPref(key: OscPrefKey): Int = when (val value = frozenPrefs[key.name]) {
        is Number -> value.toInt()
        is String -> value.toIntOrNull() ?: getIntPrefValue(key, prefs)
        else -> getIntPrefValue(key, prefs)
    }
    private fun booleanPref(key: OscPrefKey): Boolean =
        getBooleanPrefValue(key, prefs)
    internal fun frozenIntPref(key: OscPrefKey): Int = intPref(key)
    internal fun frozenBooleanPref(key: OscPrefKey): Boolean = booleanPref(key)

    internal val HOME_USERNAME = stringPref(OscPrefKey.HOME_USERNAME)
    internal val HOME_PASSWORD = stringPref(OscPrefKey.HOME_PASSWORD)
    internal val PPP_MRU = intPref(OscPrefKey.PPP_MRU)
    internal val PPP_MTU = intPref(OscPrefKey.PPP_MTU)
    internal val PPP_PAP_ENABLED = booleanPref(OscPrefKey.PPP_PAP_ENABLED)
    internal val PPP_MSCHAPv2_ENABLED = booleanPref(OscPrefKey.PPP_MSCHAPv2_ENABLED)
    internal val PPP_IPv4_ENABLED = booleanPref(OscPrefKey.PPP_IPv4_ENABLED)
    internal val PPP_IPv6_ENABLED = booleanPref(OscPrefKey.PPP_IPv6_ENABLED)

    internal lateinit var chapMessage: ChapMessage
    internal val nonce = ByteArray(32)
    internal val guid = UUID.randomUUID().toString()
    internal var hashProtocol: Byte = 0

    private val mutex = Mutex()
    private var frameID = -1

    internal var currentMRU = PPP_MRU
    internal var currentAuth = getPreferredAuthOption()
    internal val currentIPv4 = ByteArray(4)
    internal val currentIPv6 = ByteArray(8)
    internal val currentProposedDNS = ByteArray(4)

    internal val allowedApps: List<AppString> = mutableListOf<AppString>().also {
        if (booleanPref(OscPrefKey.ROUTE_DO_ENABLE_APP_BASED_RULE)) {
            getValidAllowedAppInfos(prefs, service.packageManager).forEach { info ->
                it.add(
                    AppString(
                        info.packageName,
                        service.packageManager.getApplicationLabel(info).toString()
                    )
                )
            }
        }
    }

    internal fun getPreferredAuthOption(): AuthOption {
        return if (PPP_MSCHAPv2_ENABLED) AuthOptionMSChapv2() else AuthOptionPAP()
    }

    internal fun attachSSLTerminal() {
        sslTerminal = SSLTerminal(this)
    }

    internal fun attachIPTerminal() {
        ipTerminal = IPTerminal(this)
    }

    internal suspend fun allocateNewFrameID(): Byte {
        mutex.withLock {
            frameID += 1
            return frameID.toByte()
        }
    }
}
