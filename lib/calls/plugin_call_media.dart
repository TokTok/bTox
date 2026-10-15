import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:btox/calls/call_audio.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/calls/call_video.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox_call_media/btox_call_media.dart';
import 'package:flutter/widgets.dart';

/// The app's strings, in the system's language, where there's no UI to
/// take them from.
AppLocalizations systemL10n() => lookupAppLocalizations(
  basicLocaleListResolution(
    PlatformDispatcher.instance.locales,
    AppLocalizations.supportedLocales,
  ),
);

final class PluginCallAudio implements CallAudio {
  StreamSubscription<Uint8List>? _frames;
  StreamSubscription<(AudioRoute, Set<AudioRoute>)>? _routes;

  @override
  Future<void> start(
    void Function(Int16List frame) onFrame, {
    required bool speaker,
    required void Function(AudioRoute route, Set<AudioRoute> available)
    onRoutes,
    required void Function() onFailed,
  }) async {
    await _cancel();
    // Copied, as channels give bytes at any offset, which samples can't
    // be viewed at.
    _frames = BtoxCallMedia.instance.frames.listen(
      (bytes) => onFrame(Uint8List.fromList(bytes).buffer.asInt16List()),
      onError: (Object _) => onFailed(),
    );
    _routes = BtoxCallMedia.instance.routes.listen(
      (routes) => onRoutes(routes.$1, routes.$2),
    );
    final l10n = systemL10n();
    await BtoxCallMedia.instance.start(
      sampleRate: callSampleRate,
      frameSamples: callFrameSamples,
      speaker: speaker,
      title: l10n.callOngoing,
      channel: l10n.calls,
    );
  }

  @override
  void play(Int16List pcm, {required int channels, required int sampleRate}) {
    final mono = monoAt(pcm, channels, sampleRate);
    BtoxCallMedia.instance.play(Uint8List.sublistView(mono));
  }

  @override
  Future<void> setRoute(AudioRoute route) =>
      BtoxCallMedia.instance.setRoute(route);

  @override
  Future<void> setRingBack({required bool on}) =>
      BtoxCallMedia.instance.setRingBack(on: on);

  @override
  Future<void> setRinging({required bool on}) =>
      BtoxCallMedia.instance.setRinging(on: on);

  @override
  Future<void> stop() async {
    await _cancel();
    await BtoxCallMedia.instance.stop();
  }

  Future<void> _cancel() async {
    await _frames?.cancel();
    await _routes?.cancel();
    _frames = null;
    _routes = null;
  }
}

final class PluginCallVideo implements CallVideo {
  StreamSubscription<I420Frame>? _frames;

  @override
  Future<void> startCamera({
    required bool front,
    required void Function(I420Frame frame) onFrame,
    required void Function() onStopped,
  }) async {
    await _frames?.cancel();
    _frames = BtoxCallMedia.instance.cameraFrames.listen(
      onFrame,
      onError: (Object _) => onStopped(),
    );
    await BtoxCallMedia.instance.startCamera(front: front);
  }

  @override
  Future<void> stopCamera() async {
    await _frames?.cancel();
    _frames = null;
    await BtoxCallMedia.instance.stopCamera();
  }
}

/// [pcm] of [channels] at [sampleRate] as mono at [callSampleRate], which
/// is what toxav gives unless the friend sends something else.
Int16List monoAt(Int16List pcm, int channels, int sampleRate) {
  if (channels == 1 && sampleRate == callSampleRate) {
    return pcm;
  }
  final mono = Int16List(pcm.length ~/ channels * callSampleRate ~/ sampleRate);
  for (var i = 0; i < mono.length; i++) {
    final at = i * sampleRate ~/ callSampleRate * channels;
    var sum = 0;
    for (var c = 0; c < channels; c++) {
      sum += pcm[at + c];
    }
    mono[i] = sum ~/ channels;
  }
  return mono;
}
