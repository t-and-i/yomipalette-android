import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../providers/tts_provider.dart';

/// Shared transport for cloud TTS APIs.
///
/// A bounded timeout prevents indefinite waiting; only explicit transient HTTP
/// statuses are retried. In particular, a timed-out POST is NOT retried because
/// a service may have processed it and charged for it before the timeout.
class TtsHttpClient {
  TtsHttpClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
    this.maxRetries = 2,
    Future<void> Function(Duration delay)? wait,
  }) : assert(maxRetries >= 0),
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _wait = wait ?? _sleep;

  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  final int maxRetries;
  final Future<void> Function(Duration delay) _wait;

  static Future<void> _sleep(Duration duration) =>
      Future<void>.delayed(duration);

  Future<http.Response> get(Uri uri, {Map<String, String>? headers}) =>
      _send(() => _client.get(uri, headers: headers), canRetryNetwork: true);

  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
  }) => _send(
    () => _client.post(uri, headers: headers, body: body),
    canRetryNetwork: false,
  );

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    required bool canRetryNetwork,
  }) async {
    for (var attempt = 0; ; attempt++) {
      http.Response response;
      try {
        response = await request().timeout(timeout);
      } on TimeoutException {
        // A retry could charge twice if the response was lost after
        // successful generation, so leave the decision with the user.
        throw const TtsProviderException(
          'TTS request timed out. Check connectivity and try again.',
        );
      } on SocketException {
        if (!canRetryNetwork || attempt >= maxRetries) {
          throw const TtsProviderException('TTS network connection failed.');
        }
        await _wait(_backoff(attempt));
        continue;
      } on http.ClientException {
        if (!canRetryNetwork || attempt >= maxRetries) {
          throw const TtsProviderException('TTS network connection failed.');
        }
        await _wait(_backoff(attempt));
        continue;
      }

      if (!_isTransient(response.statusCode) || attempt >= maxRetries) {
        return response;
      }
      await _wait(_retryAfter(response, attempt));
    }
  }

  static bool _isTransient(int status) =>
      status == 429 || status == 502 || status == 503 || status == 504;

  static Duration _backoff(int attempt) =>
      Duration(milliseconds: 250 * (1 << attempt.clamp(0, 4)));

  static Duration _retryAfter(http.Response response, int attempt) {
    final seconds = int.tryParse(response.headers['retry-after'] ?? '');
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds.clamp(0, 3));
    }
    return _backoff(attempt);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
