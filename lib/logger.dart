import 'dart:math';

import 'package:clock/clock.dart';
import 'package:circular_buffer/circular_buffer.dart';
import 'package:flutter/foundation.dart';

class _StackFrame {
  final String file;
  final int line;
  final int column;

  const _StackFrame(this.file, this.line, this.column);

  @override
  String toString() => '$file:$line:$column';

  static _StackFrame? fromString(String frame) {
    final match = RegExp(r'packages?[:/]([^ :]+)[: ](\d+):(\d+)')
        .firstMatch(frame);
    if (match == null) return null;
    return _StackFrame(
      match.group(1)!,
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }
}

String _callerFileLine() {
  final stack = FlutterError.demangleStackTrace(StackTrace.current)
      .toString()
      .split('\n')
      .map(_StackFrame.fromString)
      .whereType<_StackFrame>()
      .where((frame) => !frame.file.contains('logger.dart'));
  return stack.isEmpty ? '<unknown file>' : stack.first.toString();
}

final class Logger {
  static const _bufferSize = 1000;
  static final CircularBuffer<LogLine> _log = CircularBuffer(_bufferSize);
  static bool verbose = kIsWeb;

  static List<LogLine> get log => List.unmodifiable(_log);

  final List<String> tags;

  const Logger(this.tags);

  void d(String text, [StackTrace? stackTrace]) =>
      _logLine(LogLevel.debug, text, stackTrace);

  void e(String text, [StackTrace? stackTrace]) =>
      _logLine(LogLevel.error, text, stackTrace);
  void i(String text, [StackTrace? stackTrace]) =>
      _logLine(LogLevel.info, text, stackTrace);
  void logError(Error e, [String? message]) {
    debugPrintStack(
      stackTrace: e.stackTrace,
      label: message != null ? '$tags $message ($e)' : tags.toString(),
    );
    _log.add(
      LogLine(
        clock.now(),
        LogLevel.warning,
        tags,
        '$message ($e)',
        e.stackTrace,
      ),
    );
  }

  void v(String text, [StackTrace? stackTrace]) =>
      _logLine(LogLevel.verbose, text, stackTrace);
  void w(String text, [StackTrace? stackTrace]) =>
      _logLine(LogLevel.warning, text, stackTrace);

  void _logLine(LogLevel level, String text, [StackTrace? stackTrace]) {
    if (level == LogLevel.verbose && !verbose) return;
    final line =
        '${_callerFileLine()}: ${level.name[0].toUpperCase()} $tags $text';
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace, label: line);
      _log.add(LogLine(clock.now(), level, tags, text, stackTrace));
    } else {
      debugPrint(line);
      _log.add(LogLine(clock.now(), level, tags, text));
    }
  }

  T Function(A) catching<T, A>(T Function(A) f) {
    return (A a) {
      try {
        v(
          'Calling $f with ${a.toString().substring(0, min(20, a.toString().length))}',
        );
        return f(a);
      } catch (exn, stackTrace) {
        e('Caught exception $exn', stackTrace);
        rethrow;
      }
    };
  }
}

enum LogLevel { verbose, debug, info, warning, error }

final class LogLine {
  final DateTime timestamp;
  final LogLevel level;
  final List<String> tags;
  final String message;
  final StackTrace? stackTrace;

  const LogLine(
    this.timestamp,
    this.level,
    this.tags,
    this.message, [
    this.stackTrace,
  ]);
}
