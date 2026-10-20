/// An error raised while configuring one block in an ordered Mix strategy.
///
/// [index] is the block's zero-based position in the configured strategy,
/// including DNS blocks and repeated references.
class MixBlockException extends FormatException {
  MixBlockException(this.index, Object error, {this.stackTrace})
    : cause = error,
      super(_safeMessage(error));

  /// The zero-based index of the configured block that failed.
  final int index;

  /// Alias useful to callers that refer to strategy entries as hops.
  int get hopIndex => index;

  /// Alias for code that names strategy entries as blocks.
  int get blockIndex => index;

  /// The original exception or error, when callers need to inspect it.
  final Object cause;

  /// The original stack trace, if one was available.
  final StackTrace? stackTrace;

  static String _safeMessage(Object error) {
    try {
      if (error is FormatException) {
        final formatMessage = error.message;
        return formatMessage.toString();
      }
      final text = error.toString();
      return text.isEmpty ? 'Unknown Mix block error.' : text;
    } catch (_) {
      return 'Unknown Mix block error.';
    }
  }

  @override
  String toString() => 'Mix block ${index + 1} failed: $message';
}
