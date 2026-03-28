Map<String, dynamic> _toProductMap(Map source) {
  return Map<String, dynamic>.from(source.map((key, value) => MapEntry(key.toString(), value)));
}

String _normalizeTitle(String? title) {
  if (title == null) return '';
  return title
      .replaceAll(RegExp(r'[^0-9a-zA-Z\u4e00-\u9fa5]+'), '')
      .toLowerCase();
}

double _extractComparablePrice(Map<String, dynamic> product) {
  final num? finalPrice = product['final_price'] is num
      ? product['final_price'] as num
      : num.tryParse((product['final_price'] ?? '').toString());
  if (finalPrice != null && finalPrice > 0) return finalPrice.toDouble();

  final num? price = product['price'] is num
      ? product['price'] as num
      : num.tryParse((product['price'] ?? '').toString());
  return (price ?? 0).toDouble();
}

double productScore(Map<String, dynamic> product) {
  var score = 0.0;
  if ((product['link'] as String?)?.isNotEmpty ?? false) score += 100000.0;
  score += ((product['commission'] as num?)?.toDouble() ?? 0.0) * 100.0;
  score += ((product['sales'] as num?)?.toDouble() ?? 0.0) / 1000.0;
  score -= _extractComparablePrice(product) / 10000.0;
  return score;
}

List<Map<String, dynamic>> moveJdProductsToEnd(List<Map<String, dynamic>> products) {
  final nonJd = <Map<String, dynamic>>[];
  final jd = <Map<String, dynamic>>[];

  for (final item in products) {
    final platform = (item['platform'] ?? '').toString().toLowerCase();
    if (platform == 'jd') {
      jd.add(item);
    } else {
      nonJd.add(item);
    }
  }

  return <Map<String, dynamic>>[...nonJd, ...jd];
}

List<Map<String, dynamic>> deduplicateWithinPlatformByTitleAndPrice(
  List<Map<String, dynamic>> products,
) {
  final groups = <String, List<Map<String, dynamic>>>{};

  for (final item in products) {
    final product = _toProductMap(item);
    final platform = (product['platform'] ?? '').toString().toLowerCase();
    final normalizedTitle = _normalizeTitle((product['title'] ?? '').toString());
    final price = _extractComparablePrice(product).toStringAsFixed(2);

    final String key;
    if (normalizedTitle.isEmpty) {
      key = 'id:${platform}:${product['id'] ?? ''}';
    } else {
      key = 'p:${platform}|t:${normalizedTitle}|pr:${price}';
    }

    groups.putIfAbsent(key, () => []).add(product);
  }

  final merged = <Map<String, dynamic>>[];
  for (final group in groups.values) {
    if (group.length == 1) {
      merged.add(group.first);
      continue;
    }
    group.sort((a, b) => productScore(b).compareTo(productScore(a)));
    merged.add(group.first);
  }

  return merged;
}
