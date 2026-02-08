/// Cloud-Native Self-Healing Reliability Platform
///
/// A comprehensive reliability platform that provides:
/// - Predictive load management with time-series forecasting
/// - Automated root cause analysis with multi-dimensional fault diagnosis
/// - Pluggable resilience strategies with dynamic switching
/// - Built-in chaos engineering tools for fault injection and experimentation
/// - Real-time reliability dashboards with health scoring
///
/// ## Quick Start
///
/// ```dart
/// // 1. Initialize the platform
/// await initializeReliabilityPlatform(
///   config: ReliabilityPlatformConfig.production,
/// );
///
/// // 2. Register your services
/// registerReliableService(ServiceRegistration(
///   name: 'my_service',
///   sloTargets: [
///     SloTarget.availability(target: 0.999),
///     SloTarget.latency(targetMs: 500),
///   ],
///   dependencies: ['database', 'cache'],
///   criticalService: true,
/// ));
///
/// // 3. Execute operations with full resilience protection
/// final result = await executeReliably<Data>(
///   'my_service',
///   'fetch_data',
///   () => myService.fetchData(),
/// );
///
/// if (result.isSuccess) {
///   print('Data: ${result.value}');
/// } else {
///   print('Error: ${result.error}');
/// }
/// ```
///
/// ## Features
///
/// ### Predictive Load Management
/// Uses time-series analysis (EWMA, linear regression, Holt-Winters) to predict
/// future load and proactively trigger protective measures like throttling,
/// pre-warming, or emergency brakes.
///
/// ### Root Cause Analysis
/// Automatically correlates failure events, identifies patterns (cascading failure,
/// resource exhaustion, network partition, etc.), and generates hypotheses with
/// supporting evidence and suggested actions.
///
/// ### Pluggable Resilience Strategies
/// Chain multiple strategies (timeout, bulkhead, circuit breaker, rate limiting,
/// retry, fallback, caching) in priority order with dynamic configuration.
///
/// ### Chaos Engineering
/// Built-in fault injection capabilities for testing system resilience:
/// - Latency injection
/// - Error injection
/// - Network partition simulation
/// - Resource exhaustion simulation
///
/// ### Reliability Dashboard
/// Real-time visibility into:
/// - System health score (0-100)
/// - Service status summaries
/// - SLO/error budget tracking
/// - Active alerts and incidents
/// - Predictive insights
// Core platform
export 'reliability_platform.dart';

// Predictive load management
export 'predictive_load_manager.dart';

// Root cause analysis
export 'root_cause_analyzer.dart';

// Pluggable resilience strategies
export 'resilience_strategy.dart';

// Chaos engineering
export 'chaos_engineering.dart';

// Dashboard
export 'reliability_dashboard.dart';
