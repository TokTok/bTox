// ignore_for_file: invalid_annotation_target
import 'dart:typed_data';

import 'package:btox/ffi/toxcore.dart';
import 'package:btox/models/crypto.dart';
import 'package:btox/packets/converters.dart';
import 'package:btox/packets/messagepack.dart';
import 'package:btox/packets/packet.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'tox_events.freezed.dart';
part 'tox_events.g.dart';

@freezed
sealed class Event extends Packet with _$Event {
  const Event._();

  const factory Event.conferenceConnected({required int conferenceNumber}) =
      ToxEventConferenceConnected;

  const factory Event.conferenceInvite({
    @Uint8ListConverter() required Uint8List cookie,
    required Tox_Conference_Type type,
    required int friendNumber,
  }) = ToxEventConferenceInvite;

  const factory Event.conferenceMessage({
    @Uint8ListConverter() required Uint8List message,
    required Tox_Message_Type type,
    required int conferenceNumber,
    required int peerNumber,
  }) = ToxEventConferenceMessage;

  const factory Event.conferencePeerListChanged({
    required int conferenceNumber,
  }) = ToxEventConferencePeerListChanged;

  const factory Event.conferencePeerName({
    @Uint8ListConverter() required Uint8List name,
    required int conferenceNumber,
    required int peerNumber,
  }) = ToxEventConferencePeerName;

  const factory Event.conferenceTitle({
    @Uint8ListConverter() required Uint8List title,
    required int conferenceNumber,
    required int peerNumber,
  }) = ToxEventConferenceTitle;

  const factory Event.dhtNodesResponse({
    required PublicKey publicKey,
    required String ip,
    required int port,
  }) = ToxEventDhtNodesResponse;

  const factory Event.fileChunkRequest({
    required int length,
    required int fileNumber,
    required int friendNumber,
    required int position,
  }) = ToxEventFileChunkRequest;

  const factory Event.fileRecv({
    @Uint8ListConverter() required Uint8List filename,
    required int fileNumber,
    required int fileSize,
    required int friendNumber,
    required int kind,
  }) = ToxEventFileRecv;

  const factory Event.fileRecvChunk({
    @Uint8ListConverter() required Uint8List data,
    required int fileNumber,
    required int friendNumber,
    required int position,
  }) = ToxEventFileRecvChunk;

  const factory Event.fileRecvControl({
    required Tox_File_Control control,
    required int fileNumber,
    required int friendNumber,
  }) = ToxEventFileRecvControl;

  const factory Event.friendConnectionStatus({
    required Tox_Connection connectionStatus,
    required int friendNumber,
  }) = ToxEventFriendConnectionStatus;

  const factory Event.friendLosslessPacket({
    @Uint8ListConverter() required Uint8List data,
    required int dataLength,
    required int friendNumber,
  }) = ToxEventFriendLosslessPacket;

  const factory Event.friendLossyPacket({
    @Uint8ListConverter() required Uint8List data,
    required int dataLength,
    required int friendNumber,
  }) = ToxEventFriendLossyPacket;

  const factory Event.friendMessage({
    required int friendNumber,
    required Tox_Message_Type type,
    required int messageLength,
    @Uint8ListConverter() required Uint8List message,
  }) = ToxEventFriendMessage;

  const factory Event.friendName({
    @Uint8ListConverter() required Uint8List name,
    required int friendNumber,
  }) = ToxEventFriendName;

  const factory Event.friendReadReceipt({
    required int friendNumber,
    required int messageId,
  }) = ToxEventFriendReadReceipt;

  const factory Event.friendRequest({
    @Uint8ListConverter() required Uint8List message,
    required PublicKey publicKey,
  }) = ToxEventFriendRequest;

  const factory Event.friendStatus({
    required Tox_User_Status status,
    required int friendNumber,
  }) = ToxEventFriendStatus;

  const factory Event.friendStatusMessage({
    @Uint8ListConverter() required Uint8List message,
    required int friendNumber,
  }) = ToxEventFriendStatusMessage;

  const factory Event.friendTyping({
    required bool typing,
    required int friendNumber,
  }) = ToxEventFriendTyping;

  const factory Event.groupCustomPacket({
    required int groupNumber,
    required int peerId,
    @Uint8ListConverter() required Uint8List data,
  }) = ToxEventGroupCustomPacket;

  const factory Event.groupCustomPrivatePacket({
    required int groupNumber,
    required int peerId,
    @Uint8ListConverter() required Uint8List data,
  }) = ToxEventGroupCustomPrivatePacket;

  const factory Event.groupInvite({
    required int friendNumber,
    @Uint8ListConverter() required Uint8List inviteData,
    @Uint8ListConverter() required Uint8List groupName,
  }) = ToxEventGroupInvite;

  const factory Event.groupJoinFail({
    required int groupNumber,
    required Tox_Group_Join_Fail failType,
  }) = ToxEventGroupJoinFail;

  const factory Event.groupMessage({
    required int groupNumber,
    required int peerId,
    required Tox_Message_Type messageType,
    @Uint8ListConverter() required Uint8List message,
    required int messageId,
  }) = ToxEventGroupMessage;

  const factory Event.groupModeration({
    required int groupNumber,
    required int sourcePeerId,
    required int targetPeerId,
    required Tox_Group_Mod_Event modType,
  }) = ToxEventGroupModeration;

  const factory Event.groupPassword({
    required int groupNumber,
    @Uint8ListConverter() required Uint8List password,
  }) = ToxEventGroupPassword;

  const factory Event.groupPeerExit({
    required int groupNumber,
    required int peerId,
    required Tox_Group_Exit_Type exitType,
    @Uint8ListConverter() required Uint8List name,
    @Uint8ListConverter() required Uint8List partMessage,
  }) = ToxEventGroupPeerExit;

  const factory Event.groupPeerJoin({
    required int groupNumber,
    required int peerId,
  }) = ToxEventGroupPeerJoin;

  const factory Event.groupPeerLimit({
    required int groupNumber,
    required int peerLimit,
  }) = ToxEventGroupPeerLimit;

  const factory Event.groupPeerName({
    required int groupNumber,
    required int peerId,
    @Uint8ListConverter() required Uint8List name,
  }) = ToxEventGroupPeerName;

  const factory Event.groupPeerStatus({
    required int groupNumber,
    required int peerId,
    required Tox_User_Status status,
  }) = ToxEventGroupPeerStatus;

  const factory Event.groupPrivacyState({
    required int groupNumber,
    required Tox_Group_Privacy_State privacyState,
  }) = ToxEventGroupPrivacyState;

  const factory Event.groupPrivateMessage({
    required int groupNumber,
    required int peerId,
    required Tox_Message_Type messageType,
    @Uint8ListConverter() required Uint8List message,
    required int messageId,
  }) = ToxEventGroupPrivateMessage;

  const factory Event.groupSelfJoin({required int groupNumber}) =
      ToxEventGroupSelfJoin;

  const factory Event.groupTopic({
    required int groupNumber,
    required int peerId,
    @Uint8ListConverter() required Uint8List topic,
  }) = ToxEventGroupTopic;

  const factory Event.groupTopicLock({
    required int groupNumber,
    required Tox_Group_Topic_Lock topicLock,
  }) = ToxEventGroupTopicLock;

  const factory Event.groupVoiceState({
    required int groupNumber,
    required Tox_Group_Voice_State voiceState,
  }) = ToxEventGroupVoiceState;

  const factory Event.selfConnectionStatus({
    required Tox_Connection connectionStatus,
  }) = ToxEventSelfConnectionStatus;

  factory Event.fromJson(Map<String, dynamic> json) => _$EventFromJson(json);

  Tox_Event_Type get eventType => map(
    conferenceConnected: (_) => Tox_Event_Type.TOX_EVENT_CONFERENCE_CONNECTED,
    conferenceInvite: (_) => Tox_Event_Type.TOX_EVENT_CONFERENCE_INVITE,
    conferenceMessage: (_) => Tox_Event_Type.TOX_EVENT_CONFERENCE_MESSAGE,
    conferencePeerListChanged: (_) =>
        Tox_Event_Type.TOX_EVENT_CONFERENCE_PEER_LIST_CHANGED,
    conferencePeerName: (_) => Tox_Event_Type.TOX_EVENT_CONFERENCE_PEER_NAME,
    conferenceTitle: (_) => Tox_Event_Type.TOX_EVENT_CONFERENCE_TITLE,
    dhtNodesResponse: (_) => Tox_Event_Type.TOX_EVENT_DHT_NODES_RESPONSE,
    fileChunkRequest: (_) => Tox_Event_Type.TOX_EVENT_FILE_CHUNK_REQUEST,
    fileRecv: (_) => Tox_Event_Type.TOX_EVENT_FILE_RECV,
    fileRecvChunk: (_) => Tox_Event_Type.TOX_EVENT_FILE_RECV_CHUNK,
    fileRecvControl: (_) => Tox_Event_Type.TOX_EVENT_FILE_RECV_CONTROL,
    friendConnectionStatus: (_) =>
        Tox_Event_Type.TOX_EVENT_FRIEND_CONNECTION_STATUS,
    friendLosslessPacket: (_) =>
        Tox_Event_Type.TOX_EVENT_FRIEND_LOSSLESS_PACKET,
    friendLossyPacket: (_) => Tox_Event_Type.TOX_EVENT_FRIEND_LOSSY_PACKET,
    friendMessage: (_) => Tox_Event_Type.TOX_EVENT_FRIEND_MESSAGE,
    friendName: (_) => Tox_Event_Type.TOX_EVENT_FRIEND_NAME,
    friendReadReceipt: (_) => Tox_Event_Type.TOX_EVENT_FRIEND_READ_RECEIPT,
    friendRequest: (_) => Tox_Event_Type.TOX_EVENT_FRIEND_REQUEST,
    friendStatus: (_) => Tox_Event_Type.TOX_EVENT_FRIEND_STATUS,
    friendStatusMessage: (_) => Tox_Event_Type.TOX_EVENT_FRIEND_STATUS_MESSAGE,
    friendTyping: (_) => Tox_Event_Type.TOX_EVENT_FRIEND_TYPING,
    groupCustomPacket: (_) => Tox_Event_Type.TOX_EVENT_GROUP_CUSTOM_PACKET,
    groupCustomPrivatePacket: (_) =>
        Tox_Event_Type.TOX_EVENT_GROUP_CUSTOM_PRIVATE_PACKET,
    groupInvite: (_) => Tox_Event_Type.TOX_EVENT_GROUP_INVITE,
    groupJoinFail: (_) => Tox_Event_Type.TOX_EVENT_GROUP_JOIN_FAIL,
    groupMessage: (_) => Tox_Event_Type.TOX_EVENT_GROUP_MESSAGE,
    groupModeration: (_) => Tox_Event_Type.TOX_EVENT_GROUP_MODERATION,
    groupPassword: (_) => Tox_Event_Type.TOX_EVENT_GROUP_PASSWORD,
    groupPeerExit: (_) => Tox_Event_Type.TOX_EVENT_GROUP_PEER_EXIT,
    groupPeerJoin: (_) => Tox_Event_Type.TOX_EVENT_GROUP_PEER_JOIN,
    groupPeerLimit: (_) => Tox_Event_Type.TOX_EVENT_GROUP_PEER_LIMIT,
    groupPeerName: (_) => Tox_Event_Type.TOX_EVENT_GROUP_PEER_NAME,
    groupPeerStatus: (_) => Tox_Event_Type.TOX_EVENT_GROUP_PEER_STATUS,
    groupPrivacyState: (_) => Tox_Event_Type.TOX_EVENT_GROUP_PRIVACY_STATE,
    groupPrivateMessage: (_) => Tox_Event_Type.TOX_EVENT_GROUP_PRIVATE_MESSAGE,
    groupSelfJoin: (_) => Tox_Event_Type.TOX_EVENT_GROUP_SELF_JOIN,
    groupTopic: (_) => Tox_Event_Type.TOX_EVENT_GROUP_TOPIC,
    groupTopicLock: (_) => Tox_Event_Type.TOX_EVENT_GROUP_TOPIC_LOCK,
    groupVoiceState: (_) => Tox_Event_Type.TOX_EVENT_GROUP_VOICE_STATE,
    selfConnectionStatus: (_) =>
        Tox_Event_Type.TOX_EVENT_SELF_CONNECTION_STATUS,
  );

  @override
  void pack(Packer packer) => when(
    conferenceConnected: (conferenceNumber) => packer.packInt(conferenceNumber),
    conferenceInvite: (cookie, type, friendNumber) => packer
      ..packListLength(3)
      ..packBinary(cookie)
      ..packInt(type.value)
      ..packInt(friendNumber),
    conferenceMessage: (message, type, conferenceNumber, peerNumber) => packer
      ..packListLength(4)
      ..packBinary(message)
      ..packInt(type.value)
      ..packInt(conferenceNumber)
      ..packInt(peerNumber),
    conferencePeerListChanged: (conferenceNumber) =>
        packer.packInt(conferenceNumber),
    conferencePeerName: (name, conferenceNumber, peerNumber) => packer
      ..packListLength(3)
      ..packBinary(name)
      ..packInt(conferenceNumber)
      ..packInt(peerNumber),
    conferenceTitle: (title, conferenceNumber, peerNumber) => packer
      ..packListLength(3)
      ..packBinary(title)
      ..packInt(conferenceNumber)
      ..packInt(peerNumber),
    dhtNodesResponse: (publicKey, ip, port) => packer
      ..packListLength(3)
      ..pack(publicKey)
      ..packString(ip)
      ..packInt(port),
    fileChunkRequest: (length, fileNumber, friendNumber, position) => packer
      ..packListLength(4)
      ..packInt(length)
      ..packInt(fileNumber)
      ..packInt(friendNumber)
      ..packInt(position),
    fileRecv: (filename, fileNumber, fileSize, friendNumber, kind) => packer
      ..packListLength(5)
      ..packBinary(filename)
      ..packInt(fileNumber)
      ..packInt(fileSize)
      ..packInt(friendNumber)
      ..packInt(kind),
    fileRecvChunk: (data, fileNumber, friendNumber, position) => packer
      ..packListLength(4)
      ..packBinary(data)
      ..packInt(fileNumber)
      ..packInt(friendNumber)
      ..packInt(position),
    fileRecvControl: (control, fileNumber, friendNumber) => packer
      ..packListLength(3)
      ..packInt(control.value)
      ..packInt(fileNumber)
      ..packInt(friendNumber),
    friendConnectionStatus: (connectionStatus, friendNumber) => packer
      ..packListLength(2)
      ..packInt(connectionStatus.value)
      ..packInt(friendNumber),
    friendLosslessPacket: (data, dataLength, friendNumber) => packer
      ..packListLength(3)
      ..packBinary(data)
      ..packInt(dataLength)
      ..packInt(friendNumber),
    friendLossyPacket: (data, dataLength, friendNumber) => packer
      ..packListLength(3)
      ..packBinary(data)
      ..packInt(dataLength)
      ..packInt(friendNumber),
    friendMessage: (friendNumber, type, messageLength, message) => packer
      ..packListLength(4)
      ..packInt(friendNumber)
      ..packInt(type.value)
      ..packInt(messageLength)
      ..packBinary(message),
    friendName: (name, friendNumber) => packer
      ..packListLength(2)
      ..packBinary(name)
      ..packInt(friendNumber),
    friendReadReceipt: (friendNumber, messageId) => packer
      ..packListLength(2)
      ..packInt(friendNumber)
      ..packInt(messageId),
    friendRequest: (message, publicKey) => packer
      ..packListLength(2)
      ..packBinary(message)
      ..pack(publicKey),
    friendStatus: (status, friendNumber) => packer
      ..packListLength(2)
      ..packInt(status.value)
      ..packInt(friendNumber),
    friendStatusMessage: (message, friendNumber) => packer
      ..packListLength(2)
      ..packBinary(message)
      ..packInt(friendNumber),
    friendTyping: (typing, friendNumber) => packer
      ..packListLength(2)
      ..packBool(typing)
      ..packInt(friendNumber),
    groupCustomPacket: (groupNumber, peerId, data) => packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packBinary(data),
    groupCustomPrivatePacket: (groupNumber, peerId, data) => packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packBinary(data),
    groupInvite: (friendNumber, inviteData, groupName) => packer
      ..packListLength(3)
      ..packInt(friendNumber)
      ..packBinary(inviteData)
      ..packBinary(groupName),
    groupJoinFail: (groupNumber, failType) => packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(failType.value),
    groupMessage: (groupNumber, peerId, messageType, message, messageId) =>
        packer
          ..packListLength(5)
          ..packInt(groupNumber)
          ..packInt(peerId)
          ..packInt(messageType.value)
          ..packBinary(message)
          ..packInt(messageId),
    groupModeration: (groupNumber, sourcePeerId, targetPeerId, modType) =>
        packer
          ..packListLength(4)
          ..packInt(groupNumber)
          ..packInt(sourcePeerId)
          ..packInt(targetPeerId)
          ..packInt(modType.value),
    groupPassword: (groupNumber, password) => packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packBinary(password),
    groupPeerExit: (groupNumber, peerId, exitType, name, partMessage) => packer
      ..packListLength(5)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packInt(exitType.value)
      ..packBinary(name)
      ..packBinary(partMessage),
    groupPeerJoin: (groupNumber, peerId) => packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(peerId),
    groupPeerLimit: (groupNumber, peerLimit) => packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(peerLimit),
    groupPeerName: (groupNumber, peerId, name) => packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packBinary(name),
    groupPeerStatus: (groupNumber, peerId, status) => packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packInt(status.value),
    groupPrivacyState: (groupNumber, privacyState) => packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(privacyState.value),
    groupPrivateMessage:
        (groupNumber, peerId, messageType, message, messageId) => packer
          ..packListLength(5)
          ..packInt(groupNumber)
          ..packInt(peerId)
          ..packInt(messageType.value)
          ..packBinary(message)
          ..packInt(messageId),
    groupSelfJoin: (groupNumber) => packer.packInt(groupNumber),
    groupTopic: (groupNumber, peerId, topic) => packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packBinary(topic),
    groupTopicLock: (groupNumber, topicLock) => packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(topicLock.value),
    groupVoiceState: (groupNumber, voiceState) => packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(voiceState.value),
    selfConnectionStatus: (connectionStatus) =>
        packer.packInt(connectionStatus.value),
  );

  factory Event.unpack(Unpacker unpacker, Tox_Event_Type type) {
    switch (type) {
      case Tox_Event_Type.TOX_EVENT_SELF_CONNECTION_STATUS:
        return Event.selfConnectionStatus(
          connectionStatus: Tox_Connection.fromValue(unpacker.unpackInt()!),
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_REQUEST:
        ensure(unpacker.unpackListLength(), 2);
        return Event.friendRequest(
          message: unpacker.unpackBinary()!,
          publicKey: PublicKey.unpack(unpacker),
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_CONNECTION_STATUS:
        ensure(unpacker.unpackListLength(), 2);
        return Event.friendConnectionStatus(
          connectionStatus: Tox_Connection.fromValue(unpacker.unpackInt()!),
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_LOSSY_PACKET:
        ensure(unpacker.unpackListLength(), 3);
        return Event.friendLossyPacket(
          data: unpacker.unpackBinary()!,
          dataLength: unpacker.unpackInt()!,
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_LOSSLESS_PACKET:
        ensure(unpacker.unpackListLength(), 3);
        return Event.friendLosslessPacket(
          data: unpacker.unpackBinary()!,
          dataLength: unpacker.unpackInt()!,
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_NAME:
        ensure(unpacker.unpackListLength(), 2);
        return Event.friendName(
          name: unpacker.unpackBinary()!,
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_STATUS:
        ensure(unpacker.unpackListLength(), 2);
        return Event.friendStatus(
          status: Tox_User_Status.fromValue(unpacker.unpackInt()!),
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_STATUS_MESSAGE:
        ensure(unpacker.unpackListLength(), 2);
        return Event.friendStatusMessage(
          message: unpacker.unpackBinary()!,
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_MESSAGE:
        ensure(unpacker.unpackListLength(), 4);
        return Event.friendMessage(
          friendNumber: unpacker.unpackInt()!,
          type: Tox_Message_Type.fromValue(unpacker.unpackInt()!),
          messageLength: unpacker.unpackInt()!,
          message: unpacker.unpackBinary()!,
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_READ_RECEIPT:
        ensure(unpacker.unpackListLength(), 2);
        return Event.friendReadReceipt(
          friendNumber: unpacker.unpackInt()!,
          messageId: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FRIEND_TYPING:
        ensure(unpacker.unpackListLength(), 2);
        return Event.friendTyping(
          typing: unpacker.unpackBool()!,
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FILE_CHUNK_REQUEST:
        ensure(unpacker.unpackListLength(), 4);
        return Event.fileChunkRequest(
          length: unpacker.unpackInt()!,
          fileNumber: unpacker.unpackInt()!,
          friendNumber: unpacker.unpackInt()!,
          position: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FILE_RECV:
        ensure(unpacker.unpackListLength(), 5);
        return Event.fileRecv(
          filename: unpacker.unpackBinary()!,
          fileNumber: unpacker.unpackInt()!,
          fileSize: unpacker.unpackInt()!,
          friendNumber: unpacker.unpackInt()!,
          kind: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FILE_RECV_CHUNK:
        ensure(unpacker.unpackListLength(), 4);
        return Event.fileRecvChunk(
          data: unpacker.unpackBinary()!,
          fileNumber: unpacker.unpackInt()!,
          friendNumber: unpacker.unpackInt()!,
          position: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_FILE_RECV_CONTROL:
        ensure(unpacker.unpackListLength(), 3);
        return Event.fileRecvControl(
          control: Tox_File_Control.fromValue(unpacker.unpackInt()!),
          fileNumber: unpacker.unpackInt()!,
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_INVITE:
        ensure(unpacker.unpackListLength(), 3);
        return Event.conferenceInvite(
          cookie: unpacker.unpackBinary()!,
          type: Tox_Conference_Type.fromValue(unpacker.unpackInt()!),
          friendNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_CONNECTED:
        return Event.conferenceConnected(
          conferenceNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_PEER_LIST_CHANGED:
        return Event.conferencePeerListChanged(
          conferenceNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_PEER_NAME:
        ensure(unpacker.unpackListLength(), 3);
        return Event.conferencePeerName(
          name: unpacker.unpackBinary()!,
          conferenceNumber: unpacker.unpackInt()!,
          peerNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_TITLE:
        ensure(unpacker.unpackListLength(), 3);
        return Event.conferenceTitle(
          title: unpacker.unpackBinary()!,
          conferenceNumber: unpacker.unpackInt()!,
          peerNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_MESSAGE:
        ensure(unpacker.unpackListLength(), 4);
        return Event.conferenceMessage(
          message: unpacker.unpackBinary()!,
          type: Tox_Message_Type.fromValue(unpacker.unpackInt()!),
          conferenceNumber: unpacker.unpackInt()!,
          peerNumber: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_CUSTOM_PACKET:
        ensure(unpacker.unpackListLength(), 3);
        return Event.groupCustomPacket(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
          data: unpacker.unpackBinary()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_CUSTOM_PRIVATE_PACKET:
        ensure(unpacker.unpackListLength(), 3);
        return Event.groupCustomPrivatePacket(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
          data: unpacker.unpackBinary()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_INVITE:
        ensure(unpacker.unpackListLength(), 3);
        return Event.groupInvite(
          friendNumber: unpacker.unpackInt()!,
          inviteData: unpacker.unpackBinary()!,
          groupName: unpacker.unpackBinary()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_JOIN:
        ensure(unpacker.unpackListLength(), 2);
        return Event.groupPeerJoin(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_EXIT:
        ensure(unpacker.unpackListLength(), 5);
        return Event.groupPeerExit(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
          exitType: Tox_Group_Exit_Type.fromValue(unpacker.unpackInt()!),
          name: unpacker.unpackBinary()!,
          partMessage: unpacker.unpackBinary()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_NAME:
        ensure(unpacker.unpackListLength(), 3);
        return Event.groupPeerName(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
          name: unpacker.unpackBinary()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_STATUS:
        ensure(unpacker.unpackListLength(), 3);
        return Event.groupPeerStatus(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
          status: Tox_User_Status.fromValue(unpacker.unpackInt()!),
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_TOPIC:
        ensure(unpacker.unpackListLength(), 3);
        return Event.groupTopic(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
          topic: unpacker.unpackBinary()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_PRIVACY_STATE:
        ensure(unpacker.unpackListLength(), 2);
        return Event.groupPrivacyState(
          groupNumber: unpacker.unpackInt()!,
          privacyState: Tox_Group_Privacy_State.fromValue(
            unpacker.unpackInt()!,
          ),
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_VOICE_STATE:
        ensure(unpacker.unpackListLength(), 2);
        return Event.groupVoiceState(
          groupNumber: unpacker.unpackInt()!,
          voiceState: Tox_Group_Voice_State.fromValue(unpacker.unpackInt()!),
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_TOPIC_LOCK:
        ensure(unpacker.unpackListLength(), 2);
        return Event.groupTopicLock(
          groupNumber: unpacker.unpackInt()!,
          topicLock: Tox_Group_Topic_Lock.fromValue(unpacker.unpackInt()!),
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_LIMIT:
        ensure(unpacker.unpackListLength(), 2);
        return Event.groupPeerLimit(
          groupNumber: unpacker.unpackInt()!,
          peerLimit: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_PASSWORD:
        ensure(unpacker.unpackListLength(), 2);
        return Event.groupPassword(
          groupNumber: unpacker.unpackInt()!,
          password: unpacker.unpackBinary()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_MESSAGE:
        ensure(unpacker.unpackListLength(), 5);
        return Event.groupMessage(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
          messageType: Tox_Message_Type.fromValue(unpacker.unpackInt()!),
          message: unpacker.unpackBinary()!,
          messageId: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_PRIVATE_MESSAGE:
        ensure(unpacker.unpackListLength(), 5);
        return Event.groupPrivateMessage(
          groupNumber: unpacker.unpackInt()!,
          peerId: unpacker.unpackInt()!,
          messageType: Tox_Message_Type.fromValue(unpacker.unpackInt()!),
          message: unpacker.unpackBinary()!,
          messageId: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_JOIN_FAIL:
        ensure(unpacker.unpackListLength(), 2);
        return Event.groupJoinFail(
          groupNumber: unpacker.unpackInt()!,
          failType: Tox_Group_Join_Fail.fromValue(unpacker.unpackInt()!),
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_MODERATION:
        ensure(unpacker.unpackListLength(), 4);
        return Event.groupModeration(
          groupNumber: unpacker.unpackInt()!,
          sourcePeerId: unpacker.unpackInt()!,
          targetPeerId: unpacker.unpackInt()!,
          modType: Tox_Group_Mod_Event.fromValue(unpacker.unpackInt()!),
        );
      case Tox_Event_Type.TOX_EVENT_GROUP_SELF_JOIN:
        return Event.groupSelfJoin(groupNumber: unpacker.unpackInt()!);
      case Tox_Event_Type.TOX_EVENT_DHT_NODES_RESPONSE:
        ensure(unpacker.unpackListLength(), 3);
        return Event.dhtNodesResponse(
          publicKey: PublicKey.unpack(unpacker),
          ip: unpacker.unpackString()!,
          port: unpacker.unpackInt()!,
        );
      case Tox_Event_Type.TOX_EVENT_INVALID:
        throw Exception('Invalid event type');
    }
  }

  static List<Event> unpackList(Unpacker unpacker) {
    return List.unmodifiable(
      List.generate(unpacker.unpackListLength(), (_) {
        ensure(unpacker.unpackListLength(), 2);
        return Event.unpack(
          unpacker,
          Tox_Event_Type.fromValue(unpacker.unpackInt()!),
        );
      }),
    );
  }
}

void ensure<T>(T a, T b) {
  if (a != b) {
    throw Exception('Expected $b but got $a');
  }
}
