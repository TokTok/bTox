import 'package:btox/calls/call_channel.dart';
import 'package:btox/calls/call_info.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/pages/call_page.dart';
import 'package:btox/providers/calls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Shows the ongoing call: its screen, as a route on [navigator]'s, or once
/// that's left, a banner over [child] that brings it back.
final class CallOverlay extends HookConsumerWidget {
  final GlobalKey<NavigatorState> navigator;
  final Widget child;

  const CallOverlay({super.key, required this.navigator, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callsProvider).value?.firstOrNull;
    final hidden = useState(false);
    final screen = useRef<Route<void>?>(null);
    final ringing = call?.phase == CallPhase.ringing;
    final shown = switch (useAppLifecycleState()) {
      null || AppLifecycleState.resumed => true,
      _ => false,
    };
    // Also as a call starts ringing, in case its host started after the UI.
    useEffect(() {
      CallCommands.shown(shown: shown);
      return null;
    }, [shown, ringing]);
    useEffect(() {
      hidden.value = false;
      return null;
    }, [call?.chat, ringing]);
    final showScreen = call != null && !hidden.value;
    useEffect(() {
      // Once built, as the navigator may not be yet.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch ((showScreen, screen.value, navigator.currentState)) {
          case (true, null, final navigator?):
            final route = screen.value = MaterialPageRoute<void>(
              builder: (_) => const _CallScreen(),
            );
            // Back, or hiding it, leaves it for the banner.
            navigator.push(route).then((_) {
              if (identical(screen.value, route)) {
                screen.value = null;
                hidden.value = true;
              }
            });
          case (false, final route?, final navigator?):
            screen.value = null;
            navigator.removeRoute(route);
          default:
            break;
        }
      });
      return null;
    }, [showScreen]);

    if (call == null || !hidden.value) {
      return child;
    }
    return Column(
      children: [
        _ReturnBanner(call: call, onTap: () => hidden.value = false),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: child,
          ),
        ),
      ],
    );
  }
}

final class _CallScreen extends ConsumerWidget {
  const _CallScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref
      .watch(callsProvider)
      .value
      ?.firstOrNull) {
    final call? => CallScreen(call: call, onHide: () => Navigator.pop(context)),
    null => const SizedBox.shrink(),
  };
}

final class _ReturnBanner extends HookWidget {
  final CallInfo call;
  final void Function() onTap;

  const _ReturnBanner({required this.call, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = useNow();
    return Material(
      color: Colors.green.shade700,
      child: InkWell(
        onTap: onTap,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.call, color: Colors.white, size: 18),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.returnToCall,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                Text(
                  callStatus(l10n, call, now),
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
