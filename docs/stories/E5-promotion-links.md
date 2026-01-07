# Epic 5: 推广链接生成

**Epic ID**: E5  
**创建日期**: 2026-01-06  
**状态**: Draft  
**优先级**: P1

---

## Epic 描述

实现推广链接生成功能，支持淘宝、京东、拼多多三大平台的转链，提供缓存机制和便捷的复制功能。

## 业务价值

- 帮助推广者高效生成推广链接
- 通过缓存减少 API 调用成本
- 提升用户推广效率和体验

## 依赖关系

- 依赖 Epic 8（后端代理服务）

---

## Story 5.1: 推广链接生成服务

### Status
Draft

### Story
**As a** 推广者,  
**I want** 为商品生成推广链接,  
**so that** 我能获得推广佣金

### Acceptance Criteria

1. 支持淘宝商品转链
2. 支持京东商品转链
3. 支持拼多多商品转链
4. 返回推广链接和短链接
5. 淘宝返回口令（tpwd）
6. 错误情况有友好提示

### Tasks / Subtasks

- [ ] 创建推广链接服务 (AC: 1, 2, 3)
  - [ ] 创建 `lib/services/promotion_service.dart`
  - [ ] 实现 generatePromotionLink()
  - [ ] 根据平台调用不同后端接口
- [ ] 实现淘宝转链 (AC: 1, 5)
  - [ ] 调用 /taobao/convert
  - [ ] 返回 coupon_share_url、tpwd
- [ ] 实现京东转链 (AC: 2, 4)
  - [ ] 调用 /jd/union/promotion/bysubunionid
  - [ ] 返回 clickURL、shortURL
- [ ] 实现拼多多转链 (AC: 3, 4)
  - [ ] 调用 /pdd/rp/prom/generate
  - [ ] 返回 mobile_url、url
- [ ] 错误处理 (AC: 6)
  - [ ] 网络错误提示
  - [ ] API 错误提示
  - [ ] 转链失败提示

### Dev Notes

**服务接口**:
```dart
class PromotionService {
  Future<PromotionLink> generatePromotionLink(ProductModel product, {bool forceRefresh = false});
}

class PromotionLink {
  final String url;
  final String? shortUrl;
  final String? tpwd;  // 淘宝口令
  final DateTime generatedAt;
  final DateTime expiresAt;
}
```

**后端接口**:
| 平台 | 端点 | 返回字段 |
|------|------|----------|
| 淘宝 | POST /taobao/convert | coupon_share_url, tpwd |
| 京东 | POST /jd/union/promotion/bysubunionid | clickURL, shortURL |
| 拼多多 | POST /pdd/rp/prom/generate | mobile_url, url |

### Testing

**测试文件位置**: `test/services/promotion_service_test.dart`

**测试要求**:
- 测试各平台转链
- 测试错误处理
- 测试返回格式

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 5.2: 链接缓存机制

### Status
Draft

### Story
**As a** 开发者,  
**I want** 缓存生成的推广链接,  
**so that** 减少重复 API 调用

### Acceptance Criteria

1. 内存缓存推广链接
2. Hive 持久化缓存
3. 缓存有效期 30 分钟
4. 支持强制刷新
5. 自动清理过期缓存

### Tasks / Subtasks

- [ ] 实现内存缓存 (AC: 1, 3)
  - [ ] 使用 Map 存储
  - [ ] Key: productId + platform
  - [ ] Value: PromotionLink + expiry
- [ ] 实现持久化缓存 (AC: 2)
  - [ ] 使用 Hive Box: 'promo_cache'
  - [ ] 序列化 PromotionLink
- [ ] 实现缓存策略 (AC: 3, 4, 5)
  - [ ] 检查缓存有效期
  - [ ] forceRefresh 参数
  - [ ] 定期清理过期数据

### Dev Notes

**缓存键格式**:
```dart
String cacheKey(ProductModel product) => '${product.platform}_${product.id}';
```

**缓存逻辑**:
```dart
Future<PromotionLink> generatePromotionLink(ProductModel product, {bool forceRefresh = false}) async {
  final key = cacheKey(product);
  
  // 检查缓存
  if (!forceRefresh) {
    final cached = _memoryCache[key] ?? await _loadFromHive(key);
    if (cached != null && !cached.isExpired) {
      return cached;
    }
  }
  
  // 生成新链接
  final link = await _generateFromBackend(product);
  
  // 保存缓存
  _memoryCache[key] = link;
  await _saveToHive(key, link);
  
  return link;
}
```

**有效期配置**:
```dart
const cacheDuration = Duration(minutes: 30);

bool get isExpired => DateTime.now().isAfter(expiresAt);
```

### Testing

**测试文件位置**: `test/services/promotion_cache_test.dart`

**测试要求**:
- 测试缓存命中
- 测试缓存过期
- 测试强制刷新

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 5.3: 链接复制与分享

### Status
Draft

### Story
**As a** 用户,  
**I want** 方便地复制推广链接,  
**so that** 我能快速分享给他人

### Acceptance Criteria

1. 一键复制链接到剪贴板
2. 支持复制淘宝口令
3. 复制成功显示 SnackBar 提示
4. 支持选择复制类型（链接/口令/短链接）

### Tasks / Subtasks

- [ ] 实现链接复制 (AC: 1, 3)
  - [ ] 使用 Clipboard.setData
  - [ ] 显示成功提示
- [ ] 实现口令复制 (AC: 2)
  - [ ] 淘宝口令格式化
  - [ ] 复制完整口令
- [ ] 实现复制选择 (AC: 4)
  - [ ] 显示复制选项弹窗
  - [ ] 链接/短链接/口令

### Dev Notes

**复制实现**:
```dart
Future<void> copyToClipboard(String text, BuildContext context) async {
  await Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('已复制到剪贴板')),
  );
}
```

**淘宝口令格式**:
```dart
String formatTpwd(String tpwd, ProductModel product) {
  return '$tpwd\n【${product.title}】\n【¥${product.price}】';
}
```

**复制选项弹窗**:
```dart
showModalBottomSheet(
  context: context,
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ListTile(
        leading: Icon(Icons.link),
        title: Text('复制推广链接'),
        onTap: () => copyLink(),
      ),
      if (shortUrl != null)
        ListTile(
          leading: Icon(Icons.short_text),
          title: Text('复制短链接'),
          onTap: () => copyShortUrl(),
        ),
      if (tpwd != null)
        ListTile(
          leading: Icon(Icons.password),
          title: Text('复制淘宝口令'),
          onTap: () => copyTpwd(),
        ),
    ],
  ),
)
```

### Testing

**测试文件位置**: `test/services/clipboard_test.dart`

**测试要求**:
- 测试剪贴板操作
- 测试格式化
- 测试 SnackBar 显示

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |



