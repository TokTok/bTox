import 'dart:typed_data';

import 'package:btox/api/toxcore/tox_events.dart';
import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:glados/glados.dart';

extension BToxAny on Any {
  Generator<Uint8List> get uint8List => list(uint8).map(Uint8List.fromList);
  Generator<Uint8List> uint8ListWithLength(int length) =>
      listWithLength(length, uint8).map(Uint8List.fromList);

  Generator<PublicKey> get publicKey =>
      uint8ListWithLength(32).map(PublicKey.new);

  // Enum Generators
  Generator<Tox_Connection> get toxConnection => choose(Tox_Connection.values);
  Generator<Tox_Message_Type> get toxMessageType =>
      choose(Tox_Message_Type.values);
  Generator<Tox_Conference_Type> get toxConferenceType =>
      choose(Tox_Conference_Type.values);
  Generator<Tox_File_Control> get toxFileControl =>
      choose(Tox_File_Control.values);
  Generator<Tox_User_Status> get toxUserStatus =>
      choose(Tox_User_Status.values);
  Generator<Tox_Group_Join_Fail> get toxGroupJoinFail =>
      choose(Tox_Group_Join_Fail.values);
  Generator<Tox_Group_Exit_Type> get toxGroupExitType =>
      choose(Tox_Group_Exit_Type.values);
  Generator<Tox_Group_Mod_Event> get toxGroupModEvent =>
      choose(Tox_Group_Mod_Event.values);
  Generator<Tox_Group_Topic_Lock> get toxGroupTopicLock =>
      choose(Tox_Group_Topic_Lock.values);
  Generator<Tox_Group_Voice_State> get toxGroupVoiceState =>
      choose(Tox_Group_Voice_State.values);
  Generator<Tox_Group_Privacy_State> get toxGroupPrivacyState =>
      choose(Tox_Group_Privacy_State.values);

  // Individual Event Generators
  Generator<ToxEventSelfConnectionStatus> get selfConnectionStatus =>
      toxConnection.map(
        (c) => ToxEventSelfConnectionStatus(connectionStatus: c),
      );

  Generator<ToxEventFriendRequest> get friendRequest => combine2(
    uint8List,
    publicKey,
    (m, k) => ToxEventFriendRequest(message: m, publicKey: k),
  );

  Generator<ToxEventFriendMessage> get friendMessage => combine3(
    int32,
    toxMessageType,
    uint8List,
    (fn, t, m) => ToxEventFriendMessage(
      friendNumber: fn,
      type: t,
      messageLength: m.length,
      message: m,
    ),
  );

  Generator<ToxEventDhtNodesResponse> get dhtNodesResponse => combine3(
    publicKey,
    uint8List,
    int32,
    (k, ip, p) => ToxEventDhtNodesResponse(publicKey: k, ip: ip, port: p),
  );

  Generator<ToxEventFriendConnectionStatus> get friendConnectionStatus =>
      combine2(
        toxConnection,
        int32,
        (c, fn) => ToxEventFriendConnectionStatus(
          connectionStatus: c,
          friendNumber: fn,
        ),
      );

  Generator<ToxEventGroupInvite> get groupInvite => combine3(
    int32,
    uint8List,
    uint8List,
    (fn, id, gn) =>
        ToxEventGroupInvite(friendNumber: fn, inviteData: id, groupName: gn),
  );

  Generator<ToxEventGroupMessage> get groupMessage => combine5(
    int32,
    int32,
    toxMessageType,
    uint8List,
    int32,
    (gn, pi, mt, m, mi) => ToxEventGroupMessage(
      groupNumber: gn,
      peerId: pi,
      messageType: mt,
      message: m,
      messageId: mi,
    ),
  );

  Generator<ToxEventGroupPeerExit> get groupPeerExit => combine5(
    int32,
    int32,
    toxGroupExitType,
    uint8List,
    uint8List,
    (gn, pi, et, n, pm) => ToxEventGroupPeerExit(
      groupNumber: gn,
      peerId: pi,
      exitType: et,
      name: n,
      partMessage: pm,
    ),
  );

  Generator<ToxEventConferenceConnected> get conferenceConnected =>
      int32.map((cn) => ToxEventConferenceConnected(conferenceNumber: cn));

  Generator<ToxEventConferenceInvite> get conferenceInvite => combine3(
    uint8List,
    toxConferenceType,
    int32,
    (c, t, fn) =>
        ToxEventConferenceInvite(cookie: c, type: t, friendNumber: fn),
  );

  Generator<ToxEventConferenceMessage> get conferenceMessage => combine4(
    uint8List,
    toxMessageType,
    int32,
    int32,
    (m, t, cn, pn) => ToxEventConferenceMessage(
      message: m,
      type: t,
      conferenceNumber: cn,
      peerNumber: pn,
    ),
  );

  Generator<ToxEventConferencePeerListChanged> get conferencePeerListChanged =>
      int32.map(
        (cn) => ToxEventConferencePeerListChanged(conferenceNumber: cn),
      );

  Generator<ToxEventConferencePeerName> get conferencePeerName => combine3(
    uint8List,
    int32,
    int32,
    (n, cn, pn) => ToxEventConferencePeerName(
      name: n,
      conferenceNumber: cn,
      peerNumber: pn,
    ),
  );

  Generator<ToxEventConferenceTitle> get conferenceTitle => combine3(
    uint8List,
    int32,
    int32,
    (t, cn, pn) =>
        ToxEventConferenceTitle(title: t, conferenceNumber: cn, peerNumber: pn),
  );

  Generator<ToxEventFileChunkRequest> get fileChunkRequest => combine4(
    int32,
    int32,
    int32,
    int32,
    (l, fn, frn, p) => ToxEventFileChunkRequest(
      length: l,
      fileNumber: fn,
      friendNumber: frn,
      position: p,
    ),
  );

  Generator<ToxEventFileRecv> get fileRecv => combine5(
    uint8List,
    int32,
    int32,
    int32,
    int32,
    (n, fn, fs, frn, k) => ToxEventFileRecv(
      filename: n,
      fileNumber: fn,
      fileSize: fs,
      friendNumber: frn,
      kind: k,
    ),
  );

  Generator<ToxEventFileRecvChunk> get fileRecvChunk => combine4(
    uint8List,
    int32,
    int32,
    int32,
    (d, fn, frn, p) => ToxEventFileRecvChunk(
      data: d,
      fileNumber: fn,
      friendNumber: frn,
      position: p,
    ),
  );

  Generator<ToxEventFileRecvControl> get fileRecvControl => combine3(
    toxFileControl,
    int32,
    int32,
    (c, fn, frn) =>
        ToxEventFileRecvControl(control: c, fileNumber: fn, friendNumber: frn),
  );

  Generator<ToxEventFriendLosslessPacket> get friendLosslessPacket => combine3(
    uint8List,
    int32,
    int32,
    (d, dl, fn) =>
        ToxEventFriendLosslessPacket(data: d, dataLength: dl, friendNumber: fn),
  );

  Generator<ToxEventFriendLossyPacket> get friendLossyPacket => combine3(
    uint8List,
    int32,
    int32,
    (d, dl, fn) =>
        ToxEventFriendLossyPacket(data: d, dataLength: dl, friendNumber: fn),
  );

  Generator<ToxEventFriendName> get friendName => combine2(
    uint8List,
    int32,
    (n, fn) => ToxEventFriendName(name: n, friendNumber: fn),
  );

  Generator<ToxEventFriendReadReceipt> get friendReadReceipt => combine2(
    int32,
    int32,
    (fn, mi) => ToxEventFriendReadReceipt(friendNumber: fn, messageId: mi),
  );

  Generator<ToxEventFriendStatus> get friendStatus => combine2(
    toxUserStatus,
    int32,
    (s, fn) => ToxEventFriendStatus(status: s, friendNumber: fn),
  );

  Generator<ToxEventFriendStatusMessage> get friendStatusMessage => combine2(
    uint8List,
    int32,
    (m, fn) => ToxEventFriendStatusMessage(message: m, friendNumber: fn),
  );

  Generator<ToxEventFriendTyping> get friendTyping => combine2(
    this.bool,
    int32,
    (t, fn) => ToxEventFriendTyping(typing: t, friendNumber: fn),
  );

  Generator<ToxEventGroupCustomPacket> get groupCustomPacket => combine3(
    int32,
    int32,
    uint8List,
    (gn, pi, d) =>
        ToxEventGroupCustomPacket(groupNumber: gn, peerId: pi, data: d),
  );

  Generator<ToxEventGroupCustomPrivatePacket> get groupCustomPrivatePacket =>
      combine3(
        int32,
        int32,
        uint8List,
        (gn, pi, d) => ToxEventGroupCustomPrivatePacket(
          groupNumber: gn,
          peerId: pi,
          data: d,
        ),
      );

  Generator<ToxEventGroupJoinFail> get groupJoinFail => combine2(
    int32,
    toxGroupJoinFail,
    (gn, ft) => ToxEventGroupJoinFail(groupNumber: gn, failType: ft),
  );

  Generator<ToxEventGroupModeration> get groupModeration => combine4(
    int32,
    int32,
    int32,
    toxGroupModEvent,
    (gn, sp, tp, mt) => ToxEventGroupModeration(
      groupNumber: gn,
      sourcePeerId: sp,
      targetPeerId: tp,
      modType: mt,
    ),
  );

  Generator<ToxEventGroupPassword> get groupPassword => combine2(
    int32,
    uint8List,
    (gn, p) => ToxEventGroupPassword(groupNumber: gn, password: p),
  );

  Generator<ToxEventGroupPeerJoin> get groupPeerJoin => combine2(
    int32,
    int32,
    (gn, pi) => ToxEventGroupPeerJoin(groupNumber: gn, peerId: pi),
  );

  Generator<ToxEventGroupPeerLimit> get groupPeerLimit => combine2(
    int32,
    int32,
    (gn, pl) => ToxEventGroupPeerLimit(groupNumber: gn, peerLimit: pl),
  );

  Generator<ToxEventGroupPeerName> get groupPeerName => combine3(
    int32,
    int32,
    uint8List,
    (gn, pi, n) => ToxEventGroupPeerName(groupNumber: gn, peerId: pi, name: n),
  );

  Generator<ToxEventGroupPeerStatus> get groupPeerStatus => combine3(
    int32,
    int32,
    toxUserStatus,
    (gn, pi, s) =>
        ToxEventGroupPeerStatus(groupNumber: gn, peerId: pi, status: s),
  );

  Generator<ToxEventGroupPrivacyState> get groupPrivacyState => combine2(
    int32,
    toxGroupPrivacyState,
    (gn, ps) => ToxEventGroupPrivacyState(groupNumber: gn, privacyState: ps),
  );

  Generator<ToxEventGroupPrivateMessage> get groupPrivateMessage => combine5(
    int32,
    int32,
    toxMessageType,
    uint8List,
    int32,
    (gn, pi, mt, m, mi) => ToxEventGroupPrivateMessage(
      groupNumber: gn,
      peerId: pi,
      messageType: mt,
      message: m,
      messageId: mi,
    ),
  );

  Generator<ToxEventGroupSelfJoin> get groupSelfJoin =>
      int32.map((gn) => ToxEventGroupSelfJoin(groupNumber: gn));

  Generator<ToxEventGroupTopic> get groupTopic => combine3(
    int32,
    int32,
    uint8List,
    (gn, pi, t) => ToxEventGroupTopic(groupNumber: gn, peerId: pi, topic: t),
  );

  Generator<ToxEventGroupTopicLock> get groupTopicLock => combine2(
    int32,
    toxGroupTopicLock,
    (gn, tl) => ToxEventGroupTopicLock(groupNumber: gn, topicLock: tl),
  );

  Generator<ToxEventGroupVoiceState> get groupVoiceState => combine2(
    int32,
    toxGroupVoiceState,
    (gn, vs) => ToxEventGroupVoiceState(groupNumber: gn, voiceState: vs),
  );

  // The Unified Generator
  Generator<Event> get event => oneOf([
    selfConnectionStatus,
    friendRequest,
    friendMessage,
    dhtNodesResponse,
    friendConnectionStatus,
    groupInvite,
    groupMessage,
    groupPeerExit,
    conferenceConnected,
    conferenceInvite,
    conferenceMessage,
    conferencePeerListChanged,
    conferencePeerName,
    conferenceTitle,
    fileChunkRequest,
    fileRecv,
    fileRecvChunk,
    fileRecvControl,
    friendLosslessPacket,
    friendLossyPacket,
    friendName,
    friendReadReceipt,
    friendStatus,
    friendStatusMessage,
    friendTyping,
    groupCustomPacket,
    groupCustomPrivatePacket,
    groupJoinFail,
    groupModeration,
    groupPassword,
    groupPeerJoin,
    groupPeerLimit,
    groupPeerName,
    groupPeerStatus,
    groupPrivacyState,
    groupPrivateMessage,
    groupSelfJoin,
    groupTopic,
    groupTopicLock,
    groupVoiceState,
  ]);
}

void main() {
  Glados(any.event).test('Event round-trip property', (event) {
    final packer = Packer();
    event.pack(packer);
    final bytes = packer.takeBytes();

    final unpacker = Unpacker(bytes);
    final unpacked = Event.unpack(unpacker, event.eventType);

    expect(unpacked, event);
  });

  Glados(any.list(any.event))
      .test('Event list round-trip property (Batch mode)', (events) {
        final packer = Packer();
        packer.packListLength(events.length);
        for (final e in events) {
          packer.packListLength(2);
          packer.packInt(e.eventType.value);
          e.pack(packer);
        }

        final bytes = packer.takeBytes();
        final unpackedList = Event.unpackList(Unpacker(bytes));

        expect(unpackedList, events);
      });
}
