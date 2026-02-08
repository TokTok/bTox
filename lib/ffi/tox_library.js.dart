import 'package:btox/ffi/generated/toxcore.js.dart';
import 'package:btox/logger.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wasm_ffi/ffi.dart';

export 'package:btox/ffi/generated/toxcore.js.dart';
export 'package:wasm_ffi/ffi.dart';

part 'tox_library.js.g.dart';

const _logger = Logger(['ToxLibrary']);

@Riverpod(keepAlive: true)
Future<ToxLibrary> toxFfi(Ref ref) async {
  _logger.d('Loading libtoxcore.wasm');
  final library = await DynamicLibrary.open('libtoxcore.js');
  _logger.d('Registering Tox types');
  _registerToxTypes();
  _logger.d('Successfully loaded libtoxcore.js');
  return ToxLibrary(library.allocator, ToxFfi(library));
}

void _registerToxTypes() {
  registerOpaqueType<Tox>();
  registerOpaqueType<Tox_Options>();
  registerOpaqueType<Tox_Event_Conference_Connected>();
  registerOpaqueType<Tox_Event_Conference_Invite>();
  registerOpaqueType<Tox_Event_Conference_Message>();
  registerOpaqueType<Tox_Event_Conference_Peer_List_Changed>();
  registerOpaqueType<Tox_Event_Conference_Peer_Name>();
  registerOpaqueType<Tox_Event_Conference_Title>();
  registerOpaqueType<Tox_Event_File_Chunk_Request>();
  registerOpaqueType<Tox_Event_File_Recv>();
  registerOpaqueType<Tox_Event_File_Recv_Chunk>();
  registerOpaqueType<Tox_Event_File_Recv_Control>();
  registerOpaqueType<Tox_Event_Friend_Connection_Status>();
  registerOpaqueType<Tox_Event_Friend_Lossless_Packet>();
  registerOpaqueType<Tox_Event_Friend_Lossy_Packet>();
  registerOpaqueType<Tox_Event_Friend_Message>();
  registerOpaqueType<Tox_Event_Friend_Name>();
  registerOpaqueType<Tox_Event_Friend_Read_Receipt>();
  registerOpaqueType<Tox_Event_Friend_Request>();
  registerOpaqueType<Tox_Event_Friend_Status>();
  registerOpaqueType<Tox_Event_Friend_Status_Message>();
  registerOpaqueType<Tox_Event_Friend_Typing>();
  registerOpaqueType<Tox_Event_Self_Connection_Status>();
  registerOpaqueType<Tox_Event_Group_Peer_Name>();
  registerOpaqueType<Tox_Event_Group_Peer_Status>();
  registerOpaqueType<Tox_Event_Group_Topic>();
  registerOpaqueType<Tox_Event_Group_Privacy_State>();
  registerOpaqueType<Tox_Event_Group_Voice_State>();
  registerOpaqueType<Tox_Event_Group_Topic_Lock>();
  registerOpaqueType<Tox_Event_Group_Peer_Limit>();
  registerOpaqueType<Tox_Event_Group_Password>();
  registerOpaqueType<Tox_Event_Group_Message>();
  registerOpaqueType<Tox_Event_Group_Private_Message>();
  registerOpaqueType<Tox_Event_Group_Custom_Packet>();
  registerOpaqueType<Tox_Event_Group_Custom_Private_Packet>();
  registerOpaqueType<Tox_Event_Group_Invite>();
  registerOpaqueType<Tox_Event_Group_Peer_Join>();
  registerOpaqueType<Tox_Event_Group_Peer_Exit>();
  registerOpaqueType<Tox_Event_Group_Self_Join>();
  registerOpaqueType<Tox_Event_Group_Join_Fail>();
  registerOpaqueType<Tox_Event_Group_Moderation>();
  registerOpaqueType<Tox_Event_Dht_Nodes_Response>();
  registerOpaqueType<Tox_Event>();
  registerOpaqueType<Tox_Events>();
  registerOpaqueType<Tox_System>();
  registerOpaqueType<ToxAV>();
  registerOpaqueType<Tox_Pass_Key>();
}

typedef CChar = Int8;

typedef CEnum = Uint32;

final class ToxLibrary {
  final Allocator allocator;
  final ToxFfi ffi;

  const ToxLibrary(this.allocator, this.ffi);
}
