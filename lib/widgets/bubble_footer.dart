import 'package:btox/models/chat_view.dart';
import 'package:flutter/material.dart';

const _kSeenColor = Color(0xFF92DEDA);
// From the corner of a picture or a map, over it.
const _kMediaInset = 6.0;

/// When a message was sent and, for ours, how far it got, at the end of its
/// bubble.
final class BubbleFooter extends StatelessWidget {
  final String? time;
  final ChatContentState state;
  final Color color;
  // Over a picture or a map: light on a dark patch.
  final bool onMedia;

  const BubbleFooter({
    super.key,
    this.time,
    this.state = ChatContentState.none,
    required this.color,
    this.onMedia = false,
  });

  /// The footer to show over a picture or a map, in its [Stack]'s corner.
  Widget overMedia() => Positioned(
    right: _kMediaInset,
    bottom: _kMediaInset,
    child: BubbleFooter(
      time: time,
      state: state,
      color: Colors.white,
      onMedia: true,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final icon = switch (state) {
      ChatContentState.none => null,
      ChatContentState.pending => Icons.schedule,
      ChatContentState.sent => Icons.done,
      ChatContentState.delivered || ChatContentState.seen => Icons.done_all,
    };
    final footer = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        if (time case final time?)
          Text(
            time,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color),
          ),
        if (icon != null)
          Icon(
            icon,
            size: 14,
            color: state == ChatContentState.seen ? _kSeenColor : color,
          ),
      ],
    );
    if (!onMedia) {
      return footer;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: footer,
      ),
    );
  }
}
