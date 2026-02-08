import 'dart:io';
import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/network_error_detector.dart';

void main() {
  group('NetworkErrorDetector - SocketException classification', () {
    test('should detect connection refused', () {
      final error = SocketException(
        'Connection refused',
        osError: const OSError('Connection refused', 10061),
      );
      expect(NetworkErrorDetector.detectType(error),
          equals(NetworkErrorType.connectionRefused));
    });

    test('should detect connection reset', () {
      final error = SocketException(
        'Connection reset by peer',
        osError: const OSError('Connection reset', 10054),
      );
      expect(NetworkErrorDetector.detectType(error),
          equals(NetworkErrorType.connectionReset));
    });

    test('should detect network unreachable', () {
      final error = SocketException(
        'Network is unreachable',
        osError: const OSError('Network is unreachable', 10051),
      );
      expect(NetworkErrorDetector.detectType(error),
          equals(NetworkErrorType.noConnection));
    });

    test('should detect DNS failure', () {
      final error = SocketException(
        'Failed host lookup',
        osError: const OSError('No address', 11001),
      );
      expect(NetworkErrorDetector.detectType(error),
          equals(NetworkErrorType.dnsFailure));
    });

    test('should detect connection timeout', () {
      final error = SocketException(
        'Connection timed out',
        osError: const OSError('Timed out', 10060),
      );
      expect(NetworkErrorDetector.detectType(error),
          equals(NetworkErrorType.connectionTimeout));
    });
  });

  group('NetworkErrorDetector - String-based detection', () {
    test('should detect timeout from string', () {
      expect(
        NetworkErrorDetector.detectType(Exception('connection timeout occurred')),
        equals(NetworkErrorType.connectionTimeout),
      );
    });

    test('should detect response timeout', () {
      expect(
        NetworkErrorDetector.detectType(Exception('response timeout')),
        equals(NetworkErrorType.responseTimeout),
      );
    });

    test('should detect request timeout', () {
      expect(
        NetworkErrorDetector.detectType(Exception('request timeout')),
        equals(NetworkErrorType.requestTimeout),
      );
    });

    test('should detect connection refused from string', () {
      expect(
        NetworkErrorDetector.detectType(Exception('connection refused by server')),
        equals(NetworkErrorType.connectionRefused),
      );
    });

    test('should detect connection reset from string', () {
      expect(
        NetworkErrorDetector.detectType(Exception('connection reset')),
        equals(NetworkErrorType.connectionReset),
      );
    });

    test('should detect broken pipe as connection reset', () {
      expect(
        NetworkErrorDetector.detectType(Exception('broken pipe error')),
        equals(NetworkErrorType.connectionReset),
      );
    });

    test('should detect DNS failure from string', () {
      expect(
        NetworkErrorDetector.detectType(Exception('failed host lookup')),
        equals(NetworkErrorType.dnsFailure),
      );
    });

    test('should detect SSL error from string', () {
      expect(
        NetworkErrorDetector.detectType(Exception('ssl certificate error')),
        equals(NetworkErrorType.sslError),
      );
    });

    test('should detect TLS error from string', () {
      expect(
        NetworkErrorDetector.detectType(Exception('tls handshake failed')),
        equals(NetworkErrorType.sslError),
      );
    });

    test('should detect network unreachable from string', () {
      expect(
        NetworkErrorDetector.detectType(Exception('network is unreachable')),
        equals(NetworkErrorType.serverUnreachable),
      );
    });

    test('should return unknown for unrecognized errors', () {
      expect(
        NetworkErrorDetector.detectType(Exception('something else happened')),
        equals(NetworkErrorType.unknown),
      );
    });
  });

  group('NetworkErrorDetector - HandshakeException', () {
    test('should detect SSL errors from HandshakeException', () {
      // HandshakeException is a subclass of TlsException
      final error = HandshakeException('Certificate not valid');
      expect(NetworkErrorDetector.detectType(error),
          equals(NetworkErrorType.sslError));
    });
  });

  group('NetworkErrorAnalysis', () {
    test('connection refused should be retryable with 30s delay', () {
      final analysis = NetworkErrorAnalysis.fromType(
        NetworkErrorType.connectionRefused,
        'connection refused',
      );
      expect(analysis.isRetryable, isTrue);
      expect(analysis.suggestedRetryDelay, equals(const Duration(seconds: 30)));
      expect(analysis.userFriendlyMessage, isNotEmpty);
    });

    test('SSL error should not be retryable', () {
      final analysis = NetworkErrorAnalysis.fromType(
        NetworkErrorType.sslError,
        'bad cert',
      );
      expect(analysis.isRetryable, isFalse);
      expect(analysis.suggestedRetryDelay, equals(Duration.zero));
    });

    test('all error types should have user-friendly messages', () {
      for (final type in NetworkErrorType.values) {
        final analysis = NetworkErrorAnalysis.fromType(type, 'test');
        expect(analysis.userFriendlyMessage, isNotEmpty,
            reason: 'Missing message for $type');
        expect(analysis.type, equals(type));
      }
    });
  });

  group('NetworkErrorDetector - Utility methods', () {
    test('isNetworkError should return true for socket errors', () {
      expect(
        NetworkErrorDetector.isNetworkError(
          const SocketException('test'),
        ),
        isTrue,
      );
    });

    test('isNetworkError should return true for HTTP errors', () {
      expect(
        NetworkErrorDetector.isNetworkError(
          const HttpException('test'),
        ),
        isTrue,
      );
    });

    test('isNetworkError should return false for generic errors', () {
      expect(
        NetworkErrorDetector.isNetworkError(
          Exception('generic error'),
        ),
        isFalse,
      );
    });

    test('isRetryable should check retryability', () {
      expect(
        NetworkErrorDetector.isRetryable(
          const SocketException('Connection refused'),
        ),
        isTrue,
      );
    });

    test('getSuggestedRetryDelay should return duration', () {
      final delay = NetworkErrorDetector.getSuggestedRetryDelay(
        const SocketException('timeout'),
      );
      expect(delay.inMilliseconds, greaterThan(0));
    });

    test('getUserFriendlyMessage should return non-empty string', () {
      final msg = NetworkErrorDetector.getUserFriendlyMessage(
        const SocketException('error'),
      );
      expect(msg, isNotEmpty);
    });
  });

  group('Convenience functions', () {
    test('isNetworkError function should work', () {
      expect(isNetworkError(const SocketException('test')), isTrue);
    });

    test('isRetryableNetworkError function should work', () {
      expect(
        isRetryableNetworkError(const SocketException('test')),
        isTrue,
      );
    });

    test('analyzeNetworkError function should return analysis', () {
      final analysis = analyzeNetworkError(const SocketException('timeout'));
      expect(analysis, isA<NetworkErrorAnalysis>());
    });
  });
}
