import 'package:btox/attachments/attachments.dart' as attachments;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'attachments.g.dart';

@Riverpod(keepAlive: true)
Future<String> attachmentsDirectory(Ref ref) =>
    attachments.attachmentsDirectory();
