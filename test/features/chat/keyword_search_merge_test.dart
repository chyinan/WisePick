// pattern: Functional Core
import 'package:test/test.dart';
import 'package:wisepick_dart_version/features/chat/keyword_search_merge.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';

ProductModel _product(String id, String platform) {
  return ProductModel(
    id: id,
    platform: platform,
    title: '$platform-$id',
    price: 100,
    finalPrice: 100,
  );
}

void main() {
  group('mergeKeywordSearchResults', () {
    test('优先保留淘宝和拼多多，京东结果后置', () {
      final results = mergeKeywordSearchResults(
        jdList: [_product('jd-1', 'jd'), _product('jd-2', 'jd')],
        tbList: [_product('tb-1', 'taobao'), _product('tb-2', 'taobao')],
        pddList: [_product('pdd-1', 'pdd')],
      );

      expect(
        results.map((e) => e.id).toList(),
        equals(['tb-1', 'tb-2', 'pdd-1', 'jd-1', 'jd-2']),
      );
    });

    test('按列表先后去重并忽略空 id', () {
      final results = mergeKeywordSearchResults(
        jdList: [_product('dup-1', 'jd'), _product('', 'jd')],
        tbList: [_product('dup-1', 'taobao'), _product('tb-2', 'taobao')],
        pddList: [_product('pdd-1', 'pdd')],
      );

      expect(
        results.map((e) => e.id).toList(),
        equals(['dup-1', 'tb-2', 'pdd-1']),
      );
      expect(results.any((e) => e.id.isEmpty), isFalse);
    });

    test('遵守各平台条数上限且保持相对顺序', () {
      final results = mergeKeywordSearchResults(
        jdList: List.generate(6, (i) => _product('jd-$i', 'jd')),
        tbList: List.generate(6, (i) => _product('tb-$i', 'taobao')),
        pddList: List.generate(5, (i) => _product('pdd-$i', 'pdd')),
      );

      expect(
        results.map((e) => e.id).toList(),
        equals([
          'tb-0',
          'tb-1',
          'tb-2',
          'tb-3',
          'tb-4',
          'pdd-0',
          'pdd-1',
          'pdd-2',
          'pdd-3',
          'jd-0',
          'jd-1',
          'jd-2',
          'jd-3',
          'jd-4',
        ]),
      );
    });
  });
}
