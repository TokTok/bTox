import 'package:btox/models/profile_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings saved before stayOnline existed stay online', () {
    final settings = ProfileSettings.fromJson({
      'nickname': 'Me',
      'statusMessage': '',
    });
    expect(settings.stayOnline, isTrue);
  });
}
