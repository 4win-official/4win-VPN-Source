package com.forwin.vpn.mix

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class MixEgressProbeTest {
    @Test fun parsesActualIpv4EgressAndWarpStatus() {
        val trace = MixEgressProbe.parseTrace("ip=104.16.132.229\nwarp=on\ncolo=AMS\n")
        assertEquals("104.16.132.229", trace.ip)
        assertEquals("on", trace.warp)
        MixEgressProbe.requireWarpOn(trace.warp, trace.ip)
    }

    @Test fun acceptsGloballyRoutableIpv6Egress() {
        val trace = MixEgressProbe.parseTrace("ip=2606:4700:4700::1111\nwarp=on\n")
        assertEquals("2606:4700:4700::1111", trace.ip)
    }

    @Test fun rejectsPrivateMalformedAndMissingEgressAddresses() {
        for (ip in listOf("10.0.0.1", "100.64.0.1", "192.0.2.1", "not-an-ip", "")) {
            assertThrows(IllegalArgumentException::class.java) {
                MixEgressProbe.parseTrace("ip=$ip\nwarp=on\n")
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            MixEgressProbe.parseTrace("warp=on\n")
        }
    }

    @Test fun refusesToMarkReachableWarpWhenTraceSaysOffOrOmitsStatus() {
        val off = MixEgressProbe.parseTrace("ip=104.16.132.229\nwarp=off\n")
        assertThrows(IllegalStateException::class.java) { MixEgressProbe.requireWarpOn(off.warp, off.ip) }
        val missing = MixEgressProbe.parseTrace("ip=104.16.132.229\n")
        assertThrows(IllegalStateException::class.java) { MixEgressProbe.requireWarpOn(missing.warp, missing.ip) }
    }
}
