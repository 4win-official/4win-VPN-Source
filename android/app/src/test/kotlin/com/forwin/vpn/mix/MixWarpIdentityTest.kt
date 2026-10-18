package com.forwin.vpn.mix

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class MixWarpIdentityTest {
    @Test fun sameHopAcrossSessionsUsesSamePersistentAccountPath() {
        val files = Files.createTempDirectory("mix-identities").toFile()
        val first = MixWarpIdentity.accountPath(files, "2")
        val second = MixWarpIdentity.accountPath(files, "2")
        assertEquals(first, second)
        assertEquals(files.resolve("mix-identities/2/aether-warp.toml"), first)
        assertNotEquals(MixWarpIdentity.accountPath(files, "1"), first)
        assertFalse(files.resolve("aether-warp.toml").exists())
    }

    @Test fun leasePreventsConcurrentUseAndReleasesAfterClose() {
        val files = Files.createTempDirectory("mix-identities-lock").toFile()
        val first = MixWarpIdentity.acquire(files, "0")
        try {
            try {
                MixWarpIdentity.acquire(files, "0")
                fail("same stage identity must be process-locked")
            } catch (expected: IllegalStateException) {
                assertTrue(expected.message!!.contains("already in use"))
            }
        } finally {
            first.close()
        }
        MixWarpIdentity.acquire(files, "0").close()
    }

    @Test fun standaloneAccountIsNeverSelected() {
        val files = Files.createTempDirectory("mix-identities-standalone").toFile()
        val standalone = files.resolve("aether-warp.toml")
        standalone.writeText("standalone")
        assertNotEquals(standalone, MixWarpIdentity.accountPath(files, "0"))
    }
}
