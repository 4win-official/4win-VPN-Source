import 'package:flutter/services.dart';

class PsiphonService {
  static const MethodChannel _channel = MethodChannel('com.forwin.vpn/psiphon');

  Future<bool> prepare() async {
    return await _channel.invokeMethod<bool>('prepare') ?? false;
  }

  Future<bool> start({String egressRegion = ''}) async {
    final prepared = await prepare();
    if (!prepared) return false;
    return await _channel.invokeMethod<bool>('start', {
          'egressRegion': egressRegion,
        }) ??
        false;
  }

  Future<bool> stop() async {
    return await _channel.invokeMethod<bool>('stop') ?? false;
  }

  Future<bool> reconnect() async {
    return await _channel.invokeMethod<bool>('reconnect') ?? false;
  }

  Future<bool> get isRunning async {
    return await _channel.invokeMethod<bool>('isRunning') ?? false;
  }
}
