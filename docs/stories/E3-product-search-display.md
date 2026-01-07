# Epic 3: 商品搜索与展示

**Epic ID**: E3  
**创建日期**: 2026-01-06  
**状态**: Draft  
**优先级**: P0

---

## Epic 描述

实现多平台商品搜索功能，包括统一的商品数据模型、平台适配器、商品卡片组件和详情展示。支持淘宝、京东、拼多多三大电商平台。

## 业务价值

- 让用户在一个界面查看多平台商品
- 统一的商品展示提升比价效率
- 为 AI 推荐和选品车提供商品数据基础

## 依赖关系

- 依赖 Epic 8（后端代理服务）

---

## Story 3.1: 商品数据模型与适配器

### Status
Draft

### Story
**As a** 开发者,  
**I want** 有统一的商品数据模型,  
**so that** 不同平台的商品可以统一处理

### Acceptance Criteria

1. ProductModel 包含所有必要字段
2. 支持 Hive 序列化存储
3. 淘宝适配器能正确转换数据
4. 京东适配器能正确转换数据
5. 拼多多适配器能正确转换数据
6. 适配器接口统一

### Tasks / Subtasks

- [ ] 创建 ProductModel (AC: 1, 2)
  - [ ] 创建 `lib/features/products/product_model.dart`
  - [ ] 定义所有字段
  - [ ] 添加 Hive 注解
  - [ ] 实现 fromJson/toJson
- [ ] 创建淘宝适配器 (AC: 3, 6)
  - [ ] 创建 `lib/features/products/taobao_adapter.dart`
  - [ ] 实现 search 方法
  - [ ] 数据转换为 ProductModel
- [ ] 创建京东适配器 (AC: 4, 6)
  - [ ] 创建 `lib/features/products/jd_adapter.dart`
  - [ ] 实现 search 方法
  - [ ] 处理 OAuth 认证
  - [ ] 数据转换为 ProductModel
- [ ] 创建拼多多适配器 (AC: 5, 6)
  - [ ] 创建 `lib/features/products/pdd_adapter.dart`
  - [ ] 实现 search 方法
  - [ ] 数据转换为 ProductModel

### Dev Notes

**ProductModel 字段**:
```dart
@HiveType(typeId: 0)
class ProductModel {
  @HiveField(0) final String id;
  @HiveField(1) final String platform; // 'taobao' | 'jd' | 'pdd'
  @HiveField(2) final String title;
  @HiveField(3) final double price;
  @HiveField(4) final double? originalPrice;
  @HiveField(5) final double? coupon;
  @HiveField(6) final double? finalPrice;
  @HiveField(7) final String imageUrl;
  @HiveField(8) final int? sales;
  @HiveField(9) final double? rating;
  @HiveField(10) final String? shopTitle;
  @HiveField(11) final String? link;
  @HiveField(12) final double? commission;
  @HiveField(13) final String? description;
}
```

**适配器接口**:
```dart
abstract class ProductAdapter {
  Future<List<ProductModel>> search(String keyword, {int page = 1, int pageSize = 10});
}
```

### Testing

**测试文件位置**: `test/features/products/product_model_test.dart`

**测试要求**:
- 测试序列化/反序列化
- 测试各适配器数据转换
- 测试错误数据处理

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 3.2: 商品卡片组件

### Status
Draft

### Story
**As a** 用户,  
**I want** 清晰地看到商品信息,  
**so that** 我能快速判断是否感兴趣

### Acceptance Criteria

1. 支持紧凑模式（列表视图，高度 120dp）
2. 支持标准模式（网格视图，宽高比 3:4）
3. 支持聊天模式（宽度 160dp）
4. 显示平台徽章（淘宝橙/京东红/拼多多红）
5. 显示价格信息（现价、原价、优惠券）
6. 支持选中、加载、禁用状态
7. 点击有缩放反馈动画

### Tasks / Subtasks

- [ ] 创建 ProductCard 组件 (AC: 1, 2, 3)
  - [ ] 创建 `lib/widgets/product_card.dart`
  - [ ] 实现 ProductCardMode 枚举
  - [ ] 实现紧凑模式布局
  - [ ] 实现标准模式布局
  - [ ] 实现聊天模式布局
- [ ] 创建平台徽章 (AC: 4)
  - [ ] 创建 PlatformBadge Widget
  - [ ] 配置平台颜色
- [ ] 实现价格展示 (AC: 5)
  - [ ] 现价（大字，主题色）
  - [ ] 原价（小字，删除线）
  - [ ] 优惠券（红色徽章）
- [ ] 实现卡片状态 (AC: 6)
  - [ ] 默认状态
  - [ ] 选中状态（勾选框 + 边框）
  - [ ] 加载状态（骨架屏）
  - [ ] 禁用状态（灰度 + 下架标签）
- [ ] 实现点击动画 (AC: 7)
  - [ ] 按压缩放效果 (0.98)

### Dev Notes

**平台颜色**:
| 平台 | 颜色 |
|------|------|
| 淘宝 | #FF5722 |
| 京东 | #E53935 |
| 拼多多 | #FF4E4E |

**组件接口**:
```dart
class ProductCard extends StatelessWidget {
  final ProductModel product;
  final ProductCardMode mode;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
}

enum ProductCardMode { compact, standard, chat }
```

**价格显示**:
```dart
// 现价
Text(
  '¥${product.price.toStringAsFixed(0)}',
  style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Theme.of(context).colorScheme.primary,
  ),
)

// 原价
Text(
  '¥${product.originalPrice}',
  style: TextStyle(
    fontSize: 12,
    decoration: TextDecoration.lineThrough,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  ),
)
```

### Testing

**测试文件位置**: `test/widgets/product_card_test.dart`

**测试要求**:
- 测试三种模式渲染
- 测试状态切换
- 测试点击回调

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 3.3: 商品详情底部弹窗

### Status
Draft

### Story
**As a** 用户,  
**I want** 查看商品的详细信息,  
**so that** 我能做出购买决策

### Acceptance Criteria

1. 最大高度为屏幕的 85%
2. 顶部圆角 28dp，可拖拽关闭
3. 显示商品大图（16:9）
4. 显示完整标题、价格、店铺信息
5. 底部固定操作栏：加入选品车、复制链接、外部打开
6. 支持滚动查看更多内容

### Tasks / Subtasks

- [ ] 创建详情弹窗组件 (AC: 1, 2, 6)
  - [ ] 创建 `lib/widgets/product_detail_sheet.dart`
  - [ ] 使用 DraggableScrollableSheet
  - [ ] 配置 maxChildSize: 0.85
- [ ] 实现内容区域 (AC: 3, 4)
  - [ ] 拖拽指示器
  - [ ] 商品大图（可点击放大）
  - [ ] 标题（最多 3 行）
  - [ ] 标签组（平台、评分、销量）
  - [ ] 价格区域
  - [ ] 店铺信息
- [ ] 实现底部操作栏 (AC: 5)
  - [ ] 加入选品车按钮
  - [ ] 复制推广链接按钮
  - [ ] 外部打开按钮
  - [ ] 使用 SafeArea

### Dev Notes

**弹窗调用**:
```dart
void showProductDetail(BuildContext context, ProductModel product) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ProductDetailSheet(product: product),
  );
}
```

**弹窗结构**:
```dart
DraggableScrollableSheet(
  initialChildSize: 0.7,
  minChildSize: 0.5,
  maxChildSize: 0.85,
  builder: (context, scrollController) => Container(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: Column(
      children: [
        // 拖拽指示器
        Container(width: 32, height: 4, margin: EdgeInsets.symmetric(vertical: 12), ...),
        // 可滚动内容
        Expanded(child: ListView(controller: scrollController, ...)),
        // 底部操作栏
        SafeArea(child: _buildActionBar()),
      ],
    ),
  ),
)
```

### Testing

**测试文件位置**: `test/widgets/product_detail_sheet_test.dart`

**测试要求**:
- 测试弹窗打开/关闭
- 测试操作按钮回调
- 测试滚动行为

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 3.4: 多平台搜索服务

### Status
Draft

### Story
**As a** 用户,  
**I want** 同时搜索多个平台的商品,  
**so that** 我能找到最优选择

### Acceptance Criteria

1. 支持单平台搜索
2. 支持全平台并行搜索
3. 搜索结果自动去重
4. 结果按平台优先级排序（京东 > 淘宝 > 拼多多）
5. 支持分页加载
6. 搜索超时 < 5 秒

### Tasks / Subtasks

- [ ] 创建 ProductService (AC: 1, 2)
  - [ ] 创建 `lib/features/products/product_service.dart`
  - [ ] 实现单平台搜索
  - [ ] 实现并行搜索 (Future.wait)
- [ ] 实现结果处理 (AC: 3, 4)
  - [ ] 去重算法
  - [ ] 排序逻辑
- [ ] 实现分页 (AC: 5)
  - [ ] 支持 page 和 pageSize 参数
  - [ ] 默认每页 10 条
- [ ] 性能优化 (AC: 6)
  - [ ] 设置超时时间
  - [ ] 错误容错处理

### Dev Notes

**SearchService 接口**:
```dart
class ProductService {
  Future<List<ProductModel>> searchProducts(
    String keyword, {
    String? platform, // null 表示全平台
    int page = 1,
    int pageSize = 10,
  });
}
```

**并行搜索**:
```dart
final results = await Future.wait([
  _taobaoAdapter.search(keyword),
  _jdAdapter.search(keyword),
  _pddAdapter.search(keyword),
]);

// 合并结果
final allProducts = results.expand((list) => list).toList();

// 去重（按商品 ID + 平台）
final seen = <String>{};
final deduped = allProducts.where((p) => seen.add('${p.platform}_${p.id}')).toList();

// 排序
deduped.sort((a, b) => _platformPriority(a.platform).compareTo(_platformPriority(b.platform)));
```

### Testing

**测试文件位置**: `test/features/products/product_service_test.dart`

**测试要求**:
- 测试单平台搜索
- 测试并行搜索
- 测试去重和排序
- 测试超时处理

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |



