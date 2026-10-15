import 'package:btox_call_media/btox_call_media.dart';
import 'package:flutter/services.dart';

/// Call audio and video on Android, through the plugin's Kotlin.
final class ChannelCallMedia implements BtoxCallMedia {
  static const _methods = MethodChannel('btox_call_media');
  static const _frames = EventChannel('btox_call_media/frames');
  static const _routes = EventChannel('btox_call_media/routes');
  static const _camera = EventChannel('btox_call_media/camera');
  static const _playback = BasicMessageChannel<ByteData>(
    'btox_call_media/play',
    BinaryCodec(),
  );

  @override
  Stream<Uint8List> get frames =>
      _frames.receiveBroadcastStream().cast<Uint8List>();

  @override
  Stream<(AudioRoute, Set<AudioRoute>)> get routes =>
      _routes.receiveBroadcastStream().map(
        (routes) => switch (routes) {
          [int route, List<Object?> available] => (
            AudioRoute.values[route],
            {for (final r in available.cast<int>()) AudioRoute.values[r]},
          ),
          _ => throw FormatException('Not audio routes: $routes'),
        },
      );

  @override
  Future<void> start({
    required int sampleRate,
    required int frameSamples,
    required bool speaker,
    required String title,
    required String channel,
  }) => _methods.invokeMethod('start', {
    'sampleRate': sampleRate,
    'frameSamples': frameSamples,
    'speaker': speaker,
    'title': title,
    'channel': channel,
  });

  @override
  void play(Uint8List pcm) => _playback.send(ByteData.sublistView(pcm));

  @override
  Future<void> setRoute(AudioRoute route) =>
      _methods.invokeMethod('setRoute', {'route': route.index});

  @override
  Future<void> setRingBack({required bool on}) =>
      _methods.invokeMethod('setRingBack', {'on': on});

  @override
  Future<void> setRinging({required bool on}) =>
      _methods.invokeMethod('setRinging', {'on': on});

  @override
  Future<void> stop() => _methods.invokeMethod('stop');

  @override
  Stream<I420Frame> get cameraFrames => _camera.receiveBroadcastStream().map(
    (frame) => switch (frame) {
      [int width, int height, Uint8List data] => I420Frame(width, height, data),
      _ => throw FormatException('Not a frame: $frame'),
    },
  );

  @override
  Future<void> startCamera({required bool front}) =>
      _methods.invokeMethod('startCamera', {'front': front});

  @override
  Future<void> stopCamera() => _methods.invokeMethod('stopCamera');

  @override
  Future<bool> requestPermissions({required bool camera}) async =>
      await _methods.invokeMethod<bool>('requestPermissions', {
        'camera': camera,
      }) ??
      false;

  @override
  Future<bool> canRingOverLockScreen() async =>
      await _methods.invokeMethod<bool>('canRingOverLockScreen') ?? false;

  @override
  Future<void> allowRingingOverLockScreen() =>
      _methods.invokeMethod('allowRingingOverLockScreen');

  @override
  Future<void> showOverLockScreen({required bool on}) =>
      _methods.invokeMethod('showOverLockScreen', {'on': on});
}
