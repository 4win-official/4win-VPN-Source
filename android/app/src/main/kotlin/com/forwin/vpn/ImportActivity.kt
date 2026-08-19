package com.forwin.vpn

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * Lightweight trampoline that receives .ovpn / .open file VIEW & SEND intents
 * from OTHER apps (Telegram, file managers, email, the OpenVPN app, …).
 *
 * Why a separate activity instead of pointing the file intent-filters straight
 * at MainActivity:
 *
 * When another app fires a VIEW/SEND intent WITHOUT FLAG_ACTIVITY_NEW_TASK,
 * Android places the *target* activity on top of the CALLER's task. If that
 * target were MainActivity (a full FlutterActivity), 4win VPN would appear
 * embedded INSIDE the caller (e.g. Telegram), "back" would return to the
 * caller, and the mixed task occasionally crashed the Flutter engine.
 *
 * ImportActivity carries NO Flutter engine — it is nearly free to create even
 * when it lands on a foreign task. All it does is immediately relaunch
 * MainActivity in 4win VPN's OWN task (via taskAffinity + FLAG_ACTIVITY_NEW_TASK),
 * hand over the original file intent, and finish itself. The result: the app
 * ALWAYS opens standalone in its own window, exactly like the official app.
 */
class ImportActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val forward = Intent(intent)
            forward.setClass(this, MainActivity::class.java)
            // NEW_TASK → start (or move to front) MainActivity's own task, which
            // is pinned by android:taskAffinity="com.forwin.vpn"; SINGLE_TOP +
            // CLEAR_TOP → reuse the existing MainActivity instance if it's
            // already running instead of stacking a second copy.
            forward.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    // Pass on read access so MainActivity can open the content://
                    // Uri the caller granted us (Telegram etc. use content Uris).
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
            startActivity(forward)
        } catch (e: Exception) {
            android.util.Log.e("ImportActivity", "forward failed: ${e.message}", e)
        }
        // Never keep this trampoline on screen or in the back stack.
        finish()
    }
}
