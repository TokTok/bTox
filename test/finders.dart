import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A message's text, without the room it leaves for its bubble's footer.
Finder findMessage(String text) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      (widget.data ??
              widget.textSpan?.toPlainText(includePlaceholders: false)) ==
          text,
  description: 'message "$text"',
);
