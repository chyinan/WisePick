import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/services/share_service.dart';

ProductModel _makeProduct({
  String id = 'p1',
  String platform = 'taobao',
  String title = '测试商品',
  String link = '',
}) {
  return ProductModel(
    id: id,
    platform: platform,
    title: title,
    link: link,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('share_service_test_');
    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('promo_cache');
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  // ──────────────────────────────────────────────────────────────
  // truncateTitle
  // ──────────────────────────────────────────────────────────────
  group('ShareService.truncateTitle', () {
    test('短标题原样返回', () {
      expect(ShareService.truncateTitle('短标题'), equals('短标题'));
    });

    test('恰好 40 字不截断', () {
      final title = 'a' * 40;
      expect(ShareService.truncateTitle(title), equals(title));
    });

    test('超过 40 字截断并加省略号', () {
      final title = 'a' * 50;
      final result = ShareService.truncateTitle(title);
      expect(result.length, equals(40));
      expect(result.endsWith('...'), isTrue);
    });

    test('截断后前缀内容正确', () {
      final title = 'x' * 50;
      final result = ShareService.truncateTitle(title);
      expect(result, equals('${'x' * 37}...'));
    });

    test('空字符串原样返回', () {
      expect(ShareService.truncateTitle(''), equals(''));
    });
  });

  // ──────────────────────────────────────────────────────────────
  // getPromotionLink
  // ──────────────────────────────────────────────────────────────
  group('ShareService.getPromotionLink', () {
    test('商品自带 link 时直接返回', () async {
      final product = _makeProduct(link: 'https://example.com/item');
      final result = await ShareService.getPromotionLink(product);
      expect(result, equals('https://example.com/item'));
    });

    test('京东商品无 link 时返回 jd 商品页 URL', () async {
      final product = _makeProduct(id: '12345', platform: 'jd', link: '');
      final result = await ShareService.getPromotionLink(product);
      expect(result, equals('https://item.jd.com/12345.html'));
    });

    test('淘宝商品无 link 时返回淘宝商品页 URL', () async {
      final product = _makeProduct(id: '99999', platform: 'taobao', link: '');
      final result = await ShareService.getPromotionLink(product);
      // ProductService 调用会失败（无 API key），回退到默认链接
      expect(result, equals('https://item.taobao.com/item.htm?id=99999'));
    });

    test('拼多多商品无 link 时返回 pdd 商品页 URL', () async {
      final product = _makeProduct(id: '88888', platform: 'pdd', link: '');
      final result = await ShareService.getPromotionLink(product);
      expect(result, equals('https://mobile.yangkeduo.com/goods.html?goods_id=88888'));
    });

    test('未知平台无 link 时返回 null', () async {
      final product = _makeProduct(id: '1', platform: 'unknown', link: '');
      final result = await ShareService.getPromotionLink(product);
      expect(result, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────
  // generateShareText
  // ──────────────────────────────────────────────────────────────
  group('ShareService.generateShareText', () {
    test('有链接时包含标题和链接', () async {
      final product = _makeProduct(
        title: '蓝牙耳机',
        link: 'https://example.com/item',
      );
      final text = await ShareService.generateShareText(product);
      expect(text, contains('蓝牙耳机'));
      expect(text, contains('https://example.com/item'));
      expect(text, contains('我在快淘帮发现了好物'));
    });

    test('链接以 // 开头时自动补全 https:', () async {
      final product = _makeProduct(
        title: '商品',
        link: '//item.taobao.com/item.htm?id=1',
      );
      final text = await ShareService.generateShareText(product);
      expect(text, contains('https://item.taobao.com/item.htm?id=1'));
    });

    test('无链接时只包含标题', () async {
      final product = _makeProduct(
        id: '1',
        platform: 'unknown',
        title: '无链接商品',
        link: '',
      );
      final text = await ShareService.generateShareText(product);
      expect(text, contains('无链接商品'));
      expect(text, contains('我在快淘帮发现了好物'));
    });

    test('超长标题被截断', () async {
      final longTitle = '超长商品标题' * 10;
      final product = _makeProduct(
        title: longTitle,
        link: 'https://example.com',
      );
      final text = await ShareService.generateShareText(product);
      // 截断后的标题不超过 40 字
      final titleInText = RegExp(r'【(.+?)】').firstMatch(text)?.group(1) ?? '';
      expect(titleInText.length, lessThanOrEqualTo(40));
    });
  });
}
