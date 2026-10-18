package com.forwin.vpn.mix.sstp
/** Compatibility sink for upstream telemetry callbacks; Mix reports readiness through MixAdapter. */
internal class FlutterCaller { fun connect() {} fun connecting() {} suspend fun DownloadSpeed(download:Int,total:Int) {} suspend fun UploadSpeed(upload:Int,total:Int) {} }
