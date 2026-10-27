import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/providers/database.dart';
import 'package:btox/sync/setting.dart';
import 'package:btox/widgets/dates.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Asks how long to mute [chat] for, and in a group whether messages naming
/// the account still notify, then mutes it.
Future<void> muteChat(
  BuildContext context,
  WidgetRef ref,
  ChatSummary chat,
) async {
  final picked = await showDialog<(Duration?, bool)>(
    context: context,
    builder: (context) => _MuteDialog(group: chat.key is! PublicKey),
  );
  if (picked case (final duration, final mentions)) {
    final db = await ref.read(databaseProvider.future);
    await db.setSetting(
      chat.ref.profile,
      Scope.conversation(chat.ref.graph),
      Kept(
        Setting.mute(
          until: duration == null ? null : clock.now().add(duration),
          mentions: mentions,
        ),
      ),
    );
  }
}

Future<void> unmuteChat(WidgetRef ref, ChatRef chat) async {
  final db = await ref.read(databaseProvider.future);
  await db.clearSetting(
    chat.profile,
    Scope.conversation(chat.graph),
    Setting.muteKind,
  );
}

/// Until when [mute] holds: the time today, the weekday and time this
/// week, else the date and time.
String mutedText(BuildContext context, Mute mute) {
  final l10n = AppLocalizations.of(context)!;
  final until = mute.until;
  if (until == null) {
    return l10n.mutedAlways;
  }
  final day = localDay(until);
  final time = timeText(context, until);
  return l10n.mutedUntil(
    DateUtils.isSameDay(day, localDay(clock.now()))
        ? time
        : l10n.dayAndTime(nearDayText(context, day), time),
  );
}

final class _MuteDialog extends HookWidget {
  final bool group;

  const _MuteDialog({required this.group});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mentions = useState(true);
    return SimpleDialog(
      title: Text(l10n.muteChat),
      children: [
        if (group)
          CheckboxListTile(
            value: mentions.value,
            onChanged: (value) => mentions.value = value ?? true,
            title: Text(l10n.notifyMentions),
          ),
        for (final (duration, label) in [
          (const Duration(hours: 1), l10n.muteForAnHour),
          (const Duration(hours: 8), l10n.muteForEightHours),
          (const Duration(days: 7), l10n.muteForAWeek),
          (null, l10n.muteAlways),
        ])
          ListTile(
            title: Text(label),
            onTap: () =>
                Navigator.pop(context, (duration, group && mentions.value)),
          ),
      ],
    );
  }
}
