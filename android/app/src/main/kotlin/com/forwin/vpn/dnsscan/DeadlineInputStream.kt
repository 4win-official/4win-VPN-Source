package com.forwin.vpn.dnsscan

import java.io.FilterInputStream
import java.net.Socket
import java.net.SocketTimeoutException
import java.util.concurrent.TimeUnit

/** A slow peer cannot reset the whole query deadline by sending single bytes. */
internal class DeadlineInputStream(private val socket: Socket, private val deadlineNanos: Long) :
    FilterInputStream(socket.getInputStream()) {
    private fun remaining() {
        val nanos = deadlineNanos - System.nanoTime()
        if (nanos <= 0) throw SocketTimeoutException("The query deadline expired.")
        socket.soTimeout = TimeUnit.NANOSECONDS.toMillis(nanos).coerceIn(1L, Int.MAX_VALUE.toLong()).toInt()
    }
    override fun read(): Int { remaining(); return super.read() }
    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        remaining(); return super.read(buffer, offset, length)
    }
}
