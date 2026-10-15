import 'package:btox/calls/call_protocol.dart';

/// The video a call shows: the camera's, and the friend's.
enum VideoView { local, remote }

/// The camera during a call.
abstract interface class CallVideo {
  /// Once the call's audio started, starts the front or back camera.
  /// [onFrame] gets each frame, as `CallProtocol.sendVideo` takes it, and
  /// [onStopped] when it stops by itself, as when another app takes it.
  Future<void> startCamera({
    required bool front,
    required void Function(I420Frame frame) onFrame,
    required void Function() onStopped,
  });

  Future<void> stopCamera();
}
