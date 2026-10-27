import 'dart:math';
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_api.dart';
import 'package:btox/api/toxcore/tox_av.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/ffi/toxcore.dart'
    show Toxav_Call_Control, Toxav_Friend_Call_State;
import 'package:btox/logger.dart';
import 'package:btox/models/crypto.dart';
import 'package:clock/clock.dart';

const _logger = Logger(['ToxavProtocol']);

/// Opus at 48 kbit/s, plenty for voice.
const _audioBitRate = 48;

/// VP8 in kbit/s: where video starts and the most it goes up to, and the
/// least toxav's loss reports take it down to.
const _videoBitRate = 1000;
const _maxVideoBitRate = 1500;
const _minVideoBitRate = 150;

/// Without loss reports for this long, the video bit rate goes up a tenth.
const _videoBitRateStep = Duration(seconds: 5);

/// The biggest frame shown, as 4K: a friend can send more than a phone can
/// take.
const _maxVideoPixels = 3840 * 2160;

final _failed = Toxav_Friend_Call_State.TOXAV_FRIEND_CALL_STATE_ERROR.value;
final _ended =
    _failed | Toxav_Friend_Call_State.TOXAV_FRIEND_CALL_STATE_FINISHED.value;
final _sendingVideo =
    Toxav_Friend_Call_State.TOXAV_FRIEND_CALL_STATE_SENDING_V.value;

final class ToxavProtocol implements CallProtocol {
  final ToxAv _av;
  final int? Function(PublicKey friend) _numberOf;
  final PublicKey? Function(int friendNumber) _keyOf;
  final _answered = <int>{};
  final _friendVideo = <int>{};
  // What we send video at, and since when, to friends we send it to.
  final _videoBitRates = <int, (int, DateTime)>{};

  ToxavProtocol(this._av, this._numberOf, this._keyOf);

  @override
  bool get ringsElsewhere => false;

  @override
  List<CallSignal> poll() {
    _raiseVideoBitRates();
    final signals = <CallSignal>[];
    for (final event in _av.iterate()) {
      switch ((_keyOf(event.friendNumber), event)) {
        case (final friend?, _):
          signals.addAll(_signals(event, friend));
        // From no one this protocol calls with, as a linked account's home
        // device while no call goes through it.
        case (null, ToxAvEventCall(:final friendNumber)):
          _cancel(friendNumber);
        case (null, _):
          break;
      }
    }
    return signals;
  }

  Iterable<CallSignal> _signals(AvEvent event, PublicKey friend) sync* {
    switch (event) {
      case ToxAvEventCall(:final friendNumber, :final videoEnabled):
        yield CallSignal.ringing(friend, video: videoEnabled);
        // No call state tells it while it rings.
        if (videoEnabled) {
          _friendVideo.add(friendNumber);
          yield CallSignal.friendVideo(friend, on: true);
        }
      case ToxAvEventCallState(:final friendNumber, :final state)
          when state & _ended != 0:
        yield _finished(friendNumber, friend, failed: state & _failed != 0);
      case ToxAvEventCallState(:final friendNumber, :final state):
        if (_answered.add(friendNumber)) {
          yield CallSignal.answered(friend);
        }
        final video = state & _sendingVideo != 0;
        if (video != _friendVideo.contains(friendNumber)) {
          video
              ? _friendVideo.add(friendNumber)
              : _friendVideo.remove(friendNumber);
          yield CallSignal.friendVideo(friend, on: video);
        }
      case ToxAvEventAudioReceiveFrame(
        :final pcm,
        :final channels,
        :final samplingRate,
      ):
        yield CallSignal.audio(
          friend,
          pcm,
          channels: channels,
          sampleRate: samplingRate,
        );
      case ToxAvEventVideoReceiveFrame(:final width, :final height)
          when width * height <= _maxVideoPixels:
        yield CallSignal.video(friend, _packed(event));
      case ToxAvEventVideoBitRate(:final friendNumber, :final videoBitRate)
          when _videoBitRates.containsKey(friendNumber):
        _setVideoBitRate(
          friendNumber,
          videoBitRate.clamp(_minVideoBitRate, _maxVideoBitRate),
        );
      default:
        break;
    }
  }

  static I420Frame _packed(ToxAvEventVideoReceiveFrame frame) {
    final packed = I420Frame(
      frame.width,
      frame.height,
      Uint8List(I420Frame.size(frame.width, frame.height)),
    );
    for (final (from, stride, to, width) in [
      (frame.y, frame.ystride, packed.y, packed.width),
      (frame.u, frame.ustride, packed.u, packed.chromaWidth),
      (frame.v, frame.vstride, packed.v, packed.chromaWidth),
    ]) {
      for (var row = 0; row < to.length ~/ width; row++) {
        to.setRange(row * width, (row + 1) * width, from, row * stride.abs());
      }
    }
    return packed;
  }

  void _raiseVideoBitRates() {
    final now = clock.now();
    for (final MapEntry(key: number, value: (rate, since))
        in _videoBitRates.entries.toList()) {
      if (_answered.contains(number) &&
          rate < _maxVideoBitRate &&
          now.difference(since) >= _videoBitRateStep) {
        _setVideoBitRate(number, min(_maxVideoBitRate, rate * 11 ~/ 10));
      }
    }
  }

  void _setVideoBitRate(int number, int rate) {
    try {
      _av.videoSetBitRate(number, rate);
      if (rate == 0) {
        _videoBitRates.remove(number);
      } else {
        _videoBitRates[number] = (rate, clock.now());
      }
    } on ApiException catch (e) {
      _logger.w('Setting friend $number\'s video bit rate to $rate: $e');
    }
  }

  CallSignal _finished(
    int friendNumber,
    PublicKey friend, {
    required bool failed,
  }) {
    _answered.remove(friendNumber);
    _friendVideo.remove(friendNumber);
    _videoBitRates.remove(friendNumber);
    return CallSignal.finished(friend, failed: failed);
  }

  @override
  Duration get interval => Duration(milliseconds: _av.iterationInterval());

  @override
  bool call(PublicKey friend, {required bool video}) {
    final number = _number(friend);
    try {
      _av.call(number, _audioBitRate, video ? _videoBitRate : 0);
    } on ApiException catch (e) {
      // Such as a friend gone offline just now.
      _logger.w('Calling friend $number: $e');
      return false;
    }
    if (video) {
      _videoBitRates[number] = (_videoBitRate, clock.now());
    }
    return true;
  }

  @override
  void answer(PublicKey friend, {required bool video}) {
    final number = _number(friend);
    _av.answer(number, _audioBitRate, video ? _videoBitRate : 0);
    _answered.add(number);
    if (video) {
      _videoBitRates[number] = (_videoBitRate, clock.now());
    }
  }

  @override
  void hangUp(PublicKey friend) {
    // A friend deleted mid-call took their call with them.
    final number = _numberOf(friend);
    if (number == null) {
      return;
    }
    _answered.remove(number);
    _friendVideo.remove(number);
    _videoBitRates.remove(number);
    _cancel(number);
  }

  void _cancel(int number) {
    try {
      _av.callControl(number, Toxav_Call_Control.TOXAV_CALL_CONTROL_CANCEL);
    } on ApiException catch (e) {
      // Already over at the other end.
      _logger.d('Hanging up on friend $number: $e');
    }
  }

  @override
  void sendAudio(PublicKey friend, Int16List pcm) {
    try {
      _av.audioSendFrame(_number(friend), pcm, pcm.length, 1, callSampleRate);
    } on ApiException catch (e) {
      // Such as while the friend's capabilities catch up.
      _logger.d('Sending audio to $friend: $e');
    }
  }

  @override
  void setVideo(PublicKey friend, {required bool on}) {
    final number = _number(friend);
    if (on != _videoBitRates.containsKey(number)) {
      _setVideoBitRate(number, on ? _videoBitRate : 0);
    }
  }

  @override
  void sendVideo(PublicKey friend, I420Frame frame) {
    try {
      _av.videoSendFrame(
        _number(friend),
        frame.width,
        frame.height,
        frame.y,
        frame.u,
        frame.v,
      );
    } on ApiException catch (e) {
      // Such as while the friend's capabilities catch up.
      _logger.d('Sending video to $friend: $e');
    }
  }

  int _number(PublicKey friend) =>
      _numberOf(friend) ?? (throw StateError('Not a friend: $friend'));
}
