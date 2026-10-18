package com.forwin.vpn.mix.sstp.extension


internal fun Byte.toIntAsUByte(): Int {
    return this.toInt() and 0x000000FF
}
