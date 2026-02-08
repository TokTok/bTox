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

sealed class Event extends Packet {
  const Event();

  factory Event.unpack(Unpacker unpacker, Tox_Event_Type type) {
    switch (type) {
      case Tox_Event_Type.TOX_EVENT_SELF_CONNECTION_STATUS:
        return ToxEventSelfConnectionStatus.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_REQUEST:
        return ToxEventFriendRequest.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_CONNECTION_STATUS:
        return ToxEventFriendConnectionStatus.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_LOSSY_PACKET:
        return ToxEventFriendLossyPacket.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_LOSSLESS_PACKET:
        return ToxEventFriendLosslessPacket.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_NAME:
        return ToxEventFriendName.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_STATUS:
        return ToxEventFriendStatus.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_STATUS_MESSAGE:
        return ToxEventFriendStatusMessage.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_MESSAGE:
        return ToxEventFriendMessage.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_READ_RECEIPT:
        return ToxEventFriendReadReceipt.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FRIEND_TYPING:
        return ToxEventFriendTyping.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FILE_CHUNK_REQUEST:
        return ToxEventFileChunkRequest.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FILE_RECV:
        return ToxEventFileRecv.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FILE_RECV_CHUNK:
        return ToxEventFileRecvChunk.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_FILE_RECV_CONTROL:
        return ToxEventFileRecvControl.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_INVITE:
        return ToxEventConferenceInvite.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_CONNECTED:
        return ToxEventConferenceConnected.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_PEER_LIST_CHANGED:
        return ToxEventConferencePeerListChanged.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_PEER_NAME:
        return ToxEventConferencePeerName.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_TITLE:
        return ToxEventConferenceTitle.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_CONFERENCE_MESSAGE:
        return ToxEventConferenceMessage.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_CUSTOM_PACKET:
        return ToxEventGroupCustomPacket.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_CUSTOM_PRIVATE_PACKET:
        return ToxEventGroupCustomPrivatePacket.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_INVITE:
        return ToxEventGroupInvite.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_JOIN:
        return ToxEventGroupPeerJoin.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_EXIT:
        return ToxEventGroupPeerExit.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_NAME:
        return ToxEventGroupPeerName.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_STATUS:
        return ToxEventGroupPeerStatus.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_TOPIC:
        return ToxEventGroupTopic.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_PRIVACY_STATE:
        return ToxEventGroupPrivacyState.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_VOICE_STATE:
        return ToxEventGroupVoiceState.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_TOPIC_LOCK:
        return ToxEventGroupTopicLock.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_PEER_LIMIT:
        return ToxEventGroupPeerLimit.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_PASSWORD:
        return ToxEventGroupPassword.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_MESSAGE:
        return ToxEventGroupMessage.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_PRIVATE_MESSAGE:
        return ToxEventGroupPrivateMessage.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_JOIN_FAIL:
        return ToxEventGroupJoinFail.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_MODERATION:
        return ToxEventGroupModeration.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_GROUP_SELF_JOIN:
        return ToxEventGroupSelfJoin.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_DHT_NODES_RESPONSE:
        return ToxEventDhtNodesResponse.unpack(unpacker);
      case Tox_Event_Type.TOX_EVENT_INVALID:
        throw Exception('Invalid event type');
    }
  }

  static List<Event> unpackList(Unpacker unpacker) {
    return List.unmodifiable(List.generate(unpacker.unpackListLength(), (_) {
      ensure(unpacker.unpackListLength(), 2);
      return Event.unpack(
        unpacker,
        Tox_Event_Type.fromValue(unpacker.unpackInt()!),
      );
    }));
  }
}

@freezed
abstract class ToxEventConferenceConnected extends Event
    with _$ToxEventConferenceConnected {
  const ToxEventConferenceConnected._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventConferenceConnected({
    required int conferenceNumber,
  }) = _ToxEventConferenceConnected;

  factory ToxEventConferenceConnected.fromJson(Map<String, dynamic> json) =>
      _$ToxEventConferenceConnectedFromJson(json);

  factory ToxEventConferenceConnected.unpack(Unpacker unpacker) {
    return ToxEventConferenceConnected(
      conferenceNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer.packInt(conferenceNumber);
  }
}

@freezed
abstract class ToxEventConferenceInvite extends Event
    with _$ToxEventConferenceInvite {
  const ToxEventConferenceInvite._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventConferenceInvite({
    required Uint8List cookie,
    required Tox_Conference_Type type,
    required int friendNumber,
  }) = _ToxEventConferenceInvite;

  factory ToxEventConferenceInvite.fromJson(Map<String, dynamic> json) =>
      _$ToxEventConferenceInviteFromJson(json);

  factory ToxEventConferenceInvite.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventConferenceInvite(
      cookie: unpacker.unpackBinary()!,
      type: Tox_Conference_Type.fromValue(unpacker.unpackInt()!),
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packBinary(cookie)
      ..packInt(type.value)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventConferenceMessage extends Event
    with _$ToxEventConferenceMessage {
  const ToxEventConferenceMessage._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventConferenceMessage({
    required Uint8List message,
    required Tox_Message_Type type,
    required int conferenceNumber,
    required int peerNumber,
  }) = _ToxEventConferenceMessage;

  factory ToxEventConferenceMessage.fromJson(Map<String, dynamic> json) =>
      _$ToxEventConferenceMessageFromJson(json);

  factory ToxEventConferenceMessage.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 4);
    return ToxEventConferenceMessage(
      message: unpacker.unpackBinary()!,
      type: Tox_Message_Type.fromValue(unpacker.unpackInt()!),
      conferenceNumber: unpacker.unpackInt()!,
      peerNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(4)
      ..packBinary(message)
      ..packInt(type.value)
      ..packInt(conferenceNumber)
      ..packInt(peerNumber);
  }
}

@freezed
abstract class ToxEventConferencePeerListChanged extends Event
    with _$ToxEventConferencePeerListChanged {
  const ToxEventConferencePeerListChanged._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventConferencePeerListChanged({
    required int conferenceNumber,
  }) = _ToxEventConferencePeerListChanged;

  factory ToxEventConferencePeerListChanged.fromJson(
          Map<String, dynamic> json) =>
      _$ToxEventConferencePeerListChangedFromJson(json);

  factory ToxEventConferencePeerListChanged.unpack(Unpacker unpacker) {
    return ToxEventConferencePeerListChanged(
      conferenceNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer.packInt(conferenceNumber);
  }
}

@freezed
abstract class ToxEventConferencePeerName extends Event
    with _$ToxEventConferencePeerName {
  const ToxEventConferencePeerName._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventConferencePeerName({
    required Uint8List name,
    required int conferenceNumber,
    required int peerNumber,
  }) = _ToxEventConferencePeerName;

  factory ToxEventConferencePeerName.fromJson(Map<String, dynamic> json) =>
      _$ToxEventConferencePeerNameFromJson(json);

  factory ToxEventConferencePeerName.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventConferencePeerName(
      name: unpacker.unpackBinary()!,
      conferenceNumber: unpacker.unpackInt()!,
      peerNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packBinary(name)
      ..packInt(conferenceNumber)
      ..packInt(peerNumber);
  }
}

@freezed
abstract class ToxEventConferenceTitle extends Event
    with _$ToxEventConferenceTitle {
  const ToxEventConferenceTitle._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventConferenceTitle({
    required Uint8List title,
    required int conferenceNumber,
    required int peerNumber,
  }) = _ToxEventConferenceTitle;

  factory ToxEventConferenceTitle.fromJson(Map<String, dynamic> json) =>
      _$ToxEventConferenceTitleFromJson(json);

  factory ToxEventConferenceTitle.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventConferenceTitle(
      title: unpacker.unpackBinary()!,
      conferenceNumber: unpacker.unpackInt()!,
      peerNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packBinary(title)
      ..packInt(conferenceNumber)
      ..packInt(peerNumber);
  }
}

@freezed
abstract class ToxEventDhtNodesResponse extends Event
    with _$ToxEventDhtNodesResponse {
  const ToxEventDhtNodesResponse._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventDhtNodesResponse({
    required PublicKey publicKey,
    required Uint8List ip,
    required int port,
  }) = _ToxEventDhtNodesResponse;

  factory ToxEventDhtNodesResponse.fromJson(Map<String, dynamic> json) =>
      _$ToxEventDhtNodesResponseFromJson(json);

  factory ToxEventDhtNodesResponse.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventDhtNodesResponse(
      publicKey: PublicKey.unpack(unpacker),
      ip: unpacker.unpackBinary()!,
      port: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..pack(publicKey)
      ..packBinary(ip)
      ..packInt(port);
  }
}

@freezed
abstract class ToxEventFileChunkRequest extends Event
    with _$ToxEventFileChunkRequest {
  const ToxEventFileChunkRequest._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventFileChunkRequest({
    required int length,
    required int fileNumber,
    required int friendNumber,
    required int position,
  }) = _ToxEventFileChunkRequest;

  factory ToxEventFileChunkRequest.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFileChunkRequestFromJson(json);

  factory ToxEventFileChunkRequest.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 4);
    return ToxEventFileChunkRequest(
      length: unpacker.unpackInt()!,
      fileNumber: unpacker.unpackInt()!,
      friendNumber: unpacker.unpackInt()!,
      position: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(4)
      ..packInt(length)
      ..packInt(fileNumber)
      ..packInt(friendNumber)
      ..packInt(position);
  }
}

@freezed
abstract class ToxEventFileRecv extends Event with _$ToxEventFileRecv {
  const ToxEventFileRecv._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventFileRecv({
    required Uint8List filename,
    required int fileNumber,
    required int fileSize,
    required int friendNumber,
    required int kind,
  }) = _ToxEventFileRecv;

  factory ToxEventFileRecv.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFileRecvFromJson(json);

  factory ToxEventFileRecv.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 5);
    return ToxEventFileRecv(
      filename: unpacker.unpackBinary()!,
      fileNumber: unpacker.unpackInt()!,
      fileSize: unpacker.unpackInt()!,
      friendNumber: unpacker.unpackInt()!,
      kind: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(5)
      ..packBinary(filename)
      ..packInt(fileNumber)
      ..packInt(fileSize)
      ..packInt(friendNumber)
      ..packInt(kind);
  }
}

@freezed
abstract class ToxEventFileRecvChunk extends Event
    with _$ToxEventFileRecvChunk {
  const ToxEventFileRecvChunk._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventFileRecvChunk({
    required Uint8List data,
    required int fileNumber,
    required int friendNumber,
    required int position,
  }) = _ToxEventFileRecvChunk;

  factory ToxEventFileRecvChunk.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFileRecvChunkFromJson(json);

  factory ToxEventFileRecvChunk.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 4);
    return ToxEventFileRecvChunk(
      data: unpacker.unpackBinary()!,
      fileNumber: unpacker.unpackInt()!,
      friendNumber: unpacker.unpackInt()!,
      position: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(4)
      ..packBinary(data)
      ..packInt(fileNumber)
      ..packInt(friendNumber)
      ..packInt(position);
  }
}

@freezed
abstract class ToxEventFileRecvControl extends Event
    with _$ToxEventFileRecvControl {
  const ToxEventFileRecvControl._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventFileRecvControl({
    required Tox_File_Control control,
    required int fileNumber,
    required int friendNumber,
  }) = _ToxEventFileRecvControl;

  factory ToxEventFileRecvControl.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFileRecvControlFromJson(json);

  factory ToxEventFileRecvControl.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventFileRecvControl(
      control: Tox_File_Control.fromValue(unpacker.unpackInt()!),
      fileNumber: unpacker.unpackInt()!,
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packInt(control.value)
      ..packInt(fileNumber)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventFriendConnectionStatus extends Event
    with _$ToxEventFriendConnectionStatus {
  const ToxEventFriendConnectionStatus._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventFriendConnectionStatus({
    required Tox_Connection connectionStatus,
    required int friendNumber,
  }) = _ToxEventFriendConnectionStatus;

  factory ToxEventFriendConnectionStatus.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendConnectionStatusFromJson(json);

  factory ToxEventFriendConnectionStatus.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventFriendConnectionStatus(
      connectionStatus: Tox_Connection.fromValue(unpacker.unpackInt()!),
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(connectionStatus.value)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventFriendLosslessPacket extends Event
    with _$ToxEventFriendLosslessPacket {
  const ToxEventFriendLosslessPacket._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventFriendLosslessPacket({
    required Uint8List data,
    required int dataLength,
    required int friendNumber,
  }) = _ToxEventFriendLosslessPacket;

  factory ToxEventFriendLosslessPacket.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendLosslessPacketFromJson(json);

  factory ToxEventFriendLosslessPacket.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventFriendLosslessPacket(
      data: unpacker.unpackBinary()!,
      dataLength: unpacker.unpackInt()!,
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packBinary(data)
      ..packInt(dataLength)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventFriendLossyPacket extends Event
    with _$ToxEventFriendLossyPacket {
  const ToxEventFriendLossyPacket._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventFriendLossyPacket({
    required Uint8List data,
    required int dataLength,
    required int friendNumber,
  }) = _ToxEventFriendLossyPacket;

  factory ToxEventFriendLossyPacket.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendLossyPacketFromJson(json);

  factory ToxEventFriendLossyPacket.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventFriendLossyPacket(
      data: unpacker.unpackBinary()!,
      dataLength: unpacker.unpackInt()!,
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packBinary(data)
      ..packInt(dataLength)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventFriendMessage extends Event
    with _$ToxEventFriendMessage {
  const ToxEventFriendMessage._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventFriendMessage({
    required int friendNumber,
    required Tox_Message_Type type,
    required int messageLength,
    required Uint8List message,
  }) = _ToxEventFriendMessage;

  factory ToxEventFriendMessage.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendMessageFromJson(json);

  factory ToxEventFriendMessage.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 4);
    return ToxEventFriendMessage(
      friendNumber: unpacker.unpackInt()!,
      type: Tox_Message_Type.fromValue(unpacker.unpackInt()!),
      messageLength: unpacker.unpackInt()!,
      message: unpacker.unpackBinary()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(4)
      ..packInt(friendNumber)
      ..packInt(type.value)
      ..packInt(messageLength)
      ..packBinary(message);
  }
}

@freezed
abstract class ToxEventFriendName extends Event with _$ToxEventFriendName {
  const ToxEventFriendName._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventFriendName({
    required Uint8List name,
    required int friendNumber,
  }) = _ToxEventFriendName;

  factory ToxEventFriendName.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendNameFromJson(json);

  factory ToxEventFriendName.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventFriendName(
      name: unpacker.unpackBinary()!,
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packBinary(name)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventFriendReadReceipt extends Event
    with _$ToxEventFriendReadReceipt {
  const ToxEventFriendReadReceipt._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventFriendReadReceipt({
    required int friendNumber,
    required int messageId,
  }) = _ToxEventFriendReadReceipt;

  factory ToxEventFriendReadReceipt.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendReadReceiptFromJson(json);

  factory ToxEventFriendReadReceipt.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventFriendReadReceipt(
      friendNumber: unpacker.unpackInt()!,
      messageId: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(friendNumber)
      ..packInt(messageId);
  }
}

@freezed
abstract class ToxEventFriendRequest extends Event
    with _$ToxEventFriendRequest {
  const ToxEventFriendRequest._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventFriendRequest({
    required Uint8List message,
    required PublicKey publicKey,
  }) = _ToxEventFriendRequest;

  factory ToxEventFriendRequest.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendRequestFromJson(json);

  factory ToxEventFriendRequest.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventFriendRequest(
      message: unpacker.unpackBinary()!,
      publicKey: PublicKey.unpack(unpacker),
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packBinary(message)
      ..pack(publicKey);
  }
}

@freezed
abstract class ToxEventFriendStatus extends Event with _$ToxEventFriendStatus {
  const ToxEventFriendStatus._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventFriendStatus({
    required Tox_User_Status status,
    required int friendNumber,
  }) = _ToxEventFriendStatus;

  factory ToxEventFriendStatus.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendStatusFromJson(json);

  factory ToxEventFriendStatus.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventFriendStatus(
      status: Tox_User_Status.fromValue(unpacker.unpackInt()!),
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(status.value)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventFriendStatusMessage extends Event
    with _$ToxEventFriendStatusMessage {
  const ToxEventFriendStatusMessage._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventFriendStatusMessage({
    required Uint8List message,
    required int friendNumber,
  }) = _ToxEventFriendStatusMessage;

  factory ToxEventFriendStatusMessage.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendStatusMessageFromJson(json);

  factory ToxEventFriendStatusMessage.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventFriendStatusMessage(
      message: unpacker.unpackBinary()!,
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packBinary(message)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventFriendTyping extends Event with _$ToxEventFriendTyping {
  const ToxEventFriendTyping._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventFriendTyping({
    required bool typing,
    required int friendNumber,
  }) = _ToxEventFriendTyping;

  factory ToxEventFriendTyping.fromJson(Map<String, dynamic> json) =>
      _$ToxEventFriendTypingFromJson(json);

  factory ToxEventFriendTyping.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventFriendTyping(
      typing: unpacker.unpackBool()!,
      friendNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packBool(typing)
      ..packInt(friendNumber);
  }
}

@freezed
abstract class ToxEventGroupCustomPacket extends Event
    with _$ToxEventGroupCustomPacket {
  const ToxEventGroupCustomPacket._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupCustomPacket({
    required int groupNumber,
    required int peerId,
    required Uint8List data,
  }) = _ToxEventGroupCustomPacket;

  factory ToxEventGroupCustomPacket.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupCustomPacketFromJson(json);

  factory ToxEventGroupCustomPacket.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventGroupCustomPacket(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
      data: unpacker.unpackBinary()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packBinary(data);
  }
}

@freezed
abstract class ToxEventGroupCustomPrivatePacket extends Event
    with _$ToxEventGroupCustomPrivatePacket {
  const ToxEventGroupCustomPrivatePacket._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupCustomPrivatePacket({
    required int groupNumber,
    required int peerId,
    required Uint8List data,
  }) = _ToxEventGroupCustomPrivatePacket;

  factory ToxEventGroupCustomPrivatePacket.fromJson(
          Map<String, dynamic> json) =>
      _$ToxEventGroupCustomPrivatePacketFromJson(json);

  factory ToxEventGroupCustomPrivatePacket.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventGroupCustomPrivatePacket(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
      data: unpacker.unpackBinary()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packBinary(data);
  }
}

@freezed
abstract class ToxEventGroupInvite extends Event with _$ToxEventGroupInvite {
  const ToxEventGroupInvite._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupInvite({
    required int friendNumber,
    required Uint8List inviteData,
    required Uint8List groupName,
  }) = _ToxEventGroupInvite;

  factory ToxEventGroupInvite.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupInviteFromJson(json);

  factory ToxEventGroupInvite.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventGroupInvite(
      friendNumber: unpacker.unpackInt()!,
      inviteData: unpacker.unpackBinary()!,
      groupName: unpacker.unpackBinary()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packInt(friendNumber)
      ..packBinary(inviteData)
      ..packBinary(groupName);
  }
}

@freezed
abstract class ToxEventGroupJoinFail extends Event
    with _$ToxEventGroupJoinFail {
  const ToxEventGroupJoinFail._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupJoinFail({
    required int groupNumber,
    required Tox_Group_Join_Fail failType,
  }) = _ToxEventGroupJoinFail;

  factory ToxEventGroupJoinFail.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupJoinFailFromJson(json);

  factory ToxEventGroupJoinFail.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventGroupJoinFail(
      groupNumber: unpacker.unpackInt()!,
      failType: Tox_Group_Join_Fail.fromValue(unpacker.unpackInt()!),
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(failType.value);
  }
}

@freezed
abstract class ToxEventGroupMessage extends Event with _$ToxEventGroupMessage {
  const ToxEventGroupMessage._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupMessage({
    required int groupNumber,
    required int peerId,
    required Tox_Message_Type messageType,
    required Uint8List message,
    required int messageId,
  }) = _ToxEventGroupMessage;

  factory ToxEventGroupMessage.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupMessageFromJson(json);

  factory ToxEventGroupMessage.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 5);
    return ToxEventGroupMessage(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
      messageType: Tox_Message_Type.fromValue(unpacker.unpackInt()!),
      message: unpacker.unpackBinary()!,
      messageId: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(5)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packInt(messageType.value)
      ..packBinary(message)
      ..packInt(messageId);
  }
}

@freezed
abstract class ToxEventGroupModeration extends Event
    with _$ToxEventGroupModeration {
  const ToxEventGroupModeration._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupModeration({
    required int groupNumber,
    required int sourcePeerId,
    required int targetPeerId,
    required Tox_Group_Mod_Event modType,
  }) = _ToxEventGroupModeration;

  factory ToxEventGroupModeration.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupModerationFromJson(json);

  factory ToxEventGroupModeration.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 4);
    return ToxEventGroupModeration(
      groupNumber: unpacker.unpackInt()!,
      sourcePeerId: unpacker.unpackInt()!,
      targetPeerId: unpacker.unpackInt()!,
      modType: Tox_Group_Mod_Event.fromValue(unpacker.unpackInt()!),
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(4)
      ..packInt(groupNumber)
      ..packInt(sourcePeerId)
      ..packInt(targetPeerId)
      ..packInt(modType.value);
  }
}

@freezed
abstract class ToxEventGroupPassword extends Event
    with _$ToxEventGroupPassword {
  const ToxEventGroupPassword._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupPassword({
    required int groupNumber,
    required Uint8List password,
  }) = _ToxEventGroupPassword;

  factory ToxEventGroupPassword.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupPasswordFromJson(json);

  factory ToxEventGroupPassword.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventGroupPassword(
      groupNumber: unpacker.unpackInt()!,
      password: unpacker.unpackBinary()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packBinary(password);
  }
}

@freezed
abstract class ToxEventGroupPeerExit extends Event
    with _$ToxEventGroupPeerExit {
  const ToxEventGroupPeerExit._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupPeerExit({
    required int groupNumber,
    required int peerId,
    required Tox_Group_Exit_Type exitType,
    required Uint8List name,
    required Uint8List partMessage,
  }) = _ToxEventGroupPeerExit;

  factory ToxEventGroupPeerExit.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupPeerExitFromJson(json);

  factory ToxEventGroupPeerExit.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 5);
    return ToxEventGroupPeerExit(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
      exitType: Tox_Group_Exit_Type.fromValue(unpacker.unpackInt()!),
      name: unpacker.unpackBinary()!,
      partMessage: unpacker.unpackBinary()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(5)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packInt(exitType.value)
      ..packBinary(name)
      ..packBinary(partMessage);
  }
}

@freezed
abstract class ToxEventGroupPeerJoin extends Event
    with _$ToxEventGroupPeerJoin {
  const ToxEventGroupPeerJoin._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupPeerJoin({
    required int groupNumber,
    required int peerId,
  }) = _ToxEventGroupPeerJoin;

  factory ToxEventGroupPeerJoin.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupPeerJoinFromJson(json);

  factory ToxEventGroupPeerJoin.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventGroupPeerJoin(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(peerId);
  }
}

@freezed
abstract class ToxEventGroupPeerLimit extends Event
    with _$ToxEventGroupPeerLimit {
  const ToxEventGroupPeerLimit._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupPeerLimit({
    required int groupNumber,
    required int peerLimit,
  }) = _ToxEventGroupPeerLimit;

  factory ToxEventGroupPeerLimit.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupPeerLimitFromJson(json);

  factory ToxEventGroupPeerLimit.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventGroupPeerLimit(
      groupNumber: unpacker.unpackInt()!,
      peerLimit: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(peerLimit);
  }
}

@freezed
abstract class ToxEventGroupPeerName extends Event
    with _$ToxEventGroupPeerName {
  const ToxEventGroupPeerName._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupPeerName({
    required int groupNumber,
    required int peerId,
    required Uint8List name,
  }) = _ToxEventGroupPeerName;

  factory ToxEventGroupPeerName.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupPeerNameFromJson(json);

  factory ToxEventGroupPeerName.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventGroupPeerName(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
      name: unpacker.unpackBinary()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packBinary(name);
  }
}

@freezed
abstract class ToxEventGroupPeerStatus extends Event
    with _$ToxEventGroupPeerStatus {
  const ToxEventGroupPeerStatus._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupPeerStatus({
    required int groupNumber,
    required int peerId,
    required Tox_User_Status status,
  }) = _ToxEventGroupPeerStatus;

  factory ToxEventGroupPeerStatus.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupPeerStatusFromJson(json);

  factory ToxEventGroupPeerStatus.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventGroupPeerStatus(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
      status: Tox_User_Status.fromValue(unpacker.unpackInt()!),
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packInt(status.value);
  }
}

@freezed
abstract class ToxEventGroupPrivacyState extends Event
    with _$ToxEventGroupPrivacyState {
  const ToxEventGroupPrivacyState._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupPrivacyState({
    required int groupNumber,
    required Tox_Group_Privacy_State privacyState,
  }) = _ToxEventGroupPrivacyState;

  factory ToxEventGroupPrivacyState.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupPrivacyStateFromJson(json);

  factory ToxEventGroupPrivacyState.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventGroupPrivacyState(
      groupNumber: unpacker.unpackInt()!,
      privacyState: Tox_Group_Privacy_State.fromValue(unpacker.unpackInt()!),
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(privacyState.value);
  }
}

@freezed
abstract class ToxEventGroupPrivateMessage extends Event
    with _$ToxEventGroupPrivateMessage {
  const ToxEventGroupPrivateMessage._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupPrivateMessage({
    required int groupNumber,
    required int peerId,
    required Tox_Message_Type messageType,
    required Uint8List message,
    required int messageId,
  }) = _ToxEventGroupPrivateMessage;

  factory ToxEventGroupPrivateMessage.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupPrivateMessageFromJson(json);

  factory ToxEventGroupPrivateMessage.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 5);
    return ToxEventGroupPrivateMessage(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
      messageType: Tox_Message_Type.fromValue(unpacker.unpackInt()!),
      message: unpacker.unpackBinary()!,
      messageId: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(5)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packInt(messageType.value)
      ..packBinary(message)
      ..packInt(messageId);
  }
}

@freezed
abstract class ToxEventGroupSelfJoin extends Event
    with _$ToxEventGroupSelfJoin {
  const ToxEventGroupSelfJoin._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupSelfJoin({
    required int groupNumber,
  }) = _ToxEventGroupSelfJoin;

  factory ToxEventGroupSelfJoin.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupSelfJoinFromJson(json);

  factory ToxEventGroupSelfJoin.unpack(Unpacker unpacker) {
    return ToxEventGroupSelfJoin(
      groupNumber: unpacker.unpackInt()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer.packInt(groupNumber);
  }
}

@freezed
abstract class ToxEventGroupTopic extends Event with _$ToxEventGroupTopic {
  const ToxEventGroupTopic._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
    converters: [Uint8ListConverter()],
  )
  const factory ToxEventGroupTopic({
    required int groupNumber,
    required int peerId,
    required Uint8List topic,
  }) = _ToxEventGroupTopic;

  factory ToxEventGroupTopic.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupTopicFromJson(json);

  factory ToxEventGroupTopic.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 3);
    return ToxEventGroupTopic(
      groupNumber: unpacker.unpackInt()!,
      peerId: unpacker.unpackInt()!,
      topic: unpacker.unpackBinary()!,
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(3)
      ..packInt(groupNumber)
      ..packInt(peerId)
      ..packBinary(topic);
  }
}

@freezed
abstract class ToxEventGroupTopicLock extends Event
    with _$ToxEventGroupTopicLock {
  const ToxEventGroupTopicLock._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupTopicLock({
    required int groupNumber,
    required Tox_Group_Topic_Lock topicLock,
  }) = _ToxEventGroupTopicLock;

  factory ToxEventGroupTopicLock.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupTopicLockFromJson(json);

  factory ToxEventGroupTopicLock.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventGroupTopicLock(
      groupNumber: unpacker.unpackInt()!,
      topicLock: Tox_Group_Topic_Lock.fromValue(unpacker.unpackInt()!),
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(topicLock.value);
  }
}

@freezed
abstract class ToxEventGroupVoiceState extends Event
    with _$ToxEventGroupVoiceState {
  const ToxEventGroupVoiceState._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventGroupVoiceState({
    required int groupNumber,
    required Tox_Group_Voice_State voiceState,
  }) = _ToxEventGroupVoiceState;

  factory ToxEventGroupVoiceState.fromJson(Map<String, dynamic> json) =>
      _$ToxEventGroupVoiceStateFromJson(json);

  factory ToxEventGroupVoiceState.unpack(Unpacker unpacker) {
    ensure(unpacker.unpackListLength(), 2);
    return ToxEventGroupVoiceState(
      groupNumber: unpacker.unpackInt()!,
      voiceState: Tox_Group_Voice_State.fromValue(unpacker.unpackInt()!),
    );
  }

  @override
  void pack(Packer packer) {
    packer
      ..packListLength(2)
      ..packInt(groupNumber)
      ..packInt(voiceState.value);
  }
}

@freezed
abstract class ToxEventSelfConnectionStatus extends Event
    with _$ToxEventSelfConnectionStatus {
  const ToxEventSelfConnectionStatus._();
  @JsonSerializable(
    explicitToJson: true,
    fieldRename: FieldRename.snake,
  )
  const factory ToxEventSelfConnectionStatus({
    required Tox_Connection connectionStatus,
  }) = _ToxEventSelfConnectionStatus;

  factory ToxEventSelfConnectionStatus.fromJson(Map<String, dynamic> json) =>
      _$ToxEventSelfConnectionStatusFromJson(json);

  factory ToxEventSelfConnectionStatus.unpack(Unpacker unpacker) {
    return ToxEventSelfConnectionStatus(
      connectionStatus: Tox_Connection.fromValue(unpacker.unpackInt()!),
    );
  }

  @override
  void pack(Packer packer) {
    packer.packInt(connectionStatus.value);
  }
}

void ensure<T>(T a, T b) {
  if (a != b) {
    throw Exception('Expected $b but got $a');
  }
}
