package com.forwin.vpn.mix.sstp.client.ppp

import com.forwin.vpn.mix.sstp.DEFAULT_MRU
import com.forwin.vpn.mix.sstp.MIN_MRU
import com.forwin.vpn.mix.sstp.client.ClientBridge
import com.forwin.vpn.mix.sstp.client.ControlMessage
import com.forwin.vpn.mix.sstp.client.Result
import com.forwin.vpn.mix.sstp.client.Where
import com.forwin.vpn.mix.sstp.unit.ppp.*
import com.forwin.vpn.mix.sstp.unit.ppp.option.*
import kotlin.math.max
import kotlin.math.min


internal class LCPClient(bridge: ClientBridge) : ConfigClient<LCPConfigureFrame>(Where.LCP, bridge) {
    private var isMruRejected = false

    override fun tryCreateServerReject(request: LCPConfigureFrame): LCPConfigureFrame? {
        val reject = LCPOptionPack()

        if (request.options.unknownOptions.isNotEmpty()) {
            reject.unknownOptions = request.options.unknownOptions
        }

        return if (reject.allOptions.isNotEmpty()) {
            LCPConfigureReject().also {
                it.id = request.id
                it.options = reject
                it.options.order = request.options.order
            }
        } else null
    }

    override fun tryCreateServerNak(request: LCPConfigureFrame): LCPConfigureFrame? {
        val nak = LCPOptionPack()

        val serverMru = request.options.mruOption?.unitSize ?: DEFAULT_MRU
        if (serverMru < bridge.PPP_MTU) {
            nak.mruOption = MRUOption().also { it.unitSize = bridge.PPP_MTU }
        }


        val serverAuth = request.options.authOption ?: AuthOptionUnknown(0)
        var isAuthAcknowledged = false

        when (serverAuth) {
            is AuthOptionMSChapv2 -> {
                if (bridge.PPP_MSCHAPv2_ENABLED) {
                    bridge.currentAuth = serverAuth
                    isAuthAcknowledged = true
                }
            }

            is AuthOptionPAP -> {
                if (bridge.PPP_PAP_ENABLED) {
                    bridge.currentAuth = serverAuth
                    isAuthAcknowledged = true
                }
            }
        }

        if (!isAuthAcknowledged) {
            nak.authOption = bridge.getPreferredAuthOption()
        }


        return if (nak.allOptions.isNotEmpty()) {
            LCPConfigureNak().also {
                it.id = request.id
                it.options = nak
                it.options.order = request.options.order
            }
        } else null
    }

    override fun createServerAck(request: LCPConfigureFrame): LCPConfigureFrame {
        return LCPConfigureAck().also {
            it.id = request.id
            it.options = request.options
        }
    }


    override fun createClientRequest(): LCPConfigureFrame {
        val request = LCPConfigureRequest()

        if (!isMruRejected) {
            request.options.mruOption = MRUOption().also { it.unitSize = bridge.currentMRU }
        }

        return request
    }

    override suspend fun tryAcceptClientNak(nak: LCPConfigureFrame) {
        nak.options.mruOption?.also {
            bridge.currentMRU = max(min(it.unitSize, bridge.PPP_MRU), MIN_MRU)
        }
    }

    override suspend fun tryAcceptClientReject(reject: LCPConfigureFrame) {
        reject.options.mruOption?.also {
            isMruRejected = true

            if (DEFAULT_MRU > bridge.PPP_MRU) {
                bridge.controlMailbox.send(
                    ControlMessage(Where.LCP_MRU, Result.ERR_OPTION_REJECTED)
                )
            }
        }

        reject.options.authOption?.also {
            bridge.controlMailbox.send(ControlMessage(Where.LCP_AUTH, Result.ERR_OPTION_REJECTED))
        }
    }
}
