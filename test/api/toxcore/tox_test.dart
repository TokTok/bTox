import 'package:btox/api/toxcore/tox.dart';
import 'package:btox/ffi/generated/toxcore.ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiException', () {
    test('toString() with functionName', () {
      const exn = ApiException(Tox_Err_New.TOX_ERR_NEW_MALLOC, 'tox_new');
      expect(
        exn.toString(),
        'ApiException: Tox_Err_New.TOX_ERR_NEW_MALLOC in tox_new',
      );
    });

    test('toString() without functionName', () {
      const exn = ApiException(Tox_Err_New.TOX_ERR_NEW_MALLOC);
      expect(exn.toString(), 'ApiException: Tox_Err_New.TOX_ERR_NEW_MALLOC');
    });
  });
}
