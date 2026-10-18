package com.forwin.vpn.mix.sstp.extension

import android.net.Uri
import java.net.URI


internal fun sum(vararg words: String): String {
    var result = ""

    words.forEach {
        result += it
    }

    return result
}

internal fun String.toUri(): Uri? {
    if (isEmpty()) return null
    return runCatching {
        val parsed = URI(this)
        require(!parsed.isOpaque || !parsed.scheme.isNullOrBlank())
        require(!parsed.scheme.isNullOrBlank())
        Uri.parse(this)
    }.getOrNull()
}
