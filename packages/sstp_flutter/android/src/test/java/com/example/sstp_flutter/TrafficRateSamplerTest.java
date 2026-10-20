package com.example.sstp_flutter;

import static org.junit.Assert.*;
import org.junit.Test;

public class TrafficRateSamplerTest {
    @Test public void baselineAndRatesUseBinaryUnits() {
        TrafficRateSampler sampler = new TrafficRateSampler();
        assertNull(sampler.sample(0, 0, 1000));
        assertEquals("Download: 1.0 KB/s • Upload: 2.0 KB/s", sampler.sample(2048, 1024, 2000));
    }
    @Test public void resetStartsNewBaseline() {
        TrafficRateSampler sampler = new TrafficRateSampler();
        assertNull(sampler.sample(10, 20, 1));
        sampler.reset();
        assertNull(sampler.sample(0, 0, 2));
    }
    @Test public void invalidSamplesDoNotFabricateRates() {
        TrafficRateSampler sampler = new TrafficRateSampler();
        assertNull(sampler.sample(1, 1, 10));
        assertNull(sampler.sample(-1, 2, 20));
        assertNull(sampler.sample(2, 0, 20));
        assertNull(sampler.sample(2, 0, 19));
    }

    @Test public void invalidSampleResetsBaselineAndLaterSamplesRecover() {
        TrafficRateSampler sampler = new TrafficRateSampler();
        assertNull(sampler.sample(100, 100, 10));
        assertNull(sampler.sample(-1, 100, 20));
        assertNull(sampler.sample(200, 200, 30));
        assertEquals("Download: 1.0 KB/s • Upload: 1.0 KB/s", sampler.sample(1224, 1224, 1030));
    }

    @Test public void regressiveSampleRebaselinesAndLaterSamplesRecover() {
        TrafficRateSampler sampler = new TrafficRateSampler();
        assertNull(sampler.sample(1000, 1000, 10));
        assertNull(sampler.sample(500, 500, 20));
        assertEquals("Download: 97.7 KB/s • Upload: 97.7 KB/s", sampler.sample(1500, 1500, 30));
        assertEquals("Download: 1.0 KB/s • Upload: 1.0 KB/s", sampler.sample(2524, 2524, 1030));
    }
}
