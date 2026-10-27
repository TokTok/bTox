import 'dart:async';

import 'package:btox/calls/call_channel.dart';
import 'package:btox/calls/call_info.dart';
import 'package:btox/calls/call_video.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/widgets/call_entry.dart';
import 'package:btox/widgets/call_video_view.dart';
import 'package:btox/widgets/circle_identicon.dart';
import 'package:btox_call_media/btox_call_media.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// A video call goes on without the camera.
Future<bool> _permitted(BuildContext context, {required bool camera}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context)!;
  if (await BtoxCallMedia.instance.requestPermissions(camera: camera)) {
    return true;
  }
  messenger?.showSnackBar(
    SnackBar(content: Text(camera ? l10n.cameraNeeded : l10n.microphoneNeeded)),
  );
  return false;
}

/// Android lets the user forbid it.
final class RingOverLockScreenBanner extends HookWidget {
  const RingOverLockScreenBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lifecycle = useAppLifecycleState();
    // Again on returning from the setting.
    final allowed = useFuture(
      useMemoized(BtoxCallMedia.instance.canRingOverLockScreen, [
        lifecycle == AppLifecycleState.resumed,
      ]),
    );
    if (allowed.data != false) {
      return const SizedBox.shrink();
    }
    return MaterialBanner(
      leading: const Icon(Icons.phone_locked),
      content: Text(l10n.ringOverLockScreen),
      actions: [
        TextButton(
          onPressed: BtoxCallMedia.instance.allowRingingOverLockScreen,
          child: Text(l10n.allowRingOverLockScreen),
        ),
      ],
    );
  }
}

Future<void> startCall(
  BuildContext context,
  ChatRef chat,
  PublicKey friend, {
  bool video = false,
}) async {
  if (!await _permitted(context, camera: false) || !context.mounted) {
    return;
  }
  final withVideo = video && await _permitted(context, camera: true);
  CallCommands.call(chat.profile, friend, video: withVideo);
}

String callStatus(AppLocalizations l10n, CallInfo call, DateTime now) =>
    switch (call) {
      CallInfo(connectedAt: final at?) => durationText(now.difference(at)),
      CallInfo(phase: CallPhase.ringing, video: false) => l10n.incomingCall,
      CallInfo(phase: CallPhase.ringing) => l10n.incomingVideoCall,
      _ => l10n.calling,
    };

DateTime useNow() {
  final now = useState(clock.now());
  useEffect(() {
    final timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => now.value = clock.now(),
    );
    return timer.cancel;
  }, const []);
  return now.value;
}

final class CallScreen extends HookWidget {
  final CallInfo call;

  /// Shows the chats while the call goes on.
  final void Function() onHide;

  const CallScreen({super.key, required this.call, required this.onHide});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final now = useNow();
    final ringing = call.phase == CallPhase.ringing;
    // A call shows over the lock screen, as the phone's own do, also once
    // it's answered there.
    useEffect(() {
      BtoxCallMedia.instance.showOverLockScreen(on: true);
      return () => BtoxCallMedia.instance.showOverLockScreen(on: false);
    }, const []);
    final profile = call.chat.profile;
    final active = call.phase == CallPhase.active;
    final background = switch (call) {
      CallInfo(friendVideo: true) when active => const CallVideoView(
        view: VideoView.remote,
      ),
      CallInfo(camera: true) => CallVideoView(
        view: VideoView.local,
        mirrored: call.frontCamera,
      ),
      _ => null,
    };
    final corner = active && call.friendVideo && call.camera;
    // Over video, text needs its own contrast.
    final onVideo = background == null
        ? null
        : const TextStyle(
            color: Colors.white,
            shadows: [Shadow(blurRadius: 8)],
          );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (background != null) ...[
            background,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black54,
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black54,
                  ],
                  stops: [0, 0.25, 0.7, 1],
                ),
              ),
            ),
          ],
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    if (ringing)
                      const SizedBox(height: 48)
                    else
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down),
                        color: onVideo?.color,
                        tooltip: l10n.hideCall,
                        onPressed: onHide,
                      ),
                    const Spacer(),
                    if (call.camera)
                      IconButton(
                        icon: const Icon(Icons.flip_camera_android),
                        color: onVideo?.color,
                        tooltip: l10n.flipCamera,
                        onPressed: () => CallCommands.flipCamera(profile),
                      ),
                  ],
                ),
                if (background == null) ...[
                  const Spacer(),
                  SizedBox.square(
                    dimension: 128,
                    child: FittedBox(
                      child: CircleIdenticon(bytes: call.friend),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Text(
                  call.name ?? l10n.defaultContactName,
                  style: theme.textTheme.headlineMedium?.merge(onVideo),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  callStatus(l10n, call, now),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                      .merge(onVideo),
                ),
                if (corner)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: 96,
                          height: 128,
                          child: CallVideoView(
                            view: VideoView.local,
                            mirrored: call.frontCamera,
                          ),
                        ),
                      ),
                    ),
                  ),
                const Spacer(flex: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: ringing
                        ? [
                            _CallButton(
                              icon: Icons.call_end,
                              label: l10n.declineCall,
                              color: Colors.red,
                              labelStyle: onVideo,
                              onPressed: () => CallCommands.hangUp(profile),
                            ),
                            _CallButton(
                              icon: call.video ? Icons.videocam : Icons.call,
                              label: l10n.answerCall,
                              color: Colors.green,
                              labelStyle: onVideo,
                              onPressed: () async {
                                if (!await _permitted(context, camera: false) ||
                                    !context.mounted) {
                                  return;
                                }
                                if (call.video) {
                                  await _permitted(context, camera: true);
                                }
                                CallCommands.answer(profile);
                              },
                            ),
                          ]
                        : [
                            _CallButton(
                              icon: call.camera
                                  ? Icons.videocam
                                  : Icons.videocam_off,
                              label: l10n.callCamera,
                              selected: call.camera,
                              labelStyle: onVideo,
                              onPressed: () async {
                                if (call.camera ||
                                    await _permitted(context, camera: true)) {
                                  CallCommands.camera(
                                    profile,
                                    on: !call.camera,
                                  );
                                }
                              },
                            ),
                            _CallButton(
                              icon: call.muted ? Icons.mic_off : Icons.mic,
                              label: l10n.muteCall,
                              selected: call.muted,
                              labelStyle: onVideo,
                              onPressed: () => CallCommands.mute(
                                profile,
                                muted: !call.muted,
                              ),
                            ),
                            _RouteButton(call: call, labelStyle: onVideo),
                            _CallButton(
                              icon: Icons.call_end,
                              label: l10n.hangUp,
                              color: Colors.red,
                              labelStyle: onVideo,
                              onPressed: () => CallCommands.hangUp(profile),
                            ),
                          ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _RouteButton extends StatelessWidget {
  final CallInfo call;
  final TextStyle? labelStyle;

  const _RouteButton({required this.call, this.labelStyle});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final profile = call.chat.profile;
    final onSpeaker = call.route == AudioRoute.speaker;
    if (call.routes.difference(const {
      AudioRoute.earpiece,
      AudioRoute.speaker,
    }).isEmpty) {
      return _CallButton(
        icon: Icons.volume_up,
        label: l10n.callSpeaker,
        selected: onSpeaker,
        labelStyle: labelStyle,
        // Tablets have no earpiece.
        onPressed: call.routes.length < 2
            ? null
            : () => CallCommands.route(
                profile,
                onSpeaker ? AudioRoute.earpiece : AudioRoute.speaker,
              ),
      );
    }
    return _CallButton(
      icon: _routeIcon(call.route),
      label: _routeName(l10n, call.route),
      labelStyle: labelStyle,
      onPressed: () async {
        final route = await showModalBottomSheet<AudioRoute>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final route in AudioRoute.values)
                  if (call.routes.contains(route))
                    ListTile(
                      leading: Icon(_routeIcon(route)),
                      title: Text(_routeName(l10n, route)),
                      trailing: route == call.route
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, route),
                    ),
              ],
            ),
          ),
        );
        if (route != null) {
          CallCommands.route(profile, route);
        }
      },
    );
  }
}

IconData _routeIcon(AudioRoute route) => switch (route) {
  AudioRoute.earpiece => Icons.phone_in_talk,
  AudioRoute.speaker => Icons.volume_up,
  AudioRoute.wired => Icons.headset,
  AudioRoute.bluetooth => Icons.bluetooth_audio,
};

String _routeName(AppLocalizations l10n, AudioRoute route) => switch (route) {
  AudioRoute.earpiece => l10n.callEarpiece,
  AudioRoute.speaker => l10n.callSpeaker,
  AudioRoute.wired => l10n.callWired,
  AudioRoute.bluetooth => l10n.callBluetooth,
};

final class _CallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  // Answering and hanging up have their own colours.
  final Color? color;
  final bool selected;
  final TextStyle? labelStyle;
  final void Function()? onPressed;

  const _CallButton({
    required this.icon,
    required this.label,
    this.color,
    this.selected = false,
    this.labelStyle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background =
        color ?? (selected ? scheme.onSurface : scheme.surfaceContainerHigh);
    final foreground = color != null
        ? Colors.white
        : (selected ? scheme.surface : scheme.onSurface);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          iconSize: 32,
          style: IconButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            fixedSize: const Size.square(72),
          ),
          tooltip: label,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.merge(labelStyle),
        ),
      ],
    );
  }
}
