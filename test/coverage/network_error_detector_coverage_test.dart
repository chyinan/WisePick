import 'dart:io';

import 'package:test/test.dart';
import 'package:wisepick_dart_version/core/resilience/network_error_detector.dart';

void main() {
  group('NetworkErrorType', () {
    test('all values exist', () {
      expect(NetworkErrorType.values, hasLength(10));
    });
  });

  group('NetworkErrorAnalysis.fromType', () {
    test('noConnection', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.noConnection, 'msg');
      expect(a.type, NetworkErrorType.noConnection);
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 5));
      expect(a.userFriendlyMessage, contains('无网络'));
    });

    test('dnsFailure', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.dnsFailure, 'msg');
      expect(a.type, NetworkErrorType.dnsFailure);
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 10));
    });

    test('connectionTimeout', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.connectionTimeout, 'msg');
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 3));
    });

    test('connectionRefused', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.connectionRefused, 'msg');
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 30));
    });

    test('connectionReset', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.connectionReset, 'msg');
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 2));
    });

    test('sslError', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.sslError, 'msg');
      expect(a.isRetryable, isFalse);
      expect(a.suggestedRetryDelay, Duration.zero);
    });

    test('serverUnreachable', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.serverUnreachable, 'msg');
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 15));
    });

    test('requestTimeout', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.requestTimeout, 'msg');
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 5));
    });

    test('responseTimeout', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.responseTimeout, 'msg');
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 10));
    });

    test('unknown', () {
      final a = NetworkErrorAnalysis.fromType(NetworkErrorType.unknown, 'msg');
      expect(a.isRetryable, isTrue);
      expect(a.suggestedRetryDelay, const Duration(seconds: 5));
    });
  });

  group('NetworkErrorDetector - SocketException', () {
    test('connection refused by message', () {
      final e = SocketException('Connection refused');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionRefused);
    });

    test('connection refused by OS error code 111', () {
      final e = SocketException('err', osError: OSError('err', 111));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionRefused);
    });

    test('connection refused by OS error code 10061', () {
      final e = SocketException('err', osError: OSError('err', 10061));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionRefused);
    });

    test('connection reset by message', () {
      final e = SocketException('Connection reset by peer');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionReset);
    });

    test('connection reset by OS error code 104', () {
      final e = SocketException('err', osError: OSError('err', 104));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionReset);
    });

    test('connection reset by OS error code 10054', () {
      final e = SocketException('err', osError: OSError('err', 10054));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionReset);
    });

    test('network unreachable by message', () {
      final e = SocketException('Network is unreachable');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.noConnection);
    });

    test('network unreachable by OS error code 101', () {
      final e = SocketException('err', osError: OSError('err', 101));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.noConnection);
    });

    test('network unreachable by OS error code 10051', () {
      final e = SocketException('err', osError: OSError('err', 10051));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.noConnection);
    });

    test('host not found by message', () {
      final e = SocketException('Failed host lookup');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.dnsFailure);
    });

    test('DNS failure by OS error code -2', () {
      final e = SocketException('err', osError: OSError('err', -2));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.dnsFailure);
    });

    test('DNS failure by OS error code 11001', () {
      final e = SocketException('err', osError: OSError('err', 11001));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.dnsFailure);
    });

    test('DNS failure by osError message', () {
      final e = SocketException('err', osError: OSError('No address associated', 0));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.dnsFailure);
    });

    test('timed out by message', () {
      final e = SocketException('Connection timed out');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionTimeout);
    });

    test('timed out by OS error code 110', () {
      final e = SocketException('err', osError: OSError('err', 110));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionTimeout);
    });

    test('timed out by OS error code 10060', () {
      final e = SocketException('err', osError: OSError('err', 10060));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionTimeout);
    });

    test('unknown socket exception', () {
      final e = SocketException('some other error');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.unknown);
    });

    test('connection refused by osError message', () {
      final e = SocketException('err', osError: OSError('Connection refused', 0));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionRefused);
    });

    test('connection reset by osError message', () {
      final e = SocketException('err', osError: OSError('Connection reset', 0));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionReset);
    });

    test('network unreachable by osError message', () {
      final e = SocketException('err', osError: OSError('Network is unreachable', 0));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.noConnection);
    });

    test('timed out by osError message', () {
      final e = SocketException('err', osError: OSError('Timed out', 0));
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionTimeout);
    });
  });

  group('NetworkErrorDetector - HttpException', () {
    test('connection closed', () {
      final e = HttpException('Connection closed before full response');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.connectionReset);
    });

    test('timed out', () {
      final e = HttpException('Request timed out');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.requestTimeout);
    });

    test('unknown http exception', () {
      final e = HttpException('some other http error');
      expect(NetworkErrorDetector.detectType(e), NetworkErrorType.unknown);
    });
  });

  group('NetworkErrorDetector - HandshakeException', () {
    test('HandshakeException detected as sslError', () {
      // HandshakeException is not directly constructible, test via string matching
      final type = NetworkErrorDetector.detectType(
        const TlsException('Handshake error'));
      // TlsException is the parent of HandshakeException
      // It won't be a HandshakeException, so it goes to string analysis
      expect(type, NetworkErrorType.sslError); // 'handshake' in string
    });
  });

  group('NetworkErrorDetector - error string analysis', () {
    test('connection timeout', () {
      final type = NetworkErrorDetector.detectType('Connection timeout occurred');
      expect(type, NetworkErrorType.connectionTimeout);
    });

    test('response timeout', () {
      final type = NetworkErrorDetector.detectType('Response timed out');
      expect(type, NetworkErrorType.responseTimeout);
    });

    test('receive timeout', () {
      final type = NetworkErrorDetector.detectType('Receive timeout');
      expect(type, NetworkErrorType.responseTimeout);
    });

    test('request timeout', () {
      final type = NetworkErrorDetector.detectType('Request timed out');
      expect(type, NetworkErrorType.requestTimeout);
    });

    test('send timeout', () {
      final type = NetworkErrorDetector.detectType('Send timeout');
      expect(type, NetworkErrorType.requestTimeout);
    });

    test('generic timeout', () {
      final type = NetworkErrorDetector.detectType('Timeout exceeded');
      expect(type, NetworkErrorType.connectionTimeout);
    });

    test('connection refused string', () {
      final type = NetworkErrorDetector.detectType('Connection refused by server');
      expect(type, NetworkErrorType.connectionRefused);
    });

    test('connection reset string', () {
      final type = NetworkErrorDetector.detectType('Connection reset by peer');
      expect(type, NetworkErrorType.connectionReset);
    });

    test('broken pipe', () {
      final type = NetworkErrorDetector.detectType('Broken pipe');
      expect(type, NetworkErrorType.connectionReset);
    });

    test('connection failed', () {
      final type = NetworkErrorDetector.detectType('Connection failed');
      expect(type, NetworkErrorType.noConnection);
    });

    test('connection error', () {
      final type = NetworkErrorDetector.detectType('Connection error occurred');
      expect(type, NetworkErrorType.noConnection);
    });

    test('host not found string', () {
      final type = NetworkErrorDetector.detectType('Host not found');
      expect(type, NetworkErrorType.dnsFailure);
    });

    test('dns string', () {
      final type = NetworkErrorDetector.detectType('DNS resolution failed');
      expect(type, NetworkErrorType.dnsFailure);
    });

    test('failed host lookup string', () {
      final type = NetworkErrorDetector.detectType('Failed host lookup');
      expect(type, NetworkErrorType.dnsFailure);
    });

    test('no address associated', () {
      final type = NetworkErrorDetector.detectType('No address associated with hostname');
      expect(type, NetworkErrorType.dnsFailure);
    });

    test('ssl string', () {
      final type = NetworkErrorDetector.detectType('SSL error occurred');
      expect(type, NetworkErrorType.sslError);
    });

    test('tls string', () {
      final type = NetworkErrorDetector.detectType('TLS handshake failed');
      expect(type, NetworkErrorType.sslError);
    });

    test('certificate string', () {
      final type = NetworkErrorDetector.detectType('Certificate verification failed');
      expect(type, NetworkErrorType.sslError);
    });

    test('handshake string', () {
      final type = NetworkErrorDetector.detectType('Handshake error');
      expect(type, NetworkErrorType.sslError);
    });

    test('network unreachable string', () {
      final type = NetworkErrorDetector.detectType('Network is unreachable');
      expect(type, NetworkErrorType.serverUnreachable);
    });

    test('no route to host', () {
      final type = NetworkErrorDetector.detectType('No route to host');
      expect(type, NetworkErrorType.serverUnreachable);
    });

    test('network unreachable without "is"', () {
      final type = NetworkErrorDetector.detectType('Network unreachable');
      expect(type, NetworkErrorType.serverUnreachable);
    });

    test('socketexception string', () {
      final type = NetworkErrorDetector.detectType('SocketException: something');
      expect(type, NetworkErrorType.noConnection);
    });

    test('socket string', () {
      final type = NetworkErrorDetector.detectType('Socket operation failed');
      expect(type, NetworkErrorType.noConnection);
    });

    test('unknown string', () {
      final type = NetworkErrorDetector.detectType('Something completely different');
      expect(type, NetworkErrorType.unknown);
    });
  });

  group('NetworkErrorDetector - analyze', () {
    test('analyze SocketException', () {
      final analysis = NetworkErrorDetector.analyze(
        SocketException('Connection refused'),
      );
      expect(analysis.type, NetworkErrorType.connectionRefused);
      expect(analysis.isRetryable, isTrue);
      expect(analysis.message, contains('Connection refused'));
    });

    test('analyze string error', () {
      final analysis = NetworkErrorDetector.analyze('Timeout occurred');
      expect(analysis.type, NetworkErrorType.connectionTimeout);
    });
  });

  group('NetworkErrorDetector - isNetworkError', () {
    test('SocketException is network error', () {
      expect(NetworkErrorDetector.isNetworkError(SocketException('err')), isTrue);
    });

    test('HttpException is network error', () {
      expect(NetworkErrorDetector.isNetworkError(HttpException('err')), isTrue);
    });

    test('string with network keyword', () {
      expect(NetworkErrorDetector.isNetworkError('Connection refused'), isTrue);
    });

    test('unknown string is not network error', () {
      expect(NetworkErrorDetector.isNetworkError('Random error'), isFalse);
    });
  });

  group('NetworkErrorDetector - isRetryable', () {
    test('connection refused is retryable', () {
      expect(NetworkErrorDetector.isRetryable(SocketException('Connection refused')), isTrue);
    });

    test('ssl error is not retryable', () {
      expect(NetworkErrorDetector.isRetryable('SSL error'), isFalse);
    });
  });

  group('NetworkErrorDetector - getSuggestedRetryDelay', () {
    test('returns correct delay for timeout', () {
      final delay = NetworkErrorDetector.getSuggestedRetryDelay('Connection timeout');
      expect(delay, const Duration(seconds: 3));
    });
  });

  group('NetworkErrorDetector - getUserFriendlyMessage', () {
    test('returns friendly message', () {
      final msg = NetworkErrorDetector.getUserFriendlyMessage(
        SocketException('Connection refused'),
      );
      expect(msg, contains('服务'));
    });
  });

  group('Convenience functions', () {
    test('isNetworkError', () {
      expect(isNetworkError(SocketException('err')), isTrue);
    });

    test('isRetryableNetworkError', () {
      expect(isRetryableNetworkError(SocketException('Connection refused')), isTrue);
    });

    test('analyzeNetworkError', () {
      final a = analyzeNetworkError(SocketException('Connection refused'));
      expect(a.type, NetworkErrorType.connectionRefused);
    });
  });
}
