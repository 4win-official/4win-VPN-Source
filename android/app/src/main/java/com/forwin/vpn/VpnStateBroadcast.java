package com.forwin.vpn;

import android.content.Context;
import android.content.Intent;

/** Native-to-Flutter lifecycle events; broadcasts stay inside this application package. */
public final class VpnStateBroadcast {
    public static final String ACTION_DISCONNECTED = "com.forwin.vpn.VPN_DISCONNECTED";
    public static final String EXTRA_PROTOCOL = "protocol";

    private VpnStateBroadcast() { }

    public static void notifyDisconnected(Context context, String protocol) {
        if (context == null || protocol == null || protocol.isEmpty()) return;
        Intent intent = new Intent(ACTION_DISCONNECTED)
                .setPackage(context.getPackageName())
                .putExtra(EXTRA_PROTOCOL, protocol);
        context.sendBroadcast(intent);
    }
}
