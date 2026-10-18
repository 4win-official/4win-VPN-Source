package com.forwin.vpn.mix.sstp.terminal

import androidx.documentfile.provider.DocumentFile
import com.forwin.vpn.mix.sstp.client.ClientBridge
import com.forwin.vpn.mix.sstp.client.ControlMessage
import com.forwin.vpn.mix.sstp.client.Result
import com.forwin.vpn.mix.sstp.client.Where
import com.forwin.vpn.mix.sstp.extension.capacityAfterLimit
import com.forwin.vpn.mix.sstp.extension.slide
import com.forwin.vpn.mix.sstp.extension.toIntAsUByte
import com.forwin.vpn.mix.sstp.preference.OscPrefKey
import com.forwin.vpn.mix.sstp.preference.accessor.*
import com.forwin.vpn.mix.sstp.unit.DataUnit
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.yield
import java.io.BufferedInputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.Socket
import java.net.SocketTimeoutException
import java.nio.ByteBuffer
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import javax.net.ssl.*
import java.security.SecureRandom
import javax.net.ssl.X509TrustManager


private const val HTTP_DELIMITER = "\r\n"
private const val HTTP_SUFFIX = "\r\n\r\n"

internal const val SSL_REQUEST_INTERVAL = 10_000L

internal class SSLTerminal(private val bridge: ClientBridge) {
    private val mutex = Mutex()

    private var socket: Socket? = null
    private lateinit var socketInputStream: InputStream
    private lateinit var socketOutputStream: OutputStream
    private lateinit var inboundBuffer: ByteBuffer
    private lateinit var outboundBuffer: ByteBuffer

    private lateinit var engine: SSLEngine

    private var jobInitialize: Job? = null

    private val doUseProxy = getBooleanPrefValue(OscPrefKey.PROXY_DO_USE_PROXY, bridge.prefs)
    private val sslHostname = getStringPrefValue(OscPrefKey.HOME_HOSTNAME, bridge.prefs)
    private val sslPort = getIntPrefValue(OscPrefKey.SSL_PORT, bridge.prefs)
    private val selectedVersion = getStringPrefValue(OscPrefKey.SSL_VERSION, bridge.prefs)
    private val enabledSuites = getSetPrefValue(OscPrefKey.SSL_SUITES, bridge.prefs)

    internal suspend fun initialize() {
        jobInitialize = bridge.service.scope.launch(bridge.handler) {
            if (!startHandshake()) return@launch

            if (!establishHttps()) return@launch

            bridge.controlMailbox.send(ControlMessage(Where.SSL, Result.PROCEEDED))
        }
    }

    private fun createTrustManagers(): Array<TrustManager> {
        val document = DocumentFile.fromTreeUri(
            bridge.service,
            getURIPrefValue(OscPrefKey.SSL_CERT_DIR, bridge.prefs)!!
        )!!

        val certFactory = CertificateFactory.getInstance("X.509")
        val keyStore = KeyStore.getDefaultType().let {
            KeyStore.getInstance(it)
        }
        keyStore.load(null, null)

        for (file in document.listFiles()) {
            if (file.isFile) {
                val stream =
                    BufferedInputStream(bridge.service.contentResolver.openInputStream(file.uri))
                val ca = certFactory.generateCertificate(stream) as X509Certificate
                keyStore.setCertificateEntry(file.name, ca)
                stream.close()
            }
        }

        val tmFactory = TrustManagerFactory.getDefaultAlgorithm().let {
            TrustManagerFactory.getInstance(it)
        }
        tmFactory.init(keyStore)

        return tmFactory.trustManagers
    }

    private suspend fun startHandshake(): Boolean {
        val sslContext: SSLContext

        if (getBooleanPrefValue(OscPrefKey.SSL_DO_VERIFY_CERT, bridge.prefs)) {
            sslContext = if (getBooleanPrefValue(OscPrefKey.SSL_DO_ADD_CERT, bridge.prefs)) {
                SSLContext.getInstance(selectedVersion).also {
                    it.init(null, createTrustManagers(), null)
                }
            } else {
                SSLContext.getDefault()
            }
        } else {
            sslContext = SSLContext.getInstance(selectedVersion)
            sslContext.init(null, arrayOf<TrustManager>(object : X509TrustManager {
                override fun getAcceptedIssuers(): Array<X509Certificate> {
                    return arrayOf()
                }

                override fun checkClientTrusted(
                    certs: Array<X509Certificate>,
                    authType: String
                ) {
                }

                override fun checkServerTrusted(
                    certs: Array<X509Certificate>,
                    authType: String
                ) {
                }
            }), SecureRandom())
        }
        engine = sslContext.createSSLEngine(sslHostname, sslPort)
        engine.useClientMode = true

        if (selectedVersion != "DEFAULT") {
            engine.enabledProtocols = arrayOf(selectedVersion)
        }

        if (getBooleanPrefValue(OscPrefKey.SSL_DO_SELECT_SUITES, bridge.prefs)) {
            val sortedSuites = engine.supportedCipherSuites.filter {
                enabledSuites.contains(it)
            }

            engine.enabledCipherSuites = sortedSuites.toTypedArray()
        }

        val socketHostname = if (doUseProxy) getStringPrefValue(OscPrefKey.PROXY_HOSTNAME, bridge.prefs) else sslHostname
        val socketPort = if (doUseProxy) getIntPrefValue(OscPrefKey.PROXY_PORT, bridge.prefs) else sslPort
        socket = if (doUseProxy) {
            Socket(java.net.Proxy(java.net.Proxy.Type.SOCKS, java.net.InetSocketAddress(socketHostname, socketPort))).also {
                it.connect(java.net.InetSocketAddress.createUnresolved(sslHostname, sslPort), 10_000)
                socketInputStream = it.getInputStream(); socketOutputStream = it.getOutputStream()
            }
        } else {
            Socket().also {
                it.connect(java.net.InetSocketAddress(sslHostname, sslPort), 10_000)
                socketInputStream = it.getInputStream(); socketOutputStream = it.getOutputStream()
            }
        }
        inboundBuffer = ByteBuffer.allocate(engine.session.packetBufferSize).also { it.limit(0) }
        outboundBuffer = ByteBuffer.allocate(engine.session.packetBufferSize)
        val tempBuffer = ByteBuffer.allocate(0)

        engine.beginHandshake()

        while (true) {
            yield()

            when (engine.handshakeStatus) {
                SSLEngineResult.HandshakeStatus.NEED_WRAP -> {
                    val result = send(tempBuffer)
                    if (result.handshakeStatus == SSLEngineResult.HandshakeStatus.FINISHED) {
                        break
                    }
                }

                SSLEngineResult.HandshakeStatus.NEED_UNWRAP -> {
                    val result = receive(tempBuffer)
                    if (result.handshakeStatus == SSLEngineResult.HandshakeStatus.FINISHED) {
                        break
                    }
                }

                else -> {
                    throw NotImplementedError(engine.handshakeStatus.name)
                }
            }
        }

        if (getBooleanPrefValue(OscPrefKey.SSL_DO_VERIFY, bridge.prefs)) {
            HttpsURLConnection.getDefaultHostnameVerifier().also {
                if (!it.verify(sslHostname, engine.session)) {
                    bridge.controlMailbox.send(ControlMessage(Where.SSL, Result.ERR_VERIFICATION_FAILED))
                    return false
                }
            }
        }

        return true
    }

    private suspend fun establishHttps(): Boolean {
        val buffer = ByteBuffer.allocate(getApplicationBufferSize())

        val request = arrayOf(
            "SSTP_DUPLEX_POST /sra_{BA195980-CD49-458b-9E23-C84EE0ADCD75}/ HTTP/1.1",
            "Content-Length: 18446744073709551615",
            "Host: $sslHostname",
            "SSTPCORRELATIONID: {${bridge.guid}}"
        ).joinToString(separator = HTTP_DELIMITER, postfix = HTTP_SUFFIX).toByteArray(Charsets.US_ASCII)

        buffer.put(request)
        buffer.flip()

        send(buffer)

        buffer.position(0)
        buffer.limit(0)

        var response = ""
        outer@ while (true) {
            receive(buffer)

            for (i in 0 until buffer.remaining()) {
                response += buffer.get().toIntAsUByte().toChar()

                if (response.endsWith(HTTP_SUFFIX)) {
                    break@outer
                }
            }
        }

        if (!response.split(HTTP_DELIMITER)[0].contains("200")) {
            bridge.controlMailbox.send(ControlMessage(Where.SSL, Result.ERR_UNEXPECTED_MESSAGE))
            return false
        }


        socket!!.soTimeout = 1_000
        bridge.service.protect(socket!!)
        return true
    }

    internal fun getSession(): SSLSession {
        return engine.session
    }

    internal fun getServerCertificate(): ByteArray {
        return engine.session.peerCertificates[0].encoded
    }

    internal fun getApplicationBufferSize(): Int {
        return engine.session.applicationBufferSize
    }

    internal fun receive(buffer: ByteBuffer): SSLEngineResult {
        var startPayload: Int
        var result: SSLEngineResult

        while (true) {
            startPayload = buffer.position()
            buffer.position(buffer.limit())
            buffer.limit(buffer.capacity())

            result = engine.unwrap(inboundBuffer, buffer)

            when (result.status) {
                SSLEngineResult.Status.OK -> {
                    break
                }

                SSLEngineResult.Status.BUFFER_OVERFLOW -> {
                    buffer.limit(buffer.position())
                    buffer.position(startPayload)

                    buffer.slide()
                }

                SSLEngineResult.Status.BUFFER_UNDERFLOW -> {
                    buffer.limit(buffer.position())
                    buffer.position(startPayload)

                    inboundBuffer.slide()

                    try {
                        val readSize = socketInputStream.read(
                            inboundBuffer.array(),
                            inboundBuffer.limit(),
                            inboundBuffer.capacityAfterLimit
                        )

                        inboundBuffer.limit(inboundBuffer.limit() + readSize)
                    } catch (_: SocketTimeoutException) { }
                }

                else -> {
                    throw NotImplementedError(result.status.name)
                }
            }
        }

        buffer.limit(buffer.position())
        buffer.position(startPayload)

        return result
    }

    internal suspend fun send(buffer: ByteBuffer): SSLEngineResult {
        mutex.withLock {
            var result: SSLEngineResult

            while (true) {
                outboundBuffer.clear()

                result = engine.wrap(buffer, outboundBuffer)
                if (result.status != SSLEngineResult.Status.OK) {
                    throw NotImplementedError(result.status.name)
                }

                socketOutputStream.write(
                    outboundBuffer.array(),
                    0,
                    outboundBuffer.position()
                )

                if (!buffer.hasRemaining()) {
                    socketOutputStream.flush()

                    break
                }
            }

            return result
        }
    }

    internal suspend fun sendDataUnit(unit: DataUnit) {
        ByteBuffer.allocate(unit.length).also {
            unit.write(it)
            it.flip()
            send(it)
        }
    }

    internal fun close() {
        jobInitialize?.cancel()
        socket?.close()
    }
}
