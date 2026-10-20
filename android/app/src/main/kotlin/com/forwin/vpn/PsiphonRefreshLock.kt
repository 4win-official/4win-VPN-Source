package com.forwin.vpn

import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.OverlappingFileLockException

/** Advisory lock shared by all app processes; used only on background workers. */
internal object PsiphonRefreshLock {
    /** An overlapping request joins the existing attempt rather than waiting or downloading twice. */
    fun runIfIdle(directory: File, refresh: () -> Unit): Boolean {
        check(directory.mkdirs() || directory.isDirectory) { "Cannot prepare Psiphon refresh lock" }
        RandomAccessFile(File(directory, "refresh.lock"), "rw").use { file ->
            file.channel.use { channel ->
                val lock = try { channel.tryLock() } catch (_: OverlappingFileLockException) { null }
                    ?: return false
                lock.use { refresh() }
                return true
            }
        }
    }
}
