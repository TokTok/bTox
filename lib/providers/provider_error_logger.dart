import 'package:btox/logger.dart';
import 'package:riverpod/riverpod.dart';

const _logger = Logger(['Provider']);

final class ProviderErrorLogger extends ProviderObserver {
  const ProviderErrorLogger();

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) =>
      _logRetry(context, value);

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) => _logRetry(context, newValue);

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) => _logger.e('${context.provider} failed: $error', stackTrace);

  void _logRetry(ProviderObserverContext context, Object? value) {
    if (value case AsyncValue(
      retrying: true,
      :final error?,
      :final stackTrace,
    )) {
      _logger.w('${context.provider} failed, retrying: $error', stackTrace);
    }
  }
}
