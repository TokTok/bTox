import 'dart:async';

import 'package:btox/calls/call_audio.dart';
import 'package:btox/calls/call_info.dart';
import 'package:btox/calls/call_protocol.dart';
import 'package:btox/calls/call_video.dart';
import 'package:btox/logger.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/sync/event.dart';
import 'package:clock/clock.dart';

const _logger = Logger(['Calls']);

const ringFor = Duration(minutes: 1);

/// When both ends place a call at once, how long the one that places it
/// again waits for what's left of the first to arrive, and how long the
/// other waits for it.
const glareDelay = Duration(seconds: 2);
const glareWait = Duration(seconds: 8);

/// Where the UI may not show: ringing over the lock screen, and missed calls.
abstract interface class CallNotifier {
  void ring(CallInfo call);

  /// Also one that rang when bTox last stopped.
  void stopRinging(Id<Profiles> profile);

  void missed(CallInfo call);
}

/// One at a time, recorded in the friends' chats.
final class Calls {
  final Id<Profiles> _profile;
  final PublicKey _self;
  final CallProtocol _protocol;
  final CallAudio _audio;
  final CallVideo? _video;
  final CallNotifier? _notifier;
  final GraphId Function(PublicKey friend) _chatOf;
  final String? Function(PublicKey friend) _nameOf;
  final String Function() _selfName;
  final Future<NewEvent?> Function(GraphId chat, EventContent content) _record;
  final void Function(CallInfo? call) _changed;
  final bool Function() _busyElsewhere;
  final void Function(VideoView view, I420Frame frame) _showVideo;

  CallInfo? _call;
  // The call's Call event, once recorded.
  Future<NewEvent?>? _started;
  Timer? _poll;
  Timer? _unanswered;
  // Whether the call was placed at both ends at once, and while it's placed
  // again.
  var _glared = false;
  Timer? _glare;
  // With it, a call ringing here shows.
  var _shown = false;
  var _disposed = false;

  Calls(
    this._profile,
    this._self,
    this._protocol,
    this._audio, {
    CallVideo? video,
    CallNotifier? notifier,
    required GraphId Function(PublicKey friend) chatOf,
    required String? Function(PublicKey friend) nameOf,
    required String Function() selfName,
    required Future<NewEvent?> Function(GraphId chat, EventContent content)
    record,
    required void Function(CallInfo? call) changed,
    bool Function()? busyElsewhere,
    void Function(VideoView view, I420Frame frame)? showVideo,
  }) : _video = video,
       _notifier = notifier,
       _chatOf = chatOf,
       _nameOf = nameOf,
       _selfName = selfName,
       _record = record,
       _changed = changed,
       _busyElsewhere = busyElsewhere ?? (() => false),
       _showVideo = showVideo ?? ((_, _) {}) {
    _schedule(Duration.zero);
  }

  CallInfo? get current => _call;

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    try {
      hangUp('bTox stopped');
    } on StateError catch (e) {
      // Tox was killed first, which ended the call with it.
      _logger.d('Hanging up: $e');
    }
  }

  void call(PublicKey friend, {bool video = false}) {
    if (_call case CallInfo(phase: CallPhase.ringing, friend: final ringing)
        when ringing == friend) {
      answer();
      return;
    }
    if (_call != null || _busyElsewhere()) {
      return;
    }
    final withVideo = video && _video != null;
    if (!_protocol.call(friend, video: withVideo)) {
      return;
    }
    final call = _begin(friend, CallPhase.calling, video: withVideo);
    _logger.unawaited('start the call', _start(call, ringBack: true));
    _unanswered = Timer(ringFor, () => hangUp('not answered'));
  }

  void answer() {
    if (_call case final call? when call.phase == CallPhase.ringing) {
      final withVideo = call.video && _video != null;
      _protocol.answer(call.friend, video: withVideo);
      final answered = call.copyWith(camera: withVideo);
      _set(answered);
      _logger.unawaited('start the call', _start(answered));
      if (_protocol.ringsElsewhere) {
        _stopRinging(answered);
        _set(answered.copyWith(phase: CallPhase.connecting));
      } else {
        _connect(answered);
      }
    }
  }

  /// Also declines it while it rings.
  void hangUp([String why = 'hung up here']) {
    if (_call case final call?) {
      // Ended here, also where the friend can't be told.
      try {
        _protocol.hangUp(call.friend);
      } finally {
        _end(call, why, declined: true);
      }
    }
  }

  /// Only ours: toxav's mute would stop the friend's audio too.
  void setMuted({required bool muted}) {
    if (_call case final call?) {
      _set(call.copyWith(muted: muted));
    }
  }

  void setRoute(AudioRoute route) {
    if (_call case final call?) {
      _logger.unawaited('route the audio', _audio.setRoute(route));
      _set(call.copyWith(route: route));
    }
  }

  void setCamera({required bool on}) {
    if (_call case final call? when _video != null && call.camera != on) {
      final changed = call.copyWith(camera: on);
      _set(changed);
      if (call.phase == CallPhase.active) {
        _protocol.setVideo(call.friend, on: on);
      }
      _logger.unawaited(
        'switch the camera',
        on ? _startCamera(changed) : _video.stopCamera(),
      );
    }
  }

  void flipCamera() {
    if (_call case final call? when call.camera) {
      final flipped = call.copyWith(frontCamera: !call.frontCamera);
      _set(flipped);
      _logger.unawaited('flip the camera', _startCamera(flipped));
    }
  }

  /// A call ringing here rings from its notification, unless the UI shows
  /// it: then the notification would cover it.
  void setShown({required bool shown}) {
    _shown = shown;
    if (_call case final call? when call.phase == CallPhase.ringing) {
      _ring(call);
    }
  }

  /// Toxcore drops a friend's call when they go offline.
  void friendOffline(PublicKey friend) {
    if (_call case final call? when call.friend == friend) {
      _end(call, 'the friend went offline');
    }
  }

  void _schedule(Duration after) {
    _poll = Timer(after, () {
      if (_disposed) {
        return;
      }
      // Whatever a friend sends, calls go on being polled.
      try {
        _handle(_protocol.poll());
      } on Object catch (e, stackTrace) {
        _logger.e('Failed to handle calls: $e', stackTrace);
      } finally {
        _schedule(_protocol.interval);
      }
    });
  }

  void _handle(List<CallSignal> signals) {
    for (final signal in signals) {
      final call = _call;
      switch (signal) {
        case CallRinging(:final friend)
            when _glared &&
                call?.friend == friend &&
                call?.phase == CallPhase.calling:
          _glare?.cancel();
          _glare = null;
          _protocol.answer(friend, video: call!.camera);
          _connect(call);
        case CallFinished(:final friend, failed: true)
            when !_glared &&
                call?.friend == friend &&
                call?.phase == CallPhase.calling:
          // Toxav fails a call both ends placed at once, at both ends: the
          // one with the higher key places it again, the other answers.
          _glared = true;
          final again = _self.compareTo(friend) > 0;
          _glare = Timer(again ? glareDelay : glareWait, () {
            _glare = null;
            if (_call case final call?
                when call.friend == friend && call.phase == CallPhase.calling) {
              if (!again || !_protocol.call(friend, video: call.camera)) {
                _end(call, 'placed at both ends at once');
              }
            }
          });
        case CallRinging(:final friend, :final video)
            when call == null && !_busyElsewhere():
          _ring(_begin(friend, CallPhase.ringing, video: video));
        case CallRinging() when _protocol.ringsElsewhere:
          // Another device may answer it.
          break;
        case CallRinging(:final friend, :final video):
          // One call at a time, across profiles: another is declined, and
          // missed.
          _logger.i('Declined a call from $friend while busy');
          _protocol.hangUp(friend);
          final missed = _info(friend, CallPhase.ringing, video: video);
          _notifier?.missed(missed);
          _logger.unawaited(
            'record a missed call',
            _ended(_startEvent(missed), null),
          );
        case CallAnswered(:final friend)
            when call?.friend == friend &&
                (call?.phase == CallPhase.calling ||
                    call?.phase == CallPhase.connecting):
          _connect(call!);
        case CallFinished(:final friend, :final failed)
            when call?.friend == friend:
          _end(call!, failed ? 'it failed' : 'the friend hung up');
        case CallAudioFrame(
              :final friend,
              :final pcm,
              :final channels,
              :final sampleRate,
            )
            when call?.friend == friend && call?.phase == CallPhase.active:
          _audio.play(pcm, channels: channels, sampleRate: sampleRate);
        case CallFriendVideo(:final friend, :final on)
            when call?.friend == friend:
          _set(call!.copyWith(friendVideo: on));
        case CallVideoFrame(:final friend, :final frame)
            when call?.friend == friend && call?.phase == CallPhase.active:
          _showVideo(VideoView.remote, frame);
        default:
          break;
      }
    }
  }

  CallInfo _info(PublicKey friend, CallPhase phase, {required bool video}) =>
      CallInfo(
        chat: ChatRef(_profile, _chatOf(friend)),
        friend: friend,
        name: _nameOf(friend),
        phase: phase,
        video: video,
        camera: video && phase == CallPhase.calling,
      );

  Future<NewEvent?> _startEvent(CallInfo call) => _record(
    call.chat.graph,
    Call(
      sender: call.phase == CallPhase.ringing ? call.name ?? '' : _selfName(),
      incoming: call.phase == CallPhase.ringing,
      video: call.video,
    ),
  );

  CallInfo _begin(PublicKey friend, CallPhase phase, {required bool video}) {
    _glared = false;
    final call = _info(friend, phase, video: video);
    _started = _startEvent(call);
    _set(call);
    return call;
  }

  void _ring(CallInfo call) {
    // Where nothing else tells of it, as on a desktop, it rings here also
    // while bTox isn't in front.
    final notifier = _notifier;
    final here = _shown || notifier == null;
    _logger.unawaited('ring', _audio.setRinging(on: here));
    if (here) {
      notifier?.stopRinging(_profile);
    } else {
      notifier.ring(call);
    }
  }

  void _stopRinging(CallInfo call) {
    _unanswered?.cancel();
    switch (call.phase) {
      case CallPhase.ringing:
        _logger.unawaited('stop ringing', _audio.setRinging(on: false));
        _notifier?.stopRinging(_profile);
      case CallPhase.calling:
        _logger.unawaited('stop ringing back', _audio.setRingBack(on: false));
      case CallPhase.connecting || CallPhase.active:
        break;
    }
  }

  void _connect(CallInfo call) {
    _stopRinging(call);
    // Our camera may have changed while it rang.
    if (call.camera != call.video) {
      _protocol.setVideo(call.friend, on: call.camera);
    }
    _set(call.copyWith(phase: CallPhase.active, connectedAt: clock.now()));
  }

  /// When the call is placed or answered, in the UI: Android only lets an
  /// app start using the microphone while it's in the foreground.
  Future<void> _start(CallInfo call, {bool ringBack = false}) async {
    try {
      await _startAudio(call);
    } on Exception catch (e) {
      // No microphone, or one another app holds: no call without it.
      _endWithout(call, 'the audio could not start: $e');
      return;
    }
    if (ringBack && _call?.phase == CallPhase.calling) {
      await _audio.setRingBack(on: true);
    }
    if (_call case final current? when current.camera) {
      await _startCamera(current);
    }
  }

  Future<void> _startAudio(CallInfo call) => _audio.start(
    speaker: call.video,
    (frame) {
      if (_call case final call?
          when call.phase == CallPhase.active && !call.muted) {
        _protocol.sendAudio(call.friend, frame);
      }
    },
    onRoutes: (route, routes) {
      if (_call case final call?) {
        _set(call.copyWith(route: route, routes: routes));
      }
    },
    onFailed: () => _endWithout(call, 'the microphone stopped'),
  );

  void _endWithout(CallInfo call, String why) {
    if (_call?.friend == call.friend) {
      hangUp(why);
    }
  }

  Future<void> _startCamera(CallInfo call) async {
    try {
      await _video?.startCamera(
        front: call.frontCamera,
        onFrame: (frame) {
          _showVideo(VideoView.local, frame);
          if (_call case final call?
              when call.phase == CallPhase.active && call.camera) {
            _protocol.sendVideo(call.friend, frame);
          }
        },
        onStopped: () => setCamera(on: false),
      );
    } on Exception catch (e) {
      // No camera, or no permission for it.
      _logger.w('Starting the camera: $e');
      setCamera(on: false);
    }
  }

  void _end(CallInfo call, String why, {bool declined = false}) {
    _logger.i('A ${call.phase.name} call with ${call.friend} ended: $why');
    _stopRinging(call);
    _glare?.cancel();
    _glare = null;
    final started = _started;
    _started = null;
    _set(null);
    if (call.phase != CallPhase.ringing) {
      if (call.camera && _video != null) {
        _logger.unawaited('stop the camera', _video.stopCamera());
      }
      _logger.unawaited('stop the audio', _audio.stop());
    } else if (!declined) {
      _notifier?.missed(call);
    }
    if (started != null) {
      _logger.unawaited(
        'record the end of a call',
        _ended(started, switch (call.connectedAt) {
          final at? => clock.now().difference(at),
          null => null,
        }, declined: declined && call.phase == CallPhase.ringing),
      );
    }
  }

  Future<void> _ended(
    Future<NewEvent?> started,
    Duration? duration, {
    bool declined = false,
  }) async {
    if (await started case (final id, final event, _)) {
      await _record(
        event.graph,
        CallEnded(call: id, duration: duration, declined: declined),
      );
    }
  }

  void _set(CallInfo? call) {
    _call = call;
    _changed(call);
  }
}
