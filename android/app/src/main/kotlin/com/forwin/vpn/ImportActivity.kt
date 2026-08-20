package com.forwin.vpn

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns

/**
 * Lightweight trampoline that receives .ovpn / .open file VIEW & SEND intents
 * from OTHER apps (Telegram, file managers, email, the OpenVPN app, …).
 *
 * Why a separate activity instead of pointing the file intent-filters straight
 * at MainActivity: when another app fires a VIEW/SEND intent WITHOUT
 * FLAG_ACTIVITY_NEW_TASK, Android places the target on top of the CALLER's
 * task. If that target were MainActivity (a FlutterActivity) the app would
 * appear embedded inside the caller (e.g. Telegram) and the mixed task could
 * crash. ImportActivity has NO Flutter engine, so it is safe to land on a
 * foreign task; it opens MainActivity in 4win VPN's own task and finishes.
 *
 * IMPORTANT: the temporary read permission the caller grants for a content://
 * Uri is tied to THIS activity and does NOT reliably survive being forwarded to
 * MainActivity (which caused a SecurityException / crash while importing). So we
 * read the file HERE — where we definitely have permission — and pass the
 * config as plain-text extras. MainActivity then needs no Uri permission at all.
 */
class ImportActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val forward = Intent(this, MainActivity::class.java)
            forward.addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            )

            val uri = extractUri(intent)
            if (uri != null) {
                val content = readUriText(uri)
                if (content != null) {
                    forward.putExtra(EXTRA_OVPN_CONTENT, content)
                    forward.putExtra(EXTRA_OVPN_NAME, guessName(uri))
                }
            }
            startActivity(forward)
        } catch (e: Exception) {
            android.util.Log.e("ImportActivity", "forward failed: ${e.message}", e)
            // Still try to at least open the app.
            try {
                startActivity(
                    Intent(this, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Exception) {}
        }
        finish()
    }

    private fun extractUri(incoming: Intent?): Uri? {
        if (incoming == null) return null
        return when (incoming.action) {
            Intent.ACTION_VIEW -> incoming.data
            Intent.ACTION_SEND -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    incoming.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    incoming.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                }
            }
            else -> null
        }
    }

    private fun readUriText(uri: Uri): String? {
        return try {
            when (uri.scheme) {
                "content" -> contentResolver.openInputStream(uri)?.use {
                    it.readBytes().toString(Charsets.UTF_8)
                }
                "file" -> uri.path?.let { java.io.File(it).readText(Charsets.UTF_8) }
                else -> null
            }
        } catch (e: Exception) {
            android.util.Log.e("ImportActivity", "readUriText failed: ${e.message}")
            null
        }
    }

    private fun guessName(uri: Uri): String {
        var name = "Imported"
        try {
            if (uri.scheme == "content") {
                contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0 && cursor.moveToFirst()) {
                        name = cursor.getString(idx) ?: name
                    }
                }
            } else {
                name = uri.lastPathSegment ?: name
            }
        } catch (_: Exception) {}
        return name.substringBeforeLast('.').ifBlank { "Imported" }
    }

    companion object {
        const val EXTRA_OVPN_CONTENT = "com.forwin.vpn.OVPN_CONTENT"
        const val EXTRA_OVPN_NAME = "com.forwin.vpn.OVPN_NAME"
    }
}
