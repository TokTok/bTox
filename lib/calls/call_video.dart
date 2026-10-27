import 'package:btox/calls/call_protocol.dart';

enum VideoView { local, remote }

abstract interface class CallVideo {
  /// Once the call's audio started. [onStopped] is for when it stops by
  /// itself, as when another app takes it.
  Future<void> startCamera({
    required bool front,
    required void Function(I420Frame frame) onFrame,
    required void Function() onStopped,
  });

  Future<void> stopCamera();
}
