import 'package:flutter/foundation.dart';

final _frame = RegExp(r'packages?[:/]([^ :]+)[: ](\d+):(\d+)');

String _callerFileLine() {
  final stack = FlutterError.demangleStackTrace(StackTrace.current);
  for (final line in stack.toString().split('\n')) {
    final m = _frame.firstMatch(line);
    if (m != null && !m[1]!.contains('logger.dart')) {
      return '${m[1]}:${m[2]}:${m[3]}';
    }
  }
  return '<unknown file>';
}

final class Logger {
  final List<String> tags;

  const Logger(this.tags);

  void d(String text, [StackTrace? stackTrace]) => _log('D', text, stackTrace);
  void e(String text, [StackTrace? stackTrace]) => _log('E', text, stackTrace);
  void i(String text, [StackTrace? stackTrace]) => _log('I', text, stackTrace);
  void v(String text, [StackTrace? stackTrace]) {
    if (kIsWeb) _log('V', text, stackTrace);
  }

  void w(String text, [StackTrace? stackTrace]) => _log('W', text, stackTrace);

  /// Lets [future] run without waiting for it, logging if it fails to [what].
  void unawaited(String what, Future<void> future) {
    future.catchError((Object e) => this.e('Failed to $what: $e'));
  }

  void _log(String level, String text, StackTrace? stackTrace) {
    final line = '${_callerFileLine()}: $level $tags $text';
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace, label: line);
    } else {
      debugPrint(line);
    }
  }
}
