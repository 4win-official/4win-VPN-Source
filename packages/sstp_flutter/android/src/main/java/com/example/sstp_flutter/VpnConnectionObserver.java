package com.example.sstp_flutter;

import android.content.Context;

/** Receives best-effort notifications from native VPN services. */
public interface VpnConnectionObserver {
    void onVpnConnectionStarting(Context source);

    void onVpnConnectionStateChanged(Context source, boolean connected);

    /** Notify the application observer without allowing observer failures to affect VPN startup. */
    static void notifyStarting(Context context) {
        if (context == null) return;
        try {
            Context application = context.getApplicationContext();
            if (application instanceof VpnConnectionObserver) {
                try {
                    ((VpnConnectionObserver) application).onVpnConnectionStarting(context);
                } catch (RuntimeException ignored) {
                    // Observing startup is best effort and must never break the VPN.
                }
            }
        } catch (RuntimeException ignored) {
            // Some test/proxy Context implementations can fail while resolving the app context.
        }
    }

    /** Notify the application observer of a real native connection state change. */
    static void notifyState(Context context, boolean connected) {
        if (context == null) return;
        try {
            Context application = context.getApplicationContext();
            if (application instanceof VpnConnectionObserver) {
                try {
                    ((VpnConnectionObserver) application).onVpnConnectionStateChanged(context, connected);
                } catch (RuntimeException ignored) {
                    // Observing state is best effort and must never break the VPN.
                }
            }
        } catch (RuntimeException ignored) {
            // Some test/proxy Context implementations can fail while resolving the app context.
        }
    }
}
