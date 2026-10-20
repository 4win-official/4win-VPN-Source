package com.example.sstp_flutter;

import java.util.Locale;

/** Pure, session-local throughput sampler for monotonically increasing counters. */
public final class TrafficRateSampler {
    private long lastUploadBytes = -1L;
    private long lastDownloadBytes = -1L;
    private long lastElapsedRealtimeMillis = -1L;

    public synchronized String sample(long uploadBytes, long downloadBytes, long elapsedRealtimeMillis) {
        if (uploadBytes < 0 || downloadBytes < 0 || elapsedRealtimeMillis < 0) {
            reset();
            return null;
        }
        if (lastUploadBytes < 0) {
            lastUploadBytes = uploadBytes; lastDownloadBytes = downloadBytes;
            lastElapsedRealtimeMillis = elapsedRealtimeMillis;
            return null;
        }
        if (elapsedRealtimeMillis <= lastElapsedRealtimeMillis || uploadBytes < lastUploadBytes || downloadBytes < lastDownloadBytes) {
            // A reconnect/reset or clock anomaly must not leave a poisoned baseline.
            lastUploadBytes = uploadBytes;
            lastDownloadBytes = downloadBytes;
            lastElapsedRealtimeMillis = elapsedRealtimeMillis;
            return null;
        }
        long elapsed = elapsedRealtimeMillis - lastElapsedRealtimeMillis;
        double factor = 1000.0 / elapsed;
        String result = String.format(Locale.US, "Download: %s • Upload: %s", format(downloadBytes - lastDownloadBytes, factor), format(uploadBytes - lastUploadBytes, factor));
        lastUploadBytes = uploadBytes; lastDownloadBytes = downloadBytes; lastElapsedRealtimeMillis = elapsedRealtimeMillis;
        return result;
    }

    public synchronized void reset() {
        lastUploadBytes = -1L; lastDownloadBytes = -1L; lastElapsedRealtimeMillis = -1L;
    }

    private static String format(long bytes, double factor) {
        double speed = bytes * factor;
        final String[] units = {"B/s", "KB/s", "MB/s", "GB/s"};
        int unit = 0;
        while (speed >= 1024.0 && unit < units.length - 1) { speed /= 1024.0; unit++; }
        return String.format(Locale.US, "%.1f %s", speed, units[unit]);
    }
}
