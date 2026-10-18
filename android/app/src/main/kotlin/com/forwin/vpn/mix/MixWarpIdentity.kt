package com.forwin.vpn.mix

import java.io.Closeable
import java.io.File
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.nio.file.StandardOpenOption

/**
 * Persistent identities used only by Mix WARP stages.
 *
 * The key is deliberately independent of the Mix session: a stage's WARP
 * registration survives reconnects, while standalone aether-warp.toml is
 * never read or copied.  A process lock prevents two native workers from
 * concurrently roaming the same WireGuard identity.
 */
internal object MixWarpIdentity {
    private const val ROOT = "mix-identities"
    private const val ACCOUNT = "aether-warp.toml"
    private const val LOCK = ".identity.lock"

    fun directory(filesDir: File, hopId: String): File =
        File(File(filesDir, ROOT), stableStageKey(hopId))

    fun accountPath(filesDir: File, hopId: String): File =
        File(directory(filesDir, hopId), ACCOUNT)

    /** Acquire a lifetime lease; the caller must close it after NativeCore.stop(). */
    fun acquire(filesDir: File, hopId: String): Lease {
        val dir = directory(filesDir, hopId)
        check(dir.mkdirs() || dir.isDirectory) { "Cannot create Mix WARP identity directory" }
        val channel = FileChannel.open(
            File(dir, LOCK).toPath(), StandardOpenOption.CREATE, StandardOpenOption.WRITE
        )
        val fileLock = try {
            channel.tryLock() ?: error("Mix WARP identity is already in use: ${dir.name}")
        } catch (busy: OverlappingFileLockException) {
            channel.close()
            error("Mix WARP identity is already in use: ${dir.name}")
        } catch (failure: Throwable) {
            channel.close()
            throw failure
        }
        return Lease(accountPath(filesDir, hopId), channel, fileLock)
    }

    /** Stable, path-safe stage key. Normal hop ordinals remain readable. */
    internal fun stableStageKey(hopId: String): String {
        val ordinal = hopId.toIntOrNull()
        require(ordinal != null && ordinal in 0..49 && hopId == ordinal.toString()) {
            "Invalid Mix WARP hop id"
        }
        return hopId
    }

    class Lease internal constructor(
        val account: File,
        private val channel: FileChannel,
        private val lock: FileLock,
    ) : Closeable {
        private var closed = false
        override fun close() {
            if (closed) return
            closed = true
            runCatching { lock.release() }
            channel.close()
        }
    }
}
