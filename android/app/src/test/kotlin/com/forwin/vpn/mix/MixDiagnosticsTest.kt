package com.forwin.vpn.mix

import org.junit.Assert.*
import org.junit.Test

/** Exercises the private snapshot without starting Android services or engines. */
class MixDiagnosticsTest {
    private val type = Class.forName("com.forwin.vpn.mix.MixCoordinatorService\$Companion\$DiagnosticsSnapshot")
    private fun snapshot(count: Int): Any = type.getDeclaredConstructor(String::class.java, Int::class.javaPrimitiveType)
        .apply { isAccessible = true }.newInstance("attempt-1", count)
    private fun invoke(target: Any, name: String, vararg args: Any): Any? {
        val method = type.declaredMethods.single { it.name == name && it.parameterCount == args.size }
        method.isAccessible = true
        return method.invoke(target, *args)
    }
    @Suppress("UNCHECKED_CAST")
    private fun read(target: Any) = invoke(target, "asMap") as Map<String, Any?>
    @Suppress("UNCHECKED_CAST")
    private fun blocks(target: Any) = read(target)["blocks"] as List<Map<String, Any?>>

    @Test fun exactPositionOfFailureIsRetainedInFiftyBlockChain() {
        val data = snapshot(50)
        for (index in 0..24) invoke(data, "ready", index)
        invoke(data, "starting", 25)
        invoke(data, "failed", 25, "Block initialization failed")
        val result = blocks(data)
        assertEquals(50, result.size)
        assertEquals("attempt-1", read(data)["attemptId"])
        assertEquals("ready", result[24]["state"])
        assertEquals(25, result[25]["index"])
        assertEquals("failed", result[25]["state"])
        assertEquals("pending", result[26]["state"])
        invoke(data, "ready", 25)
        invoke(data, "setPhase", "Connected")
        assertEquals("failed", blocks(data)[25]["state"])
        assertEquals("Chain failed", read(data)["phase"])
    }

    @Test fun globalFailureDoesNotInventFinalBlockFailureOrMutateOldRead() {
        val data = snapshot(2)
        val old = blocks(data)
        invoke(data, "ready", 0)
        invoke(data, "ready", 1)
        invoke(data, "globalFailure", "Complete-chain test failed")
        assertTrue(blocks(data).all { it["state"] == "ready" })
        assertTrue(old.all { it["state"] == "pending" })
        assertEquals("Chain failed", read(data)["phase"])
        assertEquals("Complete-chain test failed", read(data)["error"])
    }

    @Test fun psiphonWorkerFailureDetailIsRetainedWithoutChangingOtherProtocols() {
        val detail = "Psiphon packet tunnel failed: UnsatisfiedLinkError: native library not found"
        assertEquals(detail, MixCoordinatorService.psiphonFailureDetail("psiphon", detail))
        assertNull(MixCoordinatorService.psiphonFailureDetail("warp", detail))
        assertNull(MixCoordinatorService.psiphonFailureDetail("psiphon", "  "))

        val data = snapshot(1)
        invoke(data, "failed", 0, detail)
        invoke(data, "failed", 0, "Hop failed while starting")
        assertEquals("failed", blocks(data)[0]["state"])
        assertEquals(detail, blocks(data)[0]["detail"])
        assertEquals(detail, read(data)["error"])
    }
}
