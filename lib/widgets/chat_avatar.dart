import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/models/chat_view.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/models/id.dart';
import 'package:btox/models/persistence.dart';
import 'package:btox/widgets/avatar.dart';
import 'package:flutter/material.dart';

final class ChatAvatar extends StatelessWidget {
  final CryptoBytes bytes;
  final Id<Profiles>? profile;
  final BlobId? avatar;
  final bool? online;
  final double size;

  const ChatAvatar({
    super.key,
    required this.bytes,
    this.online,
    this.size = 40,
  }) : profile = null,
       avatar = null;

  ChatAvatar.of(ChatSummary chat, {super.key, this.online, this.size = 40})
    : bytes = chat.key,
      profile = chat.ref.profile,
      avatar = chat.avatar;

  @override
  Widget build(BuildContext context) {
    final (bytes, online) = (this.bytes, this.online);
    final avatar = Avatar(
      profile: profile,
      blob: this.avatar,
      bytes: bytes,
      radius: size / 2,
    );
    if (online == null) {
      return avatar;
    }
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      label: online ? l10n.online : l10n.offline,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.35,
              height: size * 0.35,
              decoration: BoxDecoration(
                color: online ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
