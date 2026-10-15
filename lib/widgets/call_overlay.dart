import 'package:btox/calls/call_channel.dart';
import 'package:btox/calls/call_info.dart';
import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/pages/call_page.dart';
import 'package:btox/providers/calls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Shows the ongoing call over [child]: its screen, or once hidden, a banner
/// that brings it back.
final class CallOverlay extends HookConsumerWidget {
  final Widget child;

  const CallOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callsProvider).value?.firstOrNull;
    final hidden = useState(false);
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

    if (call == null) {
      return child;
    }
    if (!hidden.value) {
      return Stack(
        children: [
          child,
          // Above the app's navigator: its tooltips and sheets need their own.
          Positioned.fill(
            child: HeroControllerScope.none(
              child: Navigator(
                pages: [
                  MaterialPage<void>(
                    child: CallScreen(
                      call: call,
                      onHide: () => hidden.value = true,
                    ),
                  ),
                ],
                onDidRemovePage: (page) {},
              ),
            ),
          ),
        ],
      );
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
