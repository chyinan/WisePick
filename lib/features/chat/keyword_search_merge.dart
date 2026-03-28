// pattern: Functional Core
import '../products/product_model.dart';

List<ProductModel> mergeKeywordSearchResults({
  required List<ProductModel> jdList,
  required List<ProductModel> tbList,
  required List<ProductModel> pddList,
}) {
  final merged = <ProductModel>[];
  final seenIds = <String>{};

  void appendProducts(List<ProductModel> products, int limit) {
    var added = 0;
    for (final product in products) {
      if (added >= limit) break;
      if (product.id.isEmpty || seenIds.contains(product.id)) continue;
      merged.add(product);
      seenIds.add(product.id);
      added += 1;
    }
  }

  appendProducts(tbList, 5);
  appendProducts(pddList, 4);
  appendProducts(jdList, 5);

  return merged;
}
