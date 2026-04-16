// pattern: Imperative Shell

import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:test/test.dart';
import 'package:wisepick_proxy_server/reliability/reliability_api.dart';

void main() {
  group('ReliabilityDataCollector self-tests', () {
    late HttpServer server;
    late ReliabilityDataCollector collector;

    setUp(() async {
      collector = ReliabilityDataCollector.instance;
      collector.setChaosEnabled(false);
      collector.stopChaosExperiment();

      final router = Router()
        ..get(kReliabilityProbePath, (Request request) {
          return Response.ok(
            jsonEncode({'ok': true}),
            headers: {'content-type': 'application/json'},
          );
        });

      final handler = const Pipeline()
          .addMiddleware(observabilityMiddleware())
          .addHandler(router.call);

      server = await shelf_io.serve(handler, InternetAddress.loopbackIPv4, 0);

      final registeredExperiments = collector.getChaosStatus().registeredExperiments;
      final registeredIds =
          registeredExperiments.map((experiment) => experiment['id']).toSet();

      if (!registeredIds.contains('test_latency_probe')) {
        collector.registerChaosExperiment({
          'id': 'test_latency_probe',
          'name': 'Latency Probe Test',
          'faults': [
            {'type': 'latency', 'probability': 1.0, 'durationMs': 5},
          ],
        });
      }
      if (!registeredIds.contains('test_error_probe')) {
        collector.registerChaosExperiment({
          'id': 'test_error_probe',
          'name': 'Error Probe Test',
          'faults': [
            {'type': 'error', 'probability': 1.0},
          ],
        });
      }
    });

    tearDown(() async {
      collector.setChaosEnabled(false);
      collector.stopChaosExperiment();
      await server.close(force: true);
    });

    test('probe endpoint is reachable from a local HttpClient', () async {
      final client = HttpClient();
      client.findProxy = (_) => 'DIRECT';
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${server.port}$kReliabilityProbePath'),
      );
      final response = await request.close();
      final body = await utf8.decodeStream(response);
      client.close();

      expect(response.statusCode, 200, reason: body);
    });

    test('stress test records successful probe traffic', () async {
      final results = await collector.runStressTest(
        targetUri: Uri.parse('http://127.0.0.1:${server.port}$kReliabilityProbePath'),
      );
      final loadSteps = (results['loadSteps'] as List).cast<Map<String, dynamic>>();

      expect(loadSteps, isNotEmpty);
      expect(
        loadSteps.every((step) => (step['successCount'] as int? ?? 0) > 0),
        isTrue,
      );
    });

    test('chaos test persists experiment results for follow-up reads', () async {
      await collector.runChaosTest(
        targetUri: Uri.parse('http://127.0.0.1:${server.port}$kReliabilityProbePath'),
      );

      final results = collector.getStressTestResults();
      final chaosExperiments =
          (results['chaosExperiments'] as List).cast<Map<String, dynamic>>();

      expect(chaosExperiments, isNotEmpty);
      expect(
        chaosExperiments.any(
          (experiment) => ((experiment['observations'] as List?) ?? const [])
              .isNotEmpty,
        ),
        isTrue,
      );
    }, timeout: const Timeout(Duration(minutes: 1)));
  });
}
