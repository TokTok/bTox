import 'package:btox/attachments/attachments.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final attachmentsDirectoryProvider = FutureProvider(
  (ref) => attachmentsDirectory(),
);
