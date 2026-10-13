import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:btox/api/toxcore/tox.dart' as api;
import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/api/toxcore/tox_options.dart' as api_opts;
import 'package:btox/ffi/generated/toxcore.ffi.dart' as ffi_gen;
import 'package:btox/ffi/tox_library.ffi.dart' as tox_lib;
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'toxcore_test.mocks.dart';

@GenerateNiceMocks([MockSpec<ffi_gen.ToxFfi>()])
void main() {
  late MockToxFfi mockFfi;
  late tox_lib.ToxLibrary lib;

  ffi.Pointer<T> safePtr<T extends ffi.NativeType>() =>
      calloc<ffi.Uint8>(1).cast<T>();

  setUpAll(() {
    provideDummy<ffi.Pointer<ffi_gen.Tox_Options>>(ffi.nullptr);
    provideDummy<ffi.Pointer<ffi_gen.Tox>>(ffi.nullptr);
    provideDummy<ffi.Pointer<ffi_gen.Tox_Events>>(ffi.nullptr);
    provideDummy<ffi.Pointer<ffi_gen.Tox_Iterate_Options>>(ffi.nullptr);
    provideDummy<ffi.Pointer<ffi.Uint8>>(ffi.nullptr);
    provideDummy<ffi.Pointer<ffi.Char>>(ffi.nullptr);
    provideDummy<ffi.Pointer<ffi.UnsignedInt>>(ffi.nullptr);
  });

  setUp(() {
    mockFfi = MockToxFfi();
    lib = tox_lib.ToxLibrary(calloc, mockFfi);

    // Common stubs
    when(mockFfi.tox_options_new(any)).thenReturn(safePtr());
    when(mockFfi.tox_new(any, any)).thenReturn(safePtr());
    when(mockFfi.tox_address_size()).thenReturn(38);
    when(mockFfi.tox_public_key_size()).thenReturn(32);
  });

  group('Toxcore', () {
    test('factory constructor initializes tox correctly', () {
      final optionsPtr = safePtr<ffi_gen.Tox_Options>();
      final toxPtr = safePtr<ffi_gen.Tox>();

      when(mockFfi.tox_options_new(any)).thenReturn(optionsPtr);
      when(mockFfi.tox_new(optionsPtr, any)).thenReturn(toxPtr);

      // ignore: argument_type_not_assignable
      final toxcore = Toxcore(lib, const api_opts.ToxOptions());

      expect(toxcore, isNotNull);
      expect(toxcore.isAlive, isTrue);

      verify(mockFfi.tox_options_new(any)).called(1);
      verify(mockFfi.tox_new(optionsPtr, any)).called(1);
      verify(mockFfi.tox_events_init(toxPtr)).called(1);
    });

    test('kill() cleans up tox correctly', () {
      final toxPtr = safePtr<ffi_gen.Tox>();
      when(mockFfi.tox_new(any, any)).thenReturn(toxPtr);

      // ignore: argument_type_not_assignable
      final toxcore = Toxcore(lib, const api_opts.ToxOptions());
      toxcore.kill();

      expect(toxcore.isAlive, isFalse);
      verify(mockFfi.tox_kill(toxPtr)).called(1);
    });

    test('reads a key toxcore writes into a buffer', () {
      final toxPtr = safePtr<ffi_gen.Tox>();
      when(mockFfi.tox_new(any, any)).thenReturn(toxPtr);
      when(mockFfi.tox_friend_get_public_key(toxPtr, 7, any, any))
          .thenAnswer((invocation) {
            final keyPtr =
                invocation.positionalArguments[2] as ffi.Pointer<ffi.Uint8>;
            keyPtr.asTypedList(32).setAll(0, List.generate(32, (i) => i));
            return true;
          });

      // ignore: argument_type_not_assignable
      final toxcore = Toxcore(lib, const api_opts.ToxOptions());

      expect(toxcore.friendGetPublicKey(7).bytes, List.generate(32, (i) => i));
    });

    test('turns toxcore errors into ApiException', () {
      final toxPtr = safePtr<ffi_gen.Tox>();
      when(mockFfi.tox_new(any, any)).thenReturn(toxPtr);
      when(mockFfi.tox_friend_get_public_key(any, any, any, any))
          .thenAnswer((invocation) {
            final errPtr =
                invocation.positionalArguments[3] as ffi.Pointer<tox_lib.CEnum>;
            errPtr.value = ffi_gen
                .Tox_Err_Friend_Get_Public_Key
                .TOX_ERR_FRIEND_GET_PUBLIC_KEY_FRIEND_NOT_FOUND
                .value;
            return false;
          });

      // ignore: argument_type_not_assignable
      final toxcore = Toxcore(lib, const api_opts.ToxOptions());

      expect(
        () => toxcore.friendGetPublicKey(3),
        throwsA(isA<api.ApiException>()),
      );
    });

    test('passes bytes with their length', () {
      final toxPtr = safePtr<ffi_gen.Tox>();
      when(mockFfi.tox_new(any, any)).thenReturn(toxPtr);
      when(
        mockFfi.tox_friend_send_message(
          toxPtr,
          5,
          ffi_gen.Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          any,
          any,
          any,
        ),
      ).thenReturn(9);

      // ignore: argument_type_not_assignable
      final toxcore = Toxcore(lib, const api_opts.ToxOptions());

      expect(
        toxcore.friendSendMessage(
          5,
          // ignore: argument_type_not_assignable
          ffi_gen.Tox_Message_Type.TOX_MESSAGE_TYPE_NORMAL,
          utf8.encode('Grüße'),
        ),
        9,
      );
      verify(mockFfi.tox_friend_send_message(toxPtr, 5, any, any, 7, any))
          .called(1);
    });

    test('ToxOptions sets the given options, owning their data', () {
      final optionsPtr = safePtr<ffi_gen.Tox_Options>();
      when(mockFfi.tox_options_new(any)).thenReturn(optionsPtr);
      when(mockFfi.tox_options_set_savedata_data(any, any, any))
          .thenReturn(true);

      final toxOptions = api_opts.ToxOptions(
        ipv6Enabled: true,
        udpEnabled: false,
        localDiscoveryEnabled: true,
        savedata: Uint8List.fromList(List.filled(3, 0)),
        savedataType: Tox_Savedata_Type.TOX_SAVEDATA_TYPE_SECRET_KEY,
      );

      // ignore: argument_type_not_assignable
      Toxcore(lib, toxOptions);

      verify(mockFfi.tox_options_set_experimental_owned_data(optionsPtr, true))
          .called(1);
      verify(mockFfi.tox_options_set_ipv6_enabled(optionsPtr, true)).called(1);
      verify(mockFfi.tox_options_set_udp_enabled(optionsPtr, false)).called(1);
      verify(mockFfi.tox_options_set_local_discovery_enabled(optionsPtr, true))
          .called(1);
      verify(
        mockFfi.tox_options_set_savedata_type(
          optionsPtr,
          ffi_gen.Tox_Savedata_Type.TOX_SAVEDATA_TYPE_SECRET_KEY,
        ),
      ).called(1);
      verify(mockFfi.tox_options_set_savedata_data(optionsPtr, any, 3))
          .called(1);
    });

    test('iterate() returns list of events', () {
      final toxPtr = safePtr<ffi_gen.Tox>();
      when(mockFfi.tox_new(any, any)).thenReturn(toxPtr);

      final eventsHandle = safePtr<ffi_gen.Tox_Events>();

      final packer = Packer();
      packer.packListLength(1);
      packer.packListLength(2);
      packer.packInt(
        ffi_gen.Tox_Event_Type.TOX_EVENT_SELF_CONNECTION_STATUS.value,
      );
      packer.packInt(Tox_Connection.TOX_CONNECTION_UDP.value);
      final bytes = packer.takeBytes();

      when(mockFfi.tox_iterate_options_new(any))
          .thenReturn(safePtr<ffi_gen.Tox_Iterate_Options>());
      when(mockFfi.tox_events_iterate(toxPtr, any, any))
          .thenReturn(eventsHandle);
      when(mockFfi.tox_events_bytes_size(eventsHandle))
          .thenReturn(bytes.length);

      when(mockFfi.tox_events_get_bytes(eventsHandle, any)).thenAnswer((
        invocation,
      ) {
        final ptr = invocation.positionalArguments[1] as ffi.Pointer<ffi.Uint8>;
        ptr.asTypedList(bytes.length).setAll(0, bytes);
        return true;
      });

      // ignore: argument_type_not_assignable
      final toxcore = Toxcore(lib, const api_opts.ToxOptions());
      final events = toxcore.iterate();

      expect(events.length, 1);
      expect(events, [
        const ToxEventSelfConnectionStatus(
          connectionStatus: Tox_Connection.TOX_CONNECTION_UDP,
        ),
      ]);

      verify(mockFfi.tox_events_free(eventsHandle)).called(1);
    });
  });
}
