package com.forwin.vpn.mix

import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import java.io.Closeable

/** Per-instance raw-IP packet bridge and loopback SOCKS5 endpoint. */
class MixPacketStack private constructor(private var handle: Long) : AutoCloseable {
    val ready: Boolean get() = handle != 0L && nativeIsReady(handle)
    val error: String get() = if (handle == 0L) "closed" else nativeLastError(handle)

    override fun close() {
        val h = handle
        handle = 0L
        if (h != 0L) nativeStop(h)
    }

    companion object {
        init { System.loadLibrary("aether"); System.loadLibrary("aether_jni") }

        /** Starts asynchronously; [ready] becomes true only after the local SOCKS bind succeeds. */
        @JvmStatic
        fun start(packetFd: ParcelFileDescriptor, ipv4: String, ipv6: String, mtu: Int, listenPort: Int): MixPacketStack {
            require(listenPort in 1..65535) { "listenPort out of range" }
            val json = "{\"ipv4\":${quote(ipv4)},\"ipv6\":${quote(ipv6)},\"mtu\":$mtu,\"listen\":\"127.0.0.1:$listenPort\"}"
            // Native dup()s this descriptor; the caller retains and owns its descriptor.
            val h = nativeCreate(json, packetFd.fd)
            if (h <= 0) throw IllegalStateException(nativeCreateError(h))
            return MixPacketStack(h)
        }

        /** Returns two datagram descriptors; the first is normally passed to start(). */
        @JvmStatic
        fun createPacketPair(): Pair<ParcelFileDescriptor, ParcelFileDescriptor> {
            val left = java.io.FileDescriptor()
            val right = java.io.FileDescriptor()
            Os.socketpair(OsConstants.AF_UNIX, OsConstants.SOCK_DGRAM, 0, left, right)
            try {
                val ownedLeft = ParcelFileDescriptor.dup(left)
                try { return ownedLeft to ParcelFileDescriptor.dup(right) }
                catch (failure: Throwable) { ownedLeft.close(); throw failure }
            } finally { Os.close(left); Os.close(right) }
        }
        private fun quote(value: String): String = org.json.JSONObject.quote(value)
        private external fun nativeCreate(json: String, fd: Int): Long
        private external fun nativeCreateError(code: Long): String
        private external fun nativeIsReady(handle: Long): Boolean
        private external fun nativeLastError(handle: Long): String
        private external fun nativeStop(handle: Long): Int
    }
}
