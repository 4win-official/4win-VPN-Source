package com.forwin.vpn;

import android.app.Notification;
import android.app.PendingIntent;
import android.content.Intent;
import android.net.Uri;
import java.lang.reflect.Field;
import java.util.UUID;
import java.util.WeakHashMap;
import com.example.sstp_flutter.VpnConnectionObserver;
import de.blinkt.openvpn.core.ConnectionStatus;
import de.blinkt.openvpn.core.OpenVPNManagement;
import de.blinkt.openvpn.core.OpenVPNService;

/** Controls the pinned upstream service without reloading a selected/default profile. */
public final class OpenVpnNotificationActions {
    public static final String ACTION_RECONNECT = "com.forwin.vpn.openvpn.RECONNECT";
    private static final String ACTION_DISCONNECT = "com.forwin.vpn.openvpn.DISCONNECT";
    private static final String TOKEN = "notification_session";
    private static final WeakHashMap<OpenVPNService, Session> SESSIONS = new WeakHashMap<>();

    private static final class Session {
        final Object profile;
        final OpenVPNManagement management;
        String token = UUID.randomUUID().toString();
        boolean reconnecting;
        boolean sawRestart;
        Session(Object profile, OpenVPNManagement management) {
            this.profile = profile;
            this.management = management;
        }
    }

    private OpenVpnNotificationActions() {}

    private static boolean isMix(OpenVPNService service) {
        return service.getClass().getName().startsWith("com.forwin.vpn.mix.");
    }

    /** Called by the transformer at the beginning of the native engine-start method. */
    public static void onEngineStarting(OpenVPNService service) {
        if (isMix(service)) return;
        VpnConnectionObserver.notifyStarting(service);
    }

    private static Object field(OpenVPNService service, String name) {
        try {
            Field field = OpenVPNService.class.getDeclaredField(name);
            field.setAccessible(true);
            return field.get(service);
        } catch (ReflectiveOperationException ignored) {
            return null;
        }
    }

    /** Replaces upstream localized actions before Notification.Builder.build(). */
    public static boolean addActions(OpenVPNService service, Notification.Builder builder) {
        if (isMix(service)) return false;
        Object profile = field(service, "mProfile");
        OpenVPNManagement management = (OpenVPNManagement) field(service, "mManagement");
        final String token;
        synchronized (SESSIONS) {
            Session state = SESSIONS.get(service);
            if (state == null || state.profile != profile || state.management != management) {
                state = new Session(profile, management);
                SESSIONS.put(service, state);
            }
            token = state.token;
        }
        builder.addAction(android.R.drawable.ic_popup_sync, "Reconnect",
                pending(service, ACTION_RECONNECT, token));
        builder.addAction(android.R.drawable.ic_menu_close_clear_cancel, "Disconnect",
                pending(service, ACTION_DISCONNECT, token));
        return true;
    }

    private static PendingIntent pending(OpenVPNService service, String action, String token) {
        Intent intent = new Intent(service, service.getClass()).setAction(action)
                .setData(Uri.parse("forwin-openvpn://notification/" + token + "/" + action))
                .putExtra(TOKEN, token);
        return PendingIntent.getService(service, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /** True means the notification command was consumed, including stale/replayed commands. */
    public static boolean handleReconnect(OpenVPNService service, Intent intent) {
        if (isMix(service) || intent == null) return false;
        boolean reconnect = ACTION_RECONNECT.equals(intent.getAction());
        boolean disconnect = ACTION_DISCONNECT.equals(intent.getAction());
        if (!reconnect && !disconnect) {
            if (OpenVPNService.DISCONNECT_VPN.equals(intent.getAction()) ||
                    intent.hasExtra(service.getPackageName() + ".profileUUID") ||
                    intent.getAction() == null) invalidate(service);
            return false;
        }
        Session state;
        synchronized (SESSIONS) {
            state = SESSIONS.get(service);
            if (state == null || !state.token.equals(intent.getStringExtra(TOKEN)) ||
                    state.profile == null || state.profile != field(service, "mProfile") ||
                    state.management == null || state.management != field(service, "mManagement")) {
                return true;
            }
            if (reconnect) {
                if (state.reconnecting) return true;
                state.reconnecting = true;
                state.sawRestart = false;
                state.token = UUID.randomUUID().toString();
            } else SESSIONS.remove(service);
        }
        if (reconnect) {
            // The SDK sends SIGUSR1 and releases the management hold: it drops
            // and renegotiates the live connection with the very same native
            // profile, credentials and configuration. No prefs/profile lookup,
            // delayed task, new service, or protocol fallback can resurrect it.
            try {
                VpnConnectionObserver.notifyStarting(service);
                state.management.reconnect();
            } catch (RuntimeException failure) {
                synchronized (SESSIONS) { state.reconnecting = false; }
            }
        } else {
            VpnConnectionObserver.notifyState(service, false);
            VpnStateBroadcast.notifyDisconnected(service, "openvpn");
            try { service.stopVPN(false); } catch (android.os.RemoteException ignored) { }
        }
        return true;
    }

    /** Called on service status changes, not periodic notification refreshes. */
    public static void onState(OpenVPNService service, ConnectionStatus status) {
        if (!isMix(service)) {
            VpnConnectionObserver.notifyState(service, status == ConnectionStatus.LEVEL_CONNECTED);
        }
        synchronized (SESSIONS) {
            Session state = SESSIONS.get(service);
            if (state == null || !state.reconnecting) return;
            if (status != ConnectionStatus.LEVEL_CONNECTED) state.sawRestart = true;
            if ((status == ConnectionStatus.LEVEL_CONNECTED && state.sawRestart) ||
                    status == ConnectionStatus.LEVEL_AUTH_FAILED) state.reconnecting = false;
        }
    }

    public static void invalidate(OpenVPNService service) {
        if (!isMix(service)) VpnConnectionObserver.notifyState(service, false);
        synchronized (SESSIONS) { SESSIONS.remove(service); }
    }

    /** True while an accepted notification reconnect is in progress. */
    public static boolean isReconnecting() {
        synchronized (SESSIONS) {
            for (Session state : SESSIONS.values()) {
                if (state != null && state.reconnecting) return true;
            }
            return false;
        }
    }
}
