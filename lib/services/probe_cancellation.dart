import 'dart:async';
import 'dart:io';

/// Signals that a temporary server-reachability probe should stop.
class ProbeCancellation {
  bool _isCancelled = false;
  final Completer<void> _cancelled = Completer<void>();
  final Set<void Function()> _callbacks = <void Function()>{};

  bool get isCancelled => _isCancelled;
  Future<void> get whenCancelled => _cancelled.future;

  /// Register cleanup (for example closing a socket). Returns an unregister
  /// callback so completed probes do not stay attached to the token.
  void Function() onCancel(void Function() callback) {
    if (_isCancelled) {
      callback();
      return () {};
    }
    _callbacks.add(callback);
    return () => _callbacks.remove(callback);
  }

  /// A child token is canceled when its parent bulk run is stopped, while it
  /// can still be canceled on its own from an individual row.
  ProbeCancellation linkedTo(ProbeCancellation parent) {
    final child = ProbeCancellation();
    final removeParentListener = parent.onCancel(child.cancel);
    child.onCancel(removeParentListener);
    return child;
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    if (!_cancelled.isCompleted) _cancelled.complete();
    final callbacks = List<void Function()>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      try {
        callback();
      } catch (_) {
        // Cancellation is best-effort; one cleanup failure must not block the rest.
      }
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) throw const ProbeCancelled();
  }
}

class ProbeCancelled implements Exception {
  const ProbeCancelled();
}

/// Opens a TCP connection that can be aborted while the handshake is pending.
Future<Socket> connectProbeSocket(
  String address,
  int port, {
  required ProbeCancellation cancellation,
  required Duration timeout,
}) async {
  cancellation.throwIfCancelled();
  final task = await Future.any<ConnectionTask<Socket>>([
    Socket.startConnect(address, port).then((task) {
      if (cancellation.isCancelled) task.cancel();
      return task;
    }),
    cancellation.whenCancelled.then((_) => throw const ProbeCancelled()),
  ]);
  final unregister = cancellation.onCancel(task.cancel);
  try {
    final socket = await task.socket.timeout(
      timeout,
      onTimeout: () {
        task.cancel();
        throw TimeoutException('TCP probe timed out', timeout);
      },
    );
    if (cancellation.isCancelled) {
      socket.destroy();
      throw const ProbeCancelled();
    }
    return socket;
  } finally {
    unregister();
  }
}
