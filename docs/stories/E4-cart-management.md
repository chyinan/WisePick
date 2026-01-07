# Epic 4: 选品车管理

**Epic ID**: E4  
**创建日期**: 2026-01-06  
**状态**: Draft  
**优先级**: P0

---

## Epic 描述

实现选品车功能，让用户能够收藏商品、管理数量、监控价格变化，并批量生成推广链接进行结算。

## 业务价值

- 帮助用户管理感兴趣的商品
- 价格监控提高用户粘性
- 批量操作提升推广效率

## 依赖关系

- 依赖 Epic 1（应用基础架构）
- 依赖 Epic 3（商品搜索与展示）
- 依赖 Epic 5（推广链接生成）

---

## Story 4.1: 选品车页面布局

### Status
Draft

### Story
**As a** 用户,  
**I want** 有一个清晰的选品车界面,  
**so that** 我能方便地管理收藏的商品

### Acceptance Criteria

1. 顶部显示"选品车"标题和商品数量
2. 商品按店铺分组显示
3. 底部固定结算栏
4. 空状态显示引导界面
5. 支持下拉刷新价格

### Tasks / Subtasks

- [ ] 创建选品车页面 (AC: 1, 2, 3)
  - [ ] 创建 `lib/screens/cart_page.dart`
  - [ ] 顶部操作栏（数量、全选、删除）
  - [ ] 商品列表区域
  - [ ] 底部结算栏
- [ ] 实现店铺分组 (AC: 2)
  - [ ] 按 shopTitle 分组
  - [ ] 可展开/收起
- [ ] 实现空状态 (AC: 4)
  - [ ] 空购物车图标
  - [ ] 引导文案
  - [ ] "开始聊天"按钮
- [ ] 实现下拉刷新 (AC: 5)
  - [ ] RefreshIndicator
  - [ ] 调用价格刷新服务

### Dev Notes

**页面布局**:
```
┌─────────────────────────────────────┐
│  选品车 (3件)     [全选] [删除]      │
├─────────────────────────────────────┤
│  ── 京东自营旗舰店 ──────────────    │
│  ┌───────────────────────────────┐  │
│  │ [☑] [图] 商品标题...          │  │
│  │       ¥799  [-] 1 [+] [删除]  │  │
│  └───────────────────────────────┘  │
│  ── 淘宝店铺 ────────────────────    │
│  ┌───────────────────────────────┐  │
│  │ [☐] [图] 商品标题...          │  │
│  └───────────────────────────────┘  │
├─────────────────────────────────────┤
│  已选 1 件  合计: ¥799    [结算]    │
└─────────────────────────────────────┘
```

**店铺分组数据结构**:
```dart
class ShopGroup {
  final String shopName;
  final String platform;
  final List<CartItem> items;
  bool isExpanded;
}
```

### Testing

**测试文件位置**: `test/screens/cart_page_test.dart`

**测试要求**:
- 测试空状态渲染
- 测试店铺分组显示
- 测试下拉刷新

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 4.2: 选品车数据服务

### Status
Draft

### Story
**As a** 用户,  
**I want** 选品车数据能够持久化保存,  
**so that** 下次打开应用时还能看到

### Acceptance Criteria

1. 支持添加商品到选品车
2. 支持从选品车删除商品
3. 自动去重（相同商品合并数量）
4. 数据持久化到 Hive
5. 记录添加时的价格
6. 支持清空选品车

### Tasks / Subtasks

- [ ] 创建 CartService (AC: 1, 2, 3, 6)
  - [ ] 创建 `lib/features/cart/cart_service.dart`
  - [ ] 实现 addOrUpdateItem()
  - [ ] 实现 removeItem()
  - [ ] 实现 clear()
- [ ] 实现数据持久化 (AC: 4, 5)
  - [ ] 使用 Hive Box: 'cart_box'
  - [ ] 存储 CartItem 数据
  - [ ] 记录 initial_price
- [ ] 创建状态管理 (AC: 1, 2)
  - [ ] 创建 `lib/features/cart/cart_providers.dart`
  - [ ] cartItemsProvider
  - [ ] selectedItemsProvider
  - [ ] totalPriceProvider

### Dev Notes

**CartItem 模型**:
```dart
class CartItem {
  final ProductModel product;
  int quantity;
  bool isSelected;
  double? initialPrice;  // 加入时的价格
  double? currentPrice;  // 当前价格
  
  double get priceChange => (currentPrice ?? product.price) - (initialPrice ?? product.price);
  bool get hasPriceChanged => priceChange.abs() > 0.01;
  bool get isPriceDropped => priceChange < 0;
}
```

**CartService 方法**:
```dart
class CartService {
  Future<void> addOrUpdateItem(ProductModel product, {int quantity = 1});
  Future<void> removeItem(String productId);
  Future<void> setQuantity(String productId, int quantity);
  List<CartItem> getAllItems();
  Future<void> clear();
}
```

### Testing

**测试文件位置**: `test/features/cart/cart_service_test.dart`

**测试要求**:
- 测试添加/删除商品
- 测试数量合并
- 测试持久化

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 4.3: 商品数量与批量操作

### Status
Draft

### Story
**As a** 用户,  
**I want** 调整商品数量和批量管理,  
**so that** 我能高效管理选品车

### Acceptance Criteria

1. 数量调节器：-/+按钮
2. 数量为 1 时减号按钮禁用
3. 支持单选/取消选择
4. 支持全选/取消全选
5. 批量删除需要确认弹窗
6. 移动端支持左滑删除

### Tasks / Subtasks

- [ ] 创建数量调节器 (AC: 1, 2)
  - [ ] 减号按钮
  - [ ] 数量显示
  - [ ] 加号按钮
  - [ ] 数量为 1 时禁用减号
- [ ] 实现选择功能 (AC: 3, 4)
  - [ ] 单项选择框
  - [ ] 全选按钮
  - [ ] 更新 selectedItemsProvider
- [ ] 实现批量删除 (AC: 5)
  - [ ] 删除按钮
  - [ ] 确认对话框
  - [ ] 执行删除
- [ ] 实现左滑删除 (AC: 6)
  - [ ] 使用 Dismissible
  - [ ] 显示删除背景

### Dev Notes

**数量调节器**:
```dart
Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    IconButton(
      icon: Icon(Icons.remove),
      onPressed: quantity > 1 ? () => onQuantityChanged(quantity - 1) : null,
    ),
    SizedBox(
      width: 40,
      child: Text('$quantity', textAlign: TextAlign.center),
    ),
    IconButton(
      icon: Icon(Icons.add),
      onPressed: () => onQuantityChanged(quantity + 1),
    ),
  ],
)
```

**确认对话框**:
```dart
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('确认删除'),
    content: Text('确定要删除选中的 $count 件商品吗？'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
      FilledButton(onPressed: () { /* 执行删除 */ }, child: Text('确认')),
    ],
  ),
)
```

### Testing

**测试文件位置**: `test/features/cart/cart_operations_test.dart`

**测试要求**:
- 测试数量调节
- 测试选择功能
- 测试批量删除

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 4.4: 价格监控与通知

### Status
Draft

### Story
**As a** 用户,  
**I want** 在商品降价时收到通知,  
**so that** 我不会错过优惠

### Acceptance Criteria

1. 后台自动刷新商品价格
2. 价格变化显示标签（降价绿/涨价红）
3. 降价时发送本地通知
4. 刷新间隔可配置
5. 支持手动刷新

### Tasks / Subtasks

- [ ] 创建价格刷新服务 (AC: 1, 4)
  - [ ] 创建 `lib/services/price_refresh_service.dart`
  - [ ] 单例模式
  - [ ] 定时刷新
- [ ] 实现价格对比 (AC: 2)
  - [ ] 对比 initialPrice 和 currentPrice
  - [ ] 更新 CartItem
- [ ] 实现通知服务 (AC: 3)
  - [ ] 创建 `lib/services/notification_service.dart`
  - [ ] 跨平台本地通知
  - [ ] 降价通知内容
- [ ] 实现 UI 展示 (AC: 2)
  - [ ] 价格变化标签组件
  - [ ] 绿色降价/红色涨价
- [ ] 实现手动刷新 (AC: 5)
  - [ ] 下拉刷新
  - [ ] 刷新按钮

### Dev Notes

**价格变化标签**:
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    color: isPriceDropped 
      ? Colors.green.withOpacity(0.1) 
      : Colors.red.withOpacity(0.1),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(
    isPriceDropped 
      ? '↓降价 ¥${priceChange.abs().toStringAsFixed(0)}' 
      : '↑涨价 ¥${priceChange.toStringAsFixed(0)}',
    style: TextStyle(
      fontSize: 10,
      color: isPriceDropped ? Colors.green : Colors.red,
    ),
  ),
)
```

**通知服务**:
```dart
class NotificationService {
  static Future<void> init();
  static Future<void> showPriceDropNotification(ProductModel product, double oldPrice, double newPrice);
}
```

### Testing

**测试文件位置**: `test/services/price_refresh_service_test.dart`

**测试要求**:
- 测试价格刷新
- 测试变化检测
- 测试通知触发

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 4.5: 结算功能

### Status
Draft

### Story
**As a** 推广者,  
**I want** 批量复制选中商品的推广链接,  
**so that** 我能高效进行商品推广

### Acceptance Criteria

1. 底部显示已选数量和合计金额
2. 结算按钮在未选中时禁用
3. 点击结算显示链接生成弹窗
4. 支持单个复制和批量复制
5. 复制成功有提示反馈

### Tasks / Subtasks

- [ ] 实现底部结算栏 (AC: 1, 2)
  - [ ] 全选复选框
  - [ ] 已选数量显示
  - [ ] 合计金额计算
  - [ ] 结算按钮状态
- [ ] 创建结算弹窗 (AC: 3)
  - [ ] 商品列表
  - [ ] 推广链接生成状态
  - [ ] 单个复制按钮
  - [ ] 批量复制按钮
- [ ] 实现链接复制 (AC: 4, 5)
  - [ ] 调用推广链接服务
  - [ ] 复制到剪贴板
  - [ ] SnackBar 提示

### Dev Notes

**底部结算栏**:
```dart
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 8,
        offset: Offset(0, -2),
      ),
    ],
  ),
  child: SafeArea(
    child: Row(
      children: [
        Checkbox(value: isAllSelected, onChanged: toggleSelectAll),
        Text('全选'),
        Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('已选 $selectedCount 件'),
            Text('合计: ¥${totalPrice.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(width: 16),
        FilledButton(
          onPressed: selectedCount > 0 ? onCheckout : null,
          child: Text('结算'),
        ),
      ],
    ),
  ),
)
```

### Testing

**测试文件位置**: `test/features/cart/checkout_test.dart`

**测试要求**:
- 测试金额计算
- 测试按钮状态
- 测试链接复制

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |



