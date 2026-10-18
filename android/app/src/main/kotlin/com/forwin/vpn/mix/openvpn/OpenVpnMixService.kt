package com.forwin.vpn.mix.openvpn

import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.os.ParcelFileDescriptor
import com.forwin.vpn.mix.MixPacketStack
import de.blinkt.openvpn.core.ConnectionStatus
import de.blinkt.openvpn.core.OpenVPNService
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** OpenVPN engine whose tun endpoint is a Unix datagram packet pair, never Android TUN. */
open class OpenVpnMixService : OpenVPNService() {
    private var runtime: Runtime? = null
    private var packetPeer: ParcelFileDescriptor? = null
    private var packetStack: MixPacketStack? = null
    private var ipv4 = ""
    private var ipv6 = ""
    private var mtu = 1280
    private val opened = AtomicBoolean(false)

    private val privateContext: RuntimeContext?
        get() = runtime?.context ?: pendingContext

    override fun getApplicationContext(): Context = privateContext ?: super.getApplicationContext()
    override fun getFilesDir(): File = privateContext?.filesRoot ?: super.getFilesDir()
    override fun getCacheDir(): File = privateContext?.cacheRoot ?: super.getCacheDir()
    override fun getSharedPreferences(name: String, mode: Int): SharedPreferences =
        (privateContext ?: super.getApplicationContext()).getSharedPreferences(name, mode)

    override fun setMtu(value: Int) { mtu = value; super.setMtu(value) }
    override fun setLocalIP(local: String, netmask: String, mtu: Int, mode: String) {
        ipv4 = local.substringBefore('/').trim()
        this.mtu = mtu
        super.setLocalIP(ipv4, netmask, mtu, mode)
    }
    override fun setLocalIPv6(value: String) { ipv6 = value.substringBefore('/').trim(); super.setLocalIPv6(ipv6) }

    override fun updateState(state: String, logmessage: String, resid: Int, level: ConnectionStatus, intent: Intent?) {
        super.updateState(state, logmessage, resid, level, intent)
        val fatal = state.contains("AUTH_FAILED", true) || state.contains("EXITING", true) ||
            state.contains("CONNECT_ERROR", true)
        if (fatal) runtime?.failure("OpenVPN runtime failure: ${state.take(96)}")
    }

    override fun openTun(): ParcelFileDescriptor {
        check(opened.compareAndSet(false, true)) { "OpenVPN requested packet fd twice" }
        val configured = runtime ?: throw IllegalStateException("OpenVPN Mix runtime missing")
        val pair = MixPacketStack.createPacketPair()
        try {
            val stack = MixPacketStack.start(pair.first, ipv4, ipv6, mtu.coerceIn(576, 65535), configured.port)
            pair.first.close()
            packetStack = stack
            packetPeer = pair.second
            configured.stack = stack
            Thread {
                try {
                    while (!configured.stopped.get() && !stack.ready) Thread.sleep(25)
                    if (!configured.stopped.get()) {
                        if (stack.ready) configured.ready()
                        else configured.failure(stack.error)
                    }
                } catch (t: Throwable) {
                    if (!configured.stopped.get()) configured.failure(t.message ?: "Mix packet stack failed")
                }
            }.apply { name = "openvpn-mix-ready-${configured.sessionId}"; isDaemon = true }.start()
            // OpenVPN's native process owns this end; no Builder.establish() is called.
            return pair.second
        } catch (t: Throwable) {
            pair.first.close(); pair.second.close(); opened.set(false)
            configured.failure(t.message ?: "Unable to create Mix packet stack")
            throw t
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val uuid = intent?.getStringExtra(KEY_UUID)
        if (uuid != null) runtime = runtimes[uuid]
        runtime?.context?.ensureRoots()
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onDestroy() {
        val current = runtime
        current?.stopped?.set(true)
        packetStack?.close(); packetStack = null
        packetPeer?.close(); packetPeer = null
        runtimes.remove(current?.uuid, current)
        super.onDestroy()
        current?.cleanup()
        current?.closed?.countDown()
    }

    companion object {
        const val KEY_UUID = "com.forwin.vpn.mix.openvpn.profileUuid"
        private val runtimes = ConcurrentHashMap<String, Runtime>()
        @Volatile private var pendingContext: RuntimeContext? = null
        fun install(runtime: Runtime) { pendingContext = runtime.context; runtime.context.ensureRoots(); runtimes[runtime.uuid] = runtime }
        fun remove(uuid: String) { runtimes.remove(uuid)?.stop() }
    }

    class RuntimeContext(base: Context, sessionId: String, hopId: String) : ContextWrapper(base.applicationContext) {
        val root: File = File(base.filesDir, "mix-runtime/$sessionId/$hopId")
        val filesRoot: File = File(root, "files")
        val cacheRoot: File = File(root, "cache")
        private val prefsRoot = "mix_${sessionId}_${hopId}_"
        fun ensureRoots() { filesRoot.mkdirs(); cacheRoot.mkdirs() }
        override fun getFilesDir(): File { ensureRoots(); return filesRoot }
        override fun getCacheDir(): File { ensureRoots(); return cacheRoot }
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences = super.getSharedPreferences(prefsRoot + name, mode)
        override fun getApplicationContext(): Context = this
        override fun openFileInput(name: String): FileInputStream = FileInputStream(File(filesRoot, name))
        override fun openFileOutput(name: String, mode: Int): FileOutputStream { ensureRoots(); return FileOutputStream(File(filesRoot, name), mode and Context.MODE_APPEND != 0) }
        override fun deleteFile(name: String): Boolean = File(filesRoot, name).delete()
        override fun fileList(): Array<String> = filesRoot.list() ?: emptyArray()
        override fun getFileStreamPath(name: String): File = File(filesRoot, name)
    }

    class Runtime(
        val uuid: String, val sessionId: String, val port: Int, val context: RuntimeContext,
        private val onReadyCallback: (Boolean) -> Unit,
        private val onFailureCallback: (String) -> Unit
    ) {
        val stopped = AtomicBoolean(false)
        val closed = CountDownLatch(1)
        @Volatile var stack: MixPacketStack? = null
        private val readySent = AtomicBoolean(false)
        private val failureSent = AtomicBoolean(false)
        fun ready() { if (readySent.compareAndSet(false, true)) onReadyCallback(true) }
        fun failure(message: String) { if (!stopped.get() && failureSent.compareAndSet(false, true)) onFailureCallback(message.take(512)) }
        fun stop() { stopped.set(true); stack?.close() }
        fun awaitClosed(timeout: Long, unit: TimeUnit): Boolean = closed.await(timeout, unit)
        fun cleanup() {
            stack?.close(); stack = null
            runCatching { context.root.deleteRecursively() }
        }
    }
}

class OpenVpnMixService0 : OpenVpnMixService()
class OpenVpnMixService1 : OpenVpnMixService()
class OpenVpnMixService2 : OpenVpnMixService()
class OpenVpnMixService3 : OpenVpnMixService()
class OpenVpnMixService4 : OpenVpnMixService()
class OpenVpnMixService5 : OpenVpnMixService()
class OpenVpnMixService6 : OpenVpnMixService()
class OpenVpnMixService7 : OpenVpnMixService()
class OpenVpnMixService8 : OpenVpnMixService()
class OpenVpnMixService9 : OpenVpnMixService()
class OpenVpnMixService10 : OpenVpnMixService()
class OpenVpnMixService11 : OpenVpnMixService()
class OpenVpnMixService12 : OpenVpnMixService()
class OpenVpnMixService13 : OpenVpnMixService()
class OpenVpnMixService14 : OpenVpnMixService()
class OpenVpnMixService15 : OpenVpnMixService()
class OpenVpnMixService16 : OpenVpnMixService()
class OpenVpnMixService17 : OpenVpnMixService()
class OpenVpnMixService18 : OpenVpnMixService()
class OpenVpnMixService19 : OpenVpnMixService()
class OpenVpnMixService20 : OpenVpnMixService()
class OpenVpnMixService21 : OpenVpnMixService()
class OpenVpnMixService22 : OpenVpnMixService()
class OpenVpnMixService23 : OpenVpnMixService()
class OpenVpnMixService24 : OpenVpnMixService()
class OpenVpnMixService25 : OpenVpnMixService()
class OpenVpnMixService26 : OpenVpnMixService()
class OpenVpnMixService27 : OpenVpnMixService()
class OpenVpnMixService28 : OpenVpnMixService()
class OpenVpnMixService29 : OpenVpnMixService()
class OpenVpnMixService30 : OpenVpnMixService()
class OpenVpnMixService31 : OpenVpnMixService()
class OpenVpnMixService32 : OpenVpnMixService()
class OpenVpnMixService33 : OpenVpnMixService()
class OpenVpnMixService34 : OpenVpnMixService()
class OpenVpnMixService35 : OpenVpnMixService()
class OpenVpnMixService36 : OpenVpnMixService()
class OpenVpnMixService37 : OpenVpnMixService()
class OpenVpnMixService38 : OpenVpnMixService()
class OpenVpnMixService39 : OpenVpnMixService()
class OpenVpnMixService40 : OpenVpnMixService()
class OpenVpnMixService41 : OpenVpnMixService()
class OpenVpnMixService42 : OpenVpnMixService()
class OpenVpnMixService43 : OpenVpnMixService()
class OpenVpnMixService44 : OpenVpnMixService()
class OpenVpnMixService45 : OpenVpnMixService()
class OpenVpnMixService46 : OpenVpnMixService()
class OpenVpnMixService47 : OpenVpnMixService()
class OpenVpnMixService48 : OpenVpnMixService()
class OpenVpnMixService49 : OpenVpnMixService()
