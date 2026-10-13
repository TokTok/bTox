import 'package:btox/models/profile_settings.dart';
import 'package:http/http.dart' as http;

/// Browsers pick their own proxy.
http.Client proxyClient(NetworkSettings network) => http.Client();

Future<bool> canReachProxy(NetworkSettings network) async => true;
