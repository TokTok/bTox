import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

DateTime localDay(DateTime time) => DateUtils.dateOnly(time.toLocal());

/// The time of day of [time], as this device shows times.
String timeText(BuildContext context, DateTime time) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

/// A [day], as said above its messages.
String dayText(BuildContext context, DateTime day) {
  final l10n = AppLocalizations.of(context)!;
  final dates = MaterialLocalizations.of(context);
  final today = localDay(clock.now());
  return DateUtils.isSameDay(day, today)
      ? l10n.today
      : DateUtils.isSameDay(day, DateUtils.addDaysToDate(today, -1))
      ? l10n.yesterday
      : day.year == today.year
      ? dates.formatMediumDate(day)
      : dates.formatFullDate(day);
}

String dayAndTimeText(BuildContext context, DateTime time) =>
    AppLocalizations.of(context)!
        .dayAndTime(dayText(context, localDay(time)), timeText(context, time));

/// When [time] was, as briefly as a chat list says it: the time today, the
/// weekday this week, else the date.
String recentText(BuildContext context, DateTime time) =>
    DateUtils.isSameDay(localDay(time), localDay(clock.now()))
    ? timeText(context, time)
    : nearDayText(context, localDay(time));

/// A [day] as briefly as it can be told apart: the weekday within a week of
/// today, else the date.
String nearDayText(BuildContext context, DateTime day) {
  final dates = MaterialLocalizations.of(context);
  final today = localDay(clock.now());
  if (day.isAfter(DateUtils.addDaysToDate(today, -7)) &&
      day.isBefore(DateUtils.addDaysToDate(today, 7))) {
    return DateFormat.E(Localizations.localeOf(context).toLanguageTag())
        .format(day);
  }
  return day.year == today.year
      ? dates.formatShortMonthDay(day)
      : dates.formatCompactDate(day);
}
