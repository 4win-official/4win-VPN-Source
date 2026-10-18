package com.forwin.vpn.mix.sstp.client.ppp

import com.forwin.vpn.mix.sstp.client.ClientBridge
import com.forwin.vpn.mix.sstp.client.ControlMessage
import com.forwin.vpn.mix.sstp.client.Result
import com.forwin.vpn.mix.sstp.client.Where
import com.forwin.vpn.mix.sstp.unit.ppp.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch


internal class PPPClient(val bridge: ClientBridge) {
    internal val mailbox = Channel<Frame>(Channel.BUFFERED)

    private var jobControl: Job? = null

    internal suspend fun launchJobControl() {
        jobControl = bridge.service.scope.launch(bridge.handler) {
            while (isActive) {
                when (val received = mailbox.receive()) {
                    is LCPEchoRequest -> {
                        LCPEchoReply().also {
                            it.id = received.id
                            it.holder = "Abura Mashi Mashi".toByteArray(Charsets.US_ASCII)
                            bridge.sslTerminal!!.sendDataUnit(it)
                        }
                    }

                    is LCPEchoReply -> { }

                    is LcpDiscardRequest -> { }

                    is LCPTerminalRequest -> {
                        LCPTerminalAck().also {
                            it.id = received.id
                            bridge.sslTerminal!!.sendDataUnit(it)
                        }

                        bridge.controlMailbox.send(
                            ControlMessage(Where.PPP, Result.ERR_TERMINATE_REQUESTED)
                        )
                    }

                    is LCPProtocolReject -> {
                        bridge.controlMailbox.send(
                            ControlMessage(Where.PPP, Result.ERR_PROTOCOL_REJECTED)
                        )
                    }

                    is LCPCodeReject -> {
                        bridge.controlMailbox.send(
                            ControlMessage(Where.PPP, Result.ERR_CODE_REJECTED)
                        )
                    }

                    else -> {
                        bridge.controlMailbox.send(
                            ControlMessage(Where.PPP, Result.ERR_UNEXPECTED_MESSAGE)
                        )
                    }
                }
            }
        }
    }

    internal fun cancel() {
        jobControl?.cancel()
        mailbox.close()
    }
}
