import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/hive_config.dart';

// This provider will manage the state of JD prices,
// caching them in memory and persisting them to Hive.
final jdPriceCacheProvider = StateNotifierProvider<JdPriceCacheNotifier, Map<String, double>>((ref) {
  return JdPriceCacheNotifier();
});

class JdPriceCacheNotifier extends StateNotifier<Map<String, double>> {
  JdPriceCacheNotifier() : super({}) {
    _loadInitialPrices();
  }

  static const _boxName = 'jdPriceCache';

  // Load prices from Hive on startup.
  //
  // Uses per-entry conversion instead of a blanket .cast<String, double>()
  // to avoid a runtime CastError if any key/value is corrupted, and wraps
  // the whole operation in a try/catch so a corrupt box doesn't crash the
  // provider on startup.
  Future<void> _loadInitialPrices() async {
    try {
      final box = await HiveConfig.getTypedBox<double>(HiveConfig.jdPriceCacheBox);
      final map = <String, double>{};
      for (final entry in box.toMap().entries) {
        final value = entry.value;
        if (value is double) {
          map[entry.key.toString()] = value;
        }
      }
      state = map;
    } catch (e) {
      dev.log('Failed to load JD price cache: $e', name: 'JdPriceCacheNotifier');
      // State stays as empty map — prices will be re-fetched on next refresh.
    }
  }

  // Get a price for a specific SKU
  double? getPrice(String sku) {
    return state[sku];
  }

  // Update a price in both state and Hive
  Future<void> updatePrice(String sku, double price) async {
    final box = await HiveConfig.getTypedBox<double>(HiveConfig.jdPriceCacheBox);
    await box.put(sku, price);
    state = {...state, sku: price};
  }
}
