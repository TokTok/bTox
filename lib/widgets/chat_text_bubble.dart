import 'package:flutter/material.dart';

const _kCorner = Radius.circular(20);
// Where a bubble joins the next in its run.
const _kJoinedCorner = Radius.circular(4);

/// A bubble's corners: those on its author's side are small where it joins
/// the bubble above or below.
BorderRadius bubbleCorners({
  required bool mine,
  bool joinsAbove = false,
  bool joinsBelow = false,
}) {
  final top = joinsAbove ? _kJoinedCorner : _kCorner;
  final bottom = joinsBelow ? _kJoinedCorner : _kCorner;
  return mine
      ? BorderRadius.only(
          topLeft: _kCorner,
          bottomLeft: _kCorner,
          topRight: top,
          bottomRight: bottom,
        )
      : BorderRadius.only(
          topRight: _kCorner,
          bottomRight: _kCorner,
          topLeft: top,
          bottomLeft: bottom,
        );
}

const _kPadding = EdgeInsets.symmetric(vertical: 6, horizontal: 12);

/// The same size as [footer], unseen: room for it where the real one shows.
Widget footerSpace(Widget footer) => Opacity(opacity: 0, child: footer);

final class ChatTextBubble extends StatelessWidget {
  final BorderRadius corners;
  final Color color;
  // Above the content, such as who wrote it.
  final Widget? header;
  // In the bottom corner, below the content unless it made room itself, as
  // text does at the end of its last line.
  final Widget? footer;
  final bool contentHasFooterSpace;
  final Widget child;

  const ChatTextBubble({
    super.key,
    required this.corners,
    required this.color,
    this.header,
    this.footer,
    this.contentHasFooterSpace = false,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final footer = this.footer;
    final content = [
      ?header,
      child,
      if (footer != null && !contentHasFooterSpace) footerSpace(footer),
    ];
    return Container(
      decoration: BoxDecoration(color: color, borderRadius: corners),
      child: Stack(
        children: [
          Padding(
            padding: _kPadding,
            child: content.length == 1
                ? child
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  ),
          ),
          if (footer != null)
            Positioned(
              right: _kPadding.right,
              bottom: _kPadding.bottom,
              child: footer,
            ),
        ],
      ),
    );
  }
}
