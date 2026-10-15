import 'package:btox/l10n/generated/app_localizations.dart';
import 'package:btox/widgets/chat_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

final class _FakeLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final opened = <String>[];
  bool opens = true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return opens;
  }
}

void main() {
  late _FakeLauncher launcher;

  setUp(() => UrlLauncherPlatform.instance = launcher = _FakeLauncher());

  Future<void> show(WidgetTester tester, String text) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ChatText(
          text: text,
          color: Colors.white,
          textStyle: const TextStyle(),
          corners: BorderRadius.zero,
        ),
      ),
    ),
  );

  testWidgets('a tapped link opens', (tester) async {
    await show(tester, 'go to www.example.com/a. now');
    expect(
      find.text('go to www.example.com/a. now', findRichText: true),
      findsOneWidget,
    );

    await tester.tapOnText(find.textRange.ofSubstring('now'));
    expect(launcher.opened, isEmpty);
    await tester.tapOnText(find.textRange.ofSubstring('example'));
    expect(launcher.opened, ['https://www.example.com/a']);
  });

  testWidgets('a link no app can open shows a message', (tester) async {
    launcher.opens = false;
    await show(tester, 'me@example.com');

    await tester.tapOnText(find.textRange.ofSubstring('me@example.com'));
    await tester.pump();
    expect(find.text('No app can open this link'), findsOneWidget);
  });
}
