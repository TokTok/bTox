import 'package:btox/messages/formats.dart' as formats;
import 'package:btox/messages/message_format.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/providers/profiles.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'message_formats.g.dart';

/// The message formats bTox knows, which tests replace with their own.
@Riverpod(keepAlive: true)
List<MessageFormat> knownMessageFormats(Ref ref) => formats.messageFormats;

/// The message formats a profile reads friends' messages in.
@riverpod
MessageFormats messageFormats(Ref ref, Id<Profiles> id) => formats.formatsOn(
  ref.watch(knownMessageFormatsProvider),
  ref.watch(
    profileProvider(id)
        .select((profile) => profile.value?.settings.messageFormatsOff ?? []),
  ),
);
