package com.forwin.vpn.mix.sstp.extension


internal fun Short.toIntAsUShort(): Int {
    return this.toInt() and 0x0000FFFF
}
