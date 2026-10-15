import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_av.dart';
import 'package:btox/ffi/toxcore.dart' show Toxav_Call_Control;

/// Records what's asked of toxav, and gives the events queued for it.
final class FakeToxAv extends ToxAv {
  final events = <AvEvent>[];

  /// (friend number, audio bit rate), for calls and answers.
  final calls = <(int, int)>[];
  final answers = <(int, int)>[];
  final controls = <(int, Toxav_Call_Control)>[];
  final frames = <(int, Int16List)>[];
  final videoBitRates = <(int, int)>[];

  @override
  List<AvEvent> iterate() {
    final iterated = [...events];
    events.clear();
    return iterated;
  }

  @override
  int iterationInterval() => 20;

  @override
  void call(int friendNumber, int audioBitRate, int videoBitRate) =>
      calls.add((friendNumber, audioBitRate));

  @override
  void answer(int friendNumber, int audioBitRate, int videoBitRate) =>
      answers.add((friendNumber, audioBitRate));

  @override
  void callControl(int friendNumber, Toxav_Call_Control control) =>
      controls.add((friendNumber, control));

  @override
  void audioSendFrame(
    int friendNumber,
    Int16List pcm,
    int sampleCount,
    int channels,
    int samplingRate,
  ) => frames.add((friendNumber, pcm));

  @override
  void videoSetBitRate(int friendNumber, int bitRate) =>
      videoBitRates.add((friendNumber, bitRate));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
