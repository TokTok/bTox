import 'dart:io';

import 'package:btox_call_media/btox_call_media.dart';
import 'package:btox_call_media/src/channel_call_media.dart';
import 'package:btox_call_media/src/native_call_media.dart';

BtoxCallMedia platformCallMedia() =>
    Platform.isAndroid ? ChannelCallMedia() : NativeCallMedia();
