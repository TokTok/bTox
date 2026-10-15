import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_av.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/calls/toxav_protocol.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/sync/fact.dart';
import 'package:btox/sync/session_message.dart';
import 'package:clock/clock.dart';

/// How long the home device has to connect a call answered here.
const _connectTimeout = Duration(seconds: 30);

/// The calls of a linked account. Its home device takes the friends' calls,
/// and says which ring as facts. When this device answers or places one, the
/// home device connects it with a toxav call of its own, which carries the
/// friend's audio and video.
final class RelayProtocol implements CallProtocol {
  final int? Function() _homeNumber;
  final void Function(SessionMessage message) _toHome;
  late final ToxavProtocol _home;
  // The friend whose call goes through the home device's call, if any.
  PublicKey? _friend;
  // With video or not, once this device asked to be connected.
  bool? _connecting;
  // When the home device should have connected the call answered here.
  DateTime? _connectBy;
  // What the home device says of each friend's call.
  final _states = <PublicKey, CallState>{};
  final _signals = <CallSignal>[];

  RelayProtocol(
    ToxAv av, {
    required int? Function() homeNumber,
    required void Function(SessionMessage message) toHome,
  }) : _homeNumber = homeNumber,
       _toHome = toHome {
    _home = ToxavProtocol(
      av,
      (friend) => friend == _friend ? homeNumber() : null,
      (number) => number == homeNumber() ? _friend : null,
    );
  }

  /// Live facts from the home device: with [all], every one there is, as
  /// none when it went offline.
  void facts(List<Fact> facts, {required bool all}) {
    final states = {
      if (!all) ..._states,
      for (final (subject, value) in facts)
        if ((subject, value) case (
          FriendSubject(:final pk),
          CallValue(:final state),
        ))
          pk: state,
    };
    for (final friend in {..._states.keys, ...states.keys}) {
      final (was, now) = (_states[friend], states[friend]);
      if (now case RingingCall(:final video)
          when was is! RingingCall && _friend == null) {
        _friend = friend;
        _signals.add(CallSignal.ringing(friend, video: video));
      } else if (was is RingingCall &&
          now is! RingingCall &&
          friend == _friend &&
          _connecting == null) {
        // It stopped ringing before this device answered: the friend gave
        // up, or another device answered.
        _end();
        _signals.add(CallSignal.finished(friend));
      } else if (friend == _friend &&
          _connecting != null &&
          was != null &&
          (now == null || now is NoCall)) {
        // The friend's call ended at the home device, or it went offline,
        // while it was to connect this one.
        _home.hangUp(friend);
        _end();
        _signals.add(CallSignal.finished(friend));
      }
    }
    _states
      ..clear()
      ..addAll({
        for (final MapEntry(key: friend, value: state) in states.entries)
          if (state is! NoCall) friend: state,
      });
  }

  void _end() {
    _friend = null;
    _connecting = null;
    _connectBy = null;
  }

  @override
  List<CallSignal> poll() {
    final signals = [..._signals];
    _signals.clear();
    if ((_friend, _connectBy) case (final friend?, final by?)
        when clock.now().isAfter(by)) {
      // Another device answered first, or the home device couldn't connect
      // it.
      hangUp(friend);
      signals.add(CallSignal.finished(friend));
    }
    for (final signal in _home.poll()) {
      switch (signal) {
        // The home device calls this one once the friend's call is
        // connected.
        case CallRinging(:final friend):
          if (_connecting case final video?) {
            _connectBy = null;
            _home.answer(friend, video: video);
            signals.add(CallSignal.answered(friend));
          } else {
            _home.hangUp(friend);
          }
        case CallFinished(:final friend):
          _end();
          signals.add(CallSignal.finished(friend));
        default:
          signals.add(signal);
      }
    }
    return signals;
  }

  @override
  Duration get interval => _home.interval;

  @override
  bool get ringsElsewhere => true;

  @override
  bool call(PublicKey friend, {required bool video}) {
    if (_friend != null && _friend != friend) {
      return false;
    }
    _connect(friend, video: video);
    return true;
  }

  @override
  void answer(PublicKey friend, {required bool video}) {
    _connect(friend, video: video);
    _connectBy = clock.now().add(_connectTimeout);
  }

  void _connect(PublicKey friend, {required bool video}) {
    _friend = friend;
    _connecting = video;
    _toHome(SessionMessage.call(friend, CallAction.connect(video: video)));
  }

  @override
  void hangUp(PublicKey friend) {
    _toHome(SessionMessage.call(friend, const CallAction.hangUp()));
    _home.hangUp(friend);
    if (friend == _friend) {
      _end();
    }
  }

  // Only through a call with the home device while it's online.
  bool _carries(PublicKey friend) => friend == _friend && _homeNumber() != null;

  @override
  void sendAudio(PublicKey friend, Int16List pcm) {
    if (_carries(friend)) {
      _home.sendAudio(friend, pcm);
    }
  }

  @override
  void setVideo(PublicKey friend, {required bool on}) {
    if (_carries(friend)) {
      _home.setVideo(friend, on: on);
    }
  }

  @override
  void sendVideo(PublicKey friend, I420Frame frame) {
    if (_carries(friend)) {
      _home.sendVideo(friend, frame);
    }
  }
}
