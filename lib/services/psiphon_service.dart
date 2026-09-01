import 'package:flutter/services.dart';

class PsiphonService {
  static const MethodChannel _channel = MethodChannel('com.forwin.vpn/psiphon');

  Future<bool> prepare() async =>
      await _channel.invokeMethod<bool>('prepare') ?? false;

  Future<bool> start({String egressRegion = ''}) async {
    if (!await prepare()) return false;
    return await _channel.invokeMethod<bool>('start', {
          'egressRegion': egressRegion,
        }) ??
        false;
  }

  Future<bool> stop() async =>
      await _channel.invokeMethod<bool>('stop') ?? false;

  Future<bool> reconnect() async =>
      await _channel.invokeMethod<bool>('reconnect') ?? false;

  Future<bool> get isRunning async =>
      await _channel.invokeMethod<bool>('isRunning') ?? false;

  Future<bool> get isConnected async =>
      await _channel.invokeMethod<bool>('isConnected') ?? false;
}
