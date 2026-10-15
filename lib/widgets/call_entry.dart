import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/content.dart';
import 'package:flutter/material.dart';

/// How long a call was: `2:31`, or `1:02:31`.
String durationText(Duration duration) {
  String two(int n) => n.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60);
  final seconds = two(duration.inSeconds.remainder(60));
  return duration.inHours > 0
      ? '${duration.inHours}:${two(minutes)}:$seconds'
      : '$minutes:$seconds';
}

/// What a call in a chat says: which way it went, or that it was missed,
/// and how long it was.
String callText(AppLocalizations l10n, CallContent call) {
  final kind = switch (call) {
    CallContent(ended: false, video: false) => l10n.voiceCall,
    CallContent(ended: false) => l10n.videoCall,
    CallContent(missed: true, video: false) => l10n.missedCall,
    CallContent(missed: true) => l10n.missedVideoCall,
    CallContent(incoming: true, video: false) => l10n.incomingCall,
    CallContent(incoming: true) => l10n.incomingVideoCall,
    CallContent(video: false) => l10n.outgoingCall,
    _ => l10n.outgoingVideoCall,
  };
  return switch (call.duration) {
    final duration? => l10n.callWithDuration(kind, durationText(duration)),
    null => kind,
  };
}

IconData callIcon(CallContent call) => switch (call) {
  CallContent(missed: true) => Icons.call_missed,
  CallContent(incoming: true) => Icons.call_received,
  _ => Icons.call_made,
};

/// A call, as it shows among a chat's messages.
final class ChatCallNotice extends StatelessWidget {
  final CallContent call;

  const ChatCallNotice({super.key, required this.call});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = call.missed
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(callIcon(call), size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                callText(AppLocalizations.of(context)!, call),
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
