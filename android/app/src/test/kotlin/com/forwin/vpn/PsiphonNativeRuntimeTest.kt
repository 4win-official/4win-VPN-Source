package com.forwin.vpn

import org.junit.Assert.assertTrue
import org.junit.Test

class PsiphonNativeRuntimeTest {
    @Test
    fun diagnosticIncludesExceptionTypeAndUnderlyingNativeCause() {
        val error = IllegalStateException(
            "bridge initialization failed",
            UnsatisfiedLinkError("native library not found"),
        )

        val diagnostic = PsiphonNativeRuntime.describe(error)

        assertTrue(diagnostic.contains("IllegalStateException: bridge initialization failed"))
        assertTrue(diagnostic.contains("UnsatisfiedLinkError: native library not found"))
    }
}
