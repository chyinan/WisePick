# 快淘帮 WisePick - AI UI 生成提示词文档

**版本**: 1.0  
**创建日期**: 2026-01-06  
**文档状态**: 正式版  
**设计师**: Sally (UX Expert Agent)

---

## 文档说明

本文档包含用于 AI UI 生成工具（如 Vercel v0、Lovable.ai、Cursor 等）的优化提示词。每个提示词都经过精心设计，遵循结构化提示框架，可直接复制使用或根据需要调整。

**使用方法**:
1. 选择对应的提示词模块
2. 复制完整提示词内容
3. 粘贴到 AI UI 生成工具中
4. 根据生成结果进行迭代优化

**重要提醒**: AI 生成的代码需要人工审查、测试和优化才能用于生产环境。

---

## 目录

1. [项目基础上下文](#1-项目基础上下文)
2. [完整应用框架提示词](#2-完整应用框架提示词)
3. [聊天页面提示词](#3-聊天页面提示词)
4. [商品卡片组件提示词](#4-商品卡片组件提示词)
5. [选品车页面提示词](#5-选品车页面提示词)
6. [设置页面提示词](#6-设置页面提示词)
7. [主题系统提示词](#7-主题系统提示词)
8. [响应式布局提示词](#8-响应式布局提示词)
9. [动效组件提示词](#9-动效组件提示词)
10. [完整页面组合提示词](#10-完整页面组合提示词)

---

## 1. 项目基础上下文

> 在使用其他提示词之前，首先将此上下文提供给 AI 工具，建立项目背景。

```
# 项目基础上下文 - 快淘帮 WisePick

## 项目概述
快淘帮 WisePick 是一款基于 AI 的智能购物推荐应用，帮助用户在多个电商平台（淘宝、京东、拼多多）中快速找到心仪商品。

## 技术栈
- **框架**: Flutter 3.9+ (Dart)
- **状态管理**: Riverpod 2.5
- **本地存储**: Hive
- **UI 框架**: Material Design 3
- **网络请求**: Dio

## 设计系统
- **设计规范**: Material Design 3
- **主色调**: #6750A4 (紫色)
- **中文字体**: Noto Sans SC
- **圆角规范**: 按钮 20dp, 卡片 12dp, 输入框 8dp
- **间距基数**: 4dp

## 核心功能模块
1. AI 聊天助手 - 自然语言购物推荐
2. 选品车 - 商品收藏和管理
3. 推广链接生成 - 淘宝/京东/拼多多转链
4. 设置 - 应用配置管理

## 目标平台
Windows, macOS, Linux, Android, iOS, Web

## 设计原则
1. AI 优先 - 聊天界面作为核心入口
2. 清晰简洁 - 信息展示一目了然
3. 渐进披露 - 按需展示复杂功能
4. 无障碍设计 - WCAG 2.1 AA 合规
```

---

## 2. 完整应用框架提示词

### 2.1 应用主框架 (适用于 v0/Lovable)

```
# 高级目标
创建一个智能购物助手应用的完整 Flutter 主框架，包含响应式导航和主题系统。

# 详细步骤要求

1. 创建主入口文件 main.dart:
   - 使用 ProviderScope 包裹整个应用
   - 初始化 Hive 本地存储
   - 配置 MaterialApp 使用 Material Design 3
   - 支持深色/浅色主题切换
   - 应用名称: 快淘帮 WisePick

2. 创建响应式导航框架 HomePage:
   - 使用 LayoutBuilder 检测屏幕宽度
   - 断点: 800dp
   - 桌面端 (>800dp): 使用 NavigationRail 左侧导航
   - 移动端 (≤800dp): 使用 BottomNavigationBar 底部导航
   
3. 导航项配置:
   - AI 助手 (Icon: smart_toy, 默认选中)
   - 选品车 (Icon: shopping_cart, 显示数量徽章)
   - 设置 (Icon: settings)

4. 页面切换使用 IndexedStack 保持状态

# 代码示例和约束

```dart
// 主题配置示例
ThemeData(
  useMaterial3: true,
  colorSchemeSeed: Color(0xFF6750A4),
  fontFamily: 'NotoSansSC',
)

// NavigationRail 配置
NavigationRail(
  selectedIndex: _selectedIndex,
  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
  labelType: NavigationRailLabelType.selected,
  destinations: [...],
)
```

# 范围限制
- 只创建框架结构，各页面内容后续实现
- 不要创建完整的状态管理逻辑
- 使用占位符 Widget 替代实际页面内容
- 确保代码可编译运行

# 文件结构
```
lib/
├── main.dart
├── app.dart
├── screens/
│   └── home_page.dart
└── core/
    └── theme/
        └── app_theme.dart
```
```

---

## 3. 聊天页面提示词

### 3.1 聊天页面完整布局

```
# 高级目标
创建一个现代化的 AI 聊天界面，支持流式消息显示和商品推荐卡片嵌入。

# 详细步骤要求

1. 页面整体布局 (ChatPage):
   - 顶部: AppBar 显示会话标题，右侧有"新建会话"和"清空对话"按钮
   - 中间: 可滚动的消息列表 (ListView.builder)
   - 底部: 输入框区域，包含多行文本输入和发送按钮

2. 消息气泡组件 (MessageBubble):
   - 用户消息: 右对齐，紫色背景 (#6750A4)，白色文字
   - AI 消息: 左对齐，灰色背景 (Surface Variant)，带 AI 头像
   - 系统消息: 居中显示，灰色小字
   - 气泡圆角: 16dp，发送方向的角为 4dp

3. 流式文字效果:
   - AI 回复支持逐字显示（打字机效果）
   - 显示闪烁的光标指示正在输入
   - 完成后光标消失

4. 商品推荐卡片区:
   - 嵌入在 AI 消息中
   - 横向滚动的商品卡片列表
   - 每个卡片可点击展开详情

5. 快捷建议区:
   - 位于输入框上方
   - 水平滚动的建议芯片
   - 示例: "推荐耳机", "查看优惠", "比较价格"

6. 输入区域:
   - 圆角输入框 (borderRadius: 24)
   - 支持多行输入 (maxLines: 5)
   - 发送按钮 (圆形，主题色)
   - 输入为空时发送按钮置灰

# 视觉规范

```dart
// 消息气泡样式
// 用户消息
Container(
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.primary,
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(4),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    ),
  ),
)

// AI 消息
Container(
  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surfaceVariant,
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(4),
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    ),
  ),
)
```

# 交互要求
- 新消息自动滚动到底部
- 长按消息显示复制菜单
- 点击商品卡片展开底部弹窗
- 输入框获得焦点时键盘不遮挡

# 范围限制
- 使用 StatefulWidget 管理本地 UI 状态
- 消息数据使用 Mock 数据展示
- 不实现实际的 AI API 调用
- 专注于 UI 实现，状态管理后续集成
```

### 3.2 流式文字动画组件

```
# 高级目标
创建一个支持流式文字显示的动画组件，模拟 AI 逐字输出效果。

# 详细步骤要求

1. 创建 StreamingText Widget:
   - 接收完整文本作为参数
   - 支持配置每字符显示间隔 (默认 30ms)
   - 支持显示/隐藏输入光标
   - 支持动画完成回调

2. 光标动画:
   - 闪烁的竖线光标 "|"
   - 闪烁频率: 500ms
   - 文字完成后光标消失

3. 性能优化:
   - 使用 AnimatedBuilder 减少重绘
   - 大文本分段渲染
   - 支持取消动画

# 代码示例

```dart
class StreamingText extends StatefulWidget {
  final String text;
  final Duration charDelay;
  final bool showCursor;
  final VoidCallback? onComplete;
  
  const StreamingText({
    required this.text,
    this.charDelay = const Duration(milliseconds: 30),
    this.showCursor = true,
    this.onComplete,
  });
}

// 使用示例
StreamingText(
  text: "为您推荐以下商品...",
  charDelay: Duration(milliseconds: 25),
  onComplete: () => print("动画完成"),
)
```

# 范围限制
- 只创建动画组件，不涉及网络请求
- 支持 dispose 时正确清理动画
- 确保无内存泄漏
```

---

## 4. 商品卡片组件提示词

### 4.1 商品卡片组件

```
# 高级目标
创建一个可复用的商品卡片组件，支持多种显示模式和交互状态。

# 详细步骤要求

1. 创建 ProductCard Widget:
   - 紧凑模式 (compact): 用于列表视图，高度固定 120dp
   - 标准模式 (standard): 用于网格视图，宽高比 3:4
   - 聊天模式 (chat): 用于聊天嵌入，宽度固定 160dp

2. 卡片内容:
   - 商品图片 (左侧或顶部，圆角 8dp)
   - 平台标识徽章 (淘宝橙/京东红/拼多多红)
   - 商品标题 (最多 2 行，溢出省略)
   - 价格区域:
     - 现价 (大字，主题色)
     - 原价 (小字，删除线)
     - 优惠券 (红色徽章，如有)
   - 销量和评分 (灰色小字)
   - 店铺名称 (灰色小字)

3. 交互状态:
   - 默认状态
   - 按压状态 (轻微缩放 0.98)
   - 选中状态 (显示勾选框，边框高亮)
   - 加载状态 (骨架屏)
   - 禁用状态 (灰度显示，"已下架"标签)

4. 平台徽章颜色:
   - 淘宝: #FF5722
   - 京东: #E53935
   - 拼多多: #FF4E4E

# 代码示例

```dart
class ProductCard extends StatelessWidget {
  final ProductModel product;
  final ProductCardMode mode;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  
  const ProductCard({
    required this.product,
    this.mode = ProductCardMode.standard,
    this.isSelected = false,
    this.isLoading = false,
    this.onTap,
    this.onLongPress,
  });
}

enum ProductCardMode { compact, standard, chat }

// 商品模型
class ProductModel {
  final String id;
  final String platform; // 'taobao' | 'jd' | 'pdd'
  final String title;
  final double price;
  final double? originalPrice;
  final double? coupon;
  final String imageUrl;
  final int? sales;
  final double? rating;
  final String? shopTitle;
}
```

# 视觉规范

```dart
// 价格显示
Text(
  '¥${product.price.toStringAsFixed(0)}',
  style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
    color: Theme.of(context).colorScheme.primary,
  ),
)

// 原价 (删除线)
Text(
  '¥${product.originalPrice}',
  style: TextStyle(
    fontSize: 12,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    decoration: TextDecoration.lineThrough,
  ),
)

// 平台徽章
Container(
  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
  decoration: BoxDecoration(
    color: _getPlatformColor(product.platform),
    borderRadius: BorderRadius.circular(4),
  ),
  child: Text(
    _getPlatformName(product.platform),
    style: TextStyle(fontSize: 10, color: Colors.white),
  ),
)
```

# 范围限制
- 组件应完全无状态 (Stateless)，状态由父组件管理
- 图片使用 FadeInImage 支持渐入
- 支持 Hero 动画用于详情页过渡
- 骨架屏使用 shimmer 效果
```

### 4.2 商品详情底部弹窗

```
# 高级目标
创建商品详情底部弹窗组件，展示完整商品信息和操作按钮。

# 详细步骤要求

1. 弹窗结构 (使用 showModalBottomSheet):
   - 最大高度: 屏幕高度的 85%
   - 顶部圆角: 28dp
   - 可拖拽关闭
   - 支持滚动内容

2. 内容区域:
   a) 拖拽指示器 (居中灰色横条)
   b) 商品大图 (16:9 比例，可点击放大)
   c) 商品标题 (最多 3 行)
   d) 标签组 (平台、评分、销量)
   e) 价格区域:
      - 现价: 大字加粗，主题色
      - 原价: 删除线
      - 优惠券: 红色标签
      - 预估佣金: 绿色文字
   f) 店铺信息
   g) 商品描述 (可展开/收起)

3. 底部操作栏 (固定):
   - 加入选品车 (主要按钮)
   - 复制推广链接 (次要按钮)
   - 外部打开 (图标按钮)

# 代码示例

```dart
void showProductDetail(BuildContext context, ProductModel product) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ProductDetailSheet(product: product),
  );
}

class ProductDetailSheet extends StatelessWidget {
  final ProductModel product;
  
  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
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
            Container(
              width: 32,
              height: 4,
              margin: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // 可滚动内容...
            Expanded(child: ListView(controller: scrollController, ...)),
            // 底部操作栏
            SafeArea(child: _buildActionBar()),
          ],
        ),
      ),
    );
  }
}
```

# 动画要求
- 打开时从底部滑入 (350ms, easeOutCubic)
- 图片支持 Hero 动画
- 操作按钮有点击反馈

# 范围限制
- 使用 showModalBottomSheet 而非自定义
- 操作按钮的实际功能使用回调
- 专注于 UI 实现
```

---

## 5. 选品车页面提示词

### 5.1 选品车页面完整布局

```
# 高级目标
创建选品车页面，支持按店铺分组显示商品，提供批量操作和结算功能。

# 详细步骤要求

1. 页面整体布局:
   - 顶部: AppBar 显示"选品车 (数量)"，右侧有批量操作按钮
   - 中间: 按店铺分组的商品列表 (可滚动)
   - 底部: 固定的结算栏

2. 空状态显示:
   - 居中显示空购物车插图
   - 文案: "选品车是空的"
   - 描述: "去和 AI 助手聊聊，发现心仪商品吧"
   - 操作按钮: "开始聊天"

3. 店铺分组:
   - 分组标题显示店铺名和商品数量
   - 可点击展开/收起
   - 每个分组下显示该店铺的商品列表

4. 商品卡片 (列表项):
   - 左侧: 选择框 (Checkbox)
   - 中间: 商品图片 + 信息
     - 标题 (1行)
     - 价格 (现价 + 原价)
     - 价格变化标签 (如有)
   - 右侧: 数量调节器 + 删除按钮

5. 价格变化标签:
   - 降价: 绿色背景，"↓降价 ¥50"
   - 涨价: 红色背景，"↑涨价 ¥30"

6. 数量调节器:
   - 减号按钮 (数量为1时禁用)
   - 数量显示
   - 加号按钮

7. 底部结算栏:
   - 全选复选框 + "全选"文字
   - 已选数量和合计金额
   - 结算按钮 (主要按钮样式)

# 代码示例

```dart
// 店铺分组数据结构
class ShopGroup {
  final String shopName;
  final String platform;
  final List<CartItem> items;
  bool isExpanded;
}

class CartItem {
  final ProductModel product;
  int quantity;
  bool isSelected;
  double? initialPrice;  // 加入时的价格
  double? currentPrice;  // 当前价格
}

// 价格变化计算
double get priceChange => (currentPrice ?? product.price) - (initialPrice ?? product.price);
bool get hasPriceChanged => priceChange.abs() > 0.01;
bool get isPriceDropped => priceChange < 0;
```

# 视觉规范

```dart
// 价格变化标签
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

// 底部结算栏
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
        Checkbox(value: isAllSelected, onChanged: ...),
        Text('全选'),
        Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('已选 ${selectedCount} 件'),
            Text(
              '合计: ¥${totalPrice.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
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

# 交互要求
- 左滑商品显示删除按钮（移动端）
- 点击商品跳转详情
- 批量删除需要确认对话框
- 结算按钮显示生成链接弹窗

# 范围限制
- 使用 Mock 数据展示
- 状态管理使用 StatefulWidget
- 专注于 UI 实现，实际存储后续集成
```

---

## 6. 设置页面提示词

### 6.1 用户设置页面

```
# 高级目标
创建用户设置页面，包含外观设置、通知设置和关于信息。

# 详细步骤要求

1. 页面整体布局:
   - 顶部: AppBar 显示"设置"
   - 内容: 分组卡片式设置列表
   - 使用 ListView 支持滚动

2. 设置分组 (使用 Card 包裹):
   
   a) 外观设置:
      - 深色模式开关 (Switch)
      - 主题色选择 (点击展开颜色选择器)
   
   b) 通知设置:
      - 价格变化通知 (Switch)
      - 推送通知 (Switch)
   
   c) 关于:
      - 应用版本 (显示文字)
      - 开源许可 (点击跳转)
      - 检查更新 (点击触发)

3. 管理员入口 (隐藏):
   - 点击"关于"区域 7 次触发
   - 触发后弹出密码输入对话框
   - 密码正确后跳转管理员设置页

4. 设置项样式:
   - 使用 ListTile 组件
   - 左侧图标 + 标题 + 副标题
   - 右侧控件 (Switch/箭头/文字)

# 代码示例

```dart
// 设置分组卡片
Card(
  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(
          '外观设置',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      ListTile(
        leading: Icon(Icons.dark_mode_outlined),
        title: Text('深色模式'),
        subtitle: Text('跟随系统或手动切换'),
        trailing: Switch(
          value: isDarkMode,
          onChanged: (value) => toggleDarkMode(value),
        ),
      ),
      Divider(height: 1, indent: 56),
      ListTile(
        leading: Icon(Icons.palette_outlined),
        title: Text('主题色'),
        trailing: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: currentThemeColor,
            shape: BoxShape.circle,
          ),
        ),
        onTap: () => showColorPicker(),
      ),
    ],
  ),
)

// 隐藏入口计数器
int _aboutTapCount = 0;

void _onAboutTap() {
  _aboutTapCount++;
  if (_aboutTapCount >= 7) {
    _aboutTapCount = 0;
    _showAdminLoginDialog();
  }
}
```

# 视觉规范
- 卡片圆角: 12dp
- 卡片间距: 8dp
- 分组标题: titleSmall, 主题色
- 图标大小: 24dp
- 使用 Divider 分隔同组设置项

# 范围限制
- 设置数据使用本地状态管理
- 颜色选择器使用 Flutter 内置或简单实现
- 不实现实际的通知推送逻辑
```

### 6.2 管理员设置页面

```
# 高级目标
创建管理员设置页面，用于配置 API Key、后端地址等高级选项。

# 详细步骤要求

1. 页面整体布局:
   - 顶部: AppBar 显示"管理员设置"，带返回按钮
   - 内容: 分组配置表单
   - 底部: 保存按钮 (固定或跟随滚动)

2. 配置分组:

   a) OpenAI 配置:
      - API Key (密码输入框，支持显示/隐藏)
      - API 地址 (文本输入框，默认值提示)
      - AI 模型 (下拉选择，支持获取可用模型)
      - Max Tokens (数字输入框)
   
   b) 后端配置:
      - 后端代理地址 (文本输入框)
      - 测试连接按钮
   
   c) 京东联盟配置:
      - subUnionId (文本输入框)
      - PID (文本输入框)
   
   d) 调试选项:
      - Prompt 嵌入 (Switch)
      - 显示原始响应 (Switch)
      - Mock AI 模式 (Switch)

3. 表单验证:
   - API Key 不能为空（如果启用 AI）
   - URL 格式验证
   - 保存前验证所有字段

4. 操作反馈:
   - 保存成功显示 SnackBar
   - 测试连接显示结果对话框
   - 验证失败显示错误提示

# 代码示例

```dart
// API Key 输入框
TextFormField(
  controller: _apiKeyController,
  obscureText: !_showApiKey,
  decoration: InputDecoration(
    labelText: 'OpenAI API Key',
    hintText: 'sk-...',
    prefixIcon: Icon(Icons.key),
    suffixIcon: IconButton(
      icon: Icon(_showApiKey ? Icons.visibility_off : Icons.visibility),
      onPressed: () => setState(() => _showApiKey = !_showApiKey),
    ),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  ),
  validator: (value) {
    if (value?.isEmpty ?? true) return 'API Key 不能为空';
    if (!value!.startsWith('sk-')) return 'API Key 格式不正确';
    return null;
  },
)

// 模型选择下拉
DropdownButtonFormField<String>(
  value: _selectedModel,
  decoration: InputDecoration(
    labelText: 'AI 模型',
    prefixIcon: Icon(Icons.smart_toy),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  ),
  items: _availableModels.map((model) => 
    DropdownMenuItem(value: model, child: Text(model))
  ).toList(),
  onChanged: (value) => setState(() => _selectedModel = value),
)

// 调试开关
SwitchListTile(
  title: Text('Mock AI 模式'),
  subtitle: Text('使用模拟数据，不调用真实 API'),
  value: _useMockAI,
  onChanged: (value) => setState(() => _useMockAI = value),
)
```

# 视觉规范
- 输入框使用 OutlineInputBorder，圆角 8dp
- 分组使用 Card 包裹
- 保存按钮: FilledButton，宽度 100%
- 错误提示: 红色文字

# 范围限制
- 使用 Form + TextFormField 进行表单管理
- 配置数据使用 Hive 存储
- 测试连接使用简单的 HTTP 请求验证
- 模型列表可以硬编码或通过 API 获取
```

---

## 7. 主题系统提示词

### 7.1 完整主题配置

```
# 高级目标
创建完整的 Material Design 3 主题系统，支持浅色/深色模式切换和动态颜色。

# 详细步骤要求

1. 创建 AppTheme 类:
   - 定义浅色主题 (lightTheme)
   - 定义深色主题 (darkTheme)
   - 支持自定义种子颜色
   - 配置中文字体

2. 颜色配置:
   - 主色: #6750A4 (紫色)
   - 次色: #625B71
   - 错误色: #B3261E
   - 成功色: #2E7D32
   - 警告色: #F57C00

3. 字体配置:
   - 主字体: Noto Sans SC
   - 回退字体: Roboto, system-ui
   - 配置完整的 TextTheme

4. 组件主题覆盖:
   - AppBar: 透明背景，无阴影
   - Card: 圆角 12dp
   - Button: 圆角 20dp
   - TextField: 圆角 8dp
   - BottomSheet: 顶部圆角 28dp

5. ThemeProvider (使用 Riverpod):
   - 支持 light/dark/system 三种模式
   - 状态持久化到 Hive
   - 提供主题切换方法

# 代码示例

```dart
// app_theme.dart
class AppTheme {
  static const _primaryColor = Color(0xFF6750A4);
  static const _fontFamily = 'NotoSansSC';
  
  static ThemeData lightTheme({Color? seedColor}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor ?? _primaryColor,
      brightness: Brightness.light,
    );
    
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: _fontFamily,
      
      // AppBar 主题
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
      
      // Card 主题
      cardTheme: CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: colorScheme.surfaceVariant.withOpacity(0.5),
      ),
      
      // 按钮主题
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      
      // 输入框主题
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceVariant.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      
      // 底部弹窗主题
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
  
  static ThemeData darkTheme({Color? seedColor}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor ?? _primaryColor,
      brightness: Brightness.dark,
    );
    
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: _fontFamily,
      // ... 与 lightTheme 相同的组件主题配置
    );
  }
}

// theme_provider.dart
enum ThemeMode { light, dark, system }

class ThemeNotifier extends StateNotifier<ThemeMode> {
  final Box _settingsBox;
  
  ThemeNotifier(this._settingsBox) 
    : super(_loadThemeMode(_settingsBox));
  
  static ThemeMode _loadThemeMode(Box box) {
    final String? saved = box.get('theme_mode');
    return ThemeMode.values.firstWhere(
      (e) => e.name == saved,
      orElse: () => ThemeMode.system,
    );
  }
  
  void setThemeMode(ThemeMode mode) {
    state = mode;
    _settingsBox.put('theme_mode', mode.name);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  final box = Hive.box('settings');
  return ThemeNotifier(box);
});
```

# 范围限制
- 使用 Material Design 3 的 ColorScheme.fromSeed
- 字体文件需预先配置在 pubspec.yaml
- 主题状态使用 Riverpod 管理
- 支持运行时动态切换
```

---

## 8. 响应式布局提示词

### 8.1 响应式导航框架

```
# 高级目标
创建自适应导航框架，在不同屏幕尺寸下自动切换导航模式。

# 详细步骤要求

1. 断点定义:
   - compact: < 600dp (手机)
   - medium: 600-839dp (平板竖屏)
   - expanded: 840-1199dp (平板横屏/小桌面)
   - large: >= 1200dp (大桌面)

2. 导航模式:
   - compact/medium: BottomNavigationBar
   - expanded: NavigationRail (收起)
   - large: NavigationRail (展开)

3. 内容布局:
   - compact: 单列全宽
   - medium: 带内边距的单列
   - expanded: 双列 (导航 + 内容)
   - large: 三列 (导航 + 内容 + 详情面板)

4. 实现 ResponsiveLayout Widget:
   - 自动检测屏幕尺寸
   - 提供 builder 回调
   - 支持自定义断点

# 代码示例

```dart
// responsive_layout.dart
enum ScreenSize { compact, medium, expanded, large }

class ResponsiveLayout extends StatelessWidget {
  final Widget Function(BuildContext, ScreenSize) builder;
  
  const ResponsiveLayout({required this.builder});
  
  static ScreenSize getScreenSize(double width) {
    if (width < 600) return ScreenSize.compact;
    if (width < 840) return ScreenSize.medium;
    if (width < 1200) return ScreenSize.expanded;
    return ScreenSize.large;
  }
  
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = getScreenSize(constraints.maxWidth);
        return builder(context, screenSize);
      },
    );
  }
}

// adaptive_scaffold.dart
class AdaptiveScaffold extends StatefulWidget {
  final List<NavigationDestination> destinations;
  final List<Widget> pages;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  
  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      builder: (context, screenSize) {
        switch (screenSize) {
          case ScreenSize.compact:
          case ScreenSize.medium:
            return Scaffold(
              body: pages[selectedIndex],
              bottomNavigationBar: NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                destinations: destinations,
              ),
            );
          
          case ScreenSize.expanded:
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    labelType: NavigationRailLabelType.selected,
                    destinations: destinations.map((d) => 
                      NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      )
                    ).toList(),
                  ),
                  VerticalDivider(width: 1),
                  Expanded(child: pages[selectedIndex]),
                ],
              ),
            );
          
          case ScreenSize.large:
            return Scaffold(
              body: Row(
                children: [
                  NavigationRail(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: onDestinationSelected,
                    extended: true, // 展开模式
                    destinations: destinations.map((d) => 
                      NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      )
                    ).toList(),
                  ),
                  VerticalDivider(width: 1),
                  Expanded(
                    flex: 2,
                    child: pages[selectedIndex],
                  ),
                  // 详情面板 (可选)
                  if (showDetailPanel)
                    Expanded(
                      flex: 1,
                      child: DetailPanel(),
                    ),
                ],
              ),
            );
        }
      },
    );
  }
}
```

# 使用示例

```dart
AdaptiveScaffold(
  selectedIndex: _selectedIndex,
  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
  destinations: [
    NavigationDestination(
      icon: Icon(Icons.smart_toy_outlined),
      selectedIcon: Icon(Icons.smart_toy),
      label: 'AI 助手',
    ),
    NavigationDestination(
      icon: Badge(
        label: Text('$cartCount'),
        child: Icon(Icons.shopping_cart_outlined),
      ),
      selectedIcon: Badge(
        label: Text('$cartCount'),
        child: Icon(Icons.shopping_cart),
      ),
      label: '选品车',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '设置',
    ),
  ],
  pages: [
    ChatPage(),
    CartPage(),
    SettingsPage(),
  ],
)
```

# 范围限制
- 使用 LayoutBuilder 检测尺寸
- 避免使用 MediaQuery（性能考虑）
- 导航项图标使用 outlined/filled 变体区分状态
- 详情面板可选实现
```

---

## 9. 动效组件提示词

### 9.1 页面过渡动画

```
# 高级目标
创建自定义页面过渡动画，提供流畅的页面切换体验。

# 详细步骤要求

1. 创建 FadeSlideTransition:
   - 淡入 + 轻微滑动效果
   - 时长: 300ms
   - 曲线: easeOutCubic

2. 创建 SharedAxisTransition:
   - 支持水平/垂直轴
   - 遵循 Material Motion 规范

3. 创建 PageRouteBuilder 封装:
   - 简化使用
   - 支持自定义参数

# 代码示例

```dart
// fade_slide_route.dart
class FadeSlideRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  
  FadeSlideRoute({required this.page})
    : super(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration(milliseconds: 300),
        reverseTransitionDuration: Duration(milliseconds: 250),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          
          return FadeTransition(
            opacity: curvedAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0.03, 0),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: child,
            ),
          );
        },
      );
}

// 使用
Navigator.push(
  context,
  FadeSlideRoute(page: ProductDetailPage(product: product)),
);
```

# 范围限制
- 动画时长不超过 350ms
- 支持系统"减少动画"设置
- 确保流畅 60fps
```

### 9.2 加载状态动画

```
# 高级目标
创建统一的加载状态组件，包含骨架屏和 shimmer 效果。

# 详细步骤要求

1. 创建 ShimmerEffect Widget:
   - 从左到右的高光扫过效果
   - 循环播放
   - 时长: 1.5s

2. 创建 SkeletonLoader:
   - 支持自定义形状 (矩形/圆形/文字)
   - 使用 ShimmerEffect

3. 创建 ProductCardSkeleton:
   - 模拟 ProductCard 的骨架

4. 创建 MessageSkeleton:
   - 模拟消息气泡的骨架

# 代码示例

```dart
// shimmer_effect.dart
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  
  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat();
  }
  
  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor ?? 
      Theme.of(context).colorScheme.surfaceVariant;
    final highlightColor = widget.highlightColor ?? 
      Theme.of(context).colorScheme.surface;
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ].map((s) => s.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

// skeleton_loader.dart
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  
  const SkeletonBox({
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 4,
  });
  
  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

// product_card_skeleton.dart
class ProductCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            // 图片骨架
            SkeletonBox(width: 80, height: 80, borderRadius: 8),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题骨架
                  SkeletonBox(height: 16),
                  SizedBox(height: 8),
                  SkeletonBox(height: 16, width: 150),
                  SizedBox(height: 12),
                  // 价格骨架
                  SkeletonBox(height: 20, width: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

# 范围限制
- 动画使用 AnimationController
- 支持 dispose 清理
- 颜色跟随主题
```

---

## 10. 完整页面组合提示词

### 10.1 一键生成完整聊天模块

```
# 高级目标
一次性生成完整的 AI 聊天模块，包含所有必要组件和交互逻辑。

# 项目上下文
- 框架: Flutter 3.9+ (Dart)
- 状态管理: Riverpod 2.5
- 设计系统: Material Design 3
- 主色调: #6750A4

# 需要生成的文件

1. lib/features/chat/
   ├── chat_page.dart              # 聊天页面主体
   ├── widgets/
   │   ├── message_bubble.dart     # 消息气泡组件
   │   ├── streaming_text.dart     # 流式文字动画
   │   ├── product_cards_row.dart  # 商品卡片横向列表
   │   ├── quick_suggestions.dart  # 快捷建议
   │   └── chat_input.dart         # 输入框组件
   ├── models/
   │   └── chat_message.dart       # 消息模型
   └── providers/
       └── chat_provider.dart      # 聊天状态管理

# 详细要求

## chat_page.dart
- Scaffold 结构: AppBar + 消息列表 + 输入区
- 使用 Consumer 监听状态
- 支持下拉刷新加载历史
- 新消息自动滚动到底部

## message_bubble.dart
- 用户/AI/系统三种类型
- 支持嵌入商品卡片
- 支持流式文字显示
- 长按复制功能

## streaming_text.dart
- 打字机效果，每字 25ms
- 闪烁光标
- 完成回调

## product_cards_row.dart
- 横向滚动
- 每张卡片宽 160dp
- 点击展开详情弹窗

## quick_suggestions.dart
- 水平滚动芯片列表
- 预设: ["推荐耳机", "查看优惠", "比较价格", "推荐相机"]
- 点击填充到输入框

## chat_input.dart
- 多行输入 (1-5 行自适应)
- 发送按钮状态
- 支持回车发送 (桌面端)

## chat_message.dart
```dart
class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'system'
  final String content;
  final DateTime timestamp;
  final List<ProductModel>? products;
  final bool isStreaming;
}
```

## chat_provider.dart
- 消息列表状态
- 发送消息方法
- 模拟 AI 回复 (Mock)
- 流式更新支持

# 视觉规范

```dart
// 消息气泡样式
class MessageBubbleStyle {
  // 用户消息
  static const userBubble = BoxDecoration(
    color: Color(0xFF6750A4), // Primary
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(16),
      topRight: Radius.circular(4),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    ),
  );
  
  // AI 消息
  static BoxDecoration aiBubble(BuildContext context) => BoxDecoration(
    color: Theme.of(context).colorScheme.surfaceVariant,
    borderRadius: BorderRadius.only(
      topLeft: Radius.circular(4),
      topRight: Radius.circular(16),
      bottomLeft: Radius.circular(16),
      bottomRight: Radius.circular(16),
    ),
  );
}

// 间距
const messagePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
const bubblePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
```

# Mock 数据

```dart
final mockMessages = [
  ChatMessage(
    id: '1',
    role: 'assistant',
    content: '你好！我是快淘帮 AI 助手，有什么可以帮你的吗？',
    timestamp: DateTime.now(),
  ),
];

final mockProducts = [
  ProductModel(
    id: '1',
    platform: 'jd',
    title: 'FiiO K7 台式解码耳放一体机',
    price: 2399,
    originalPrice: 2699,
    imageUrl: 'https://placeholder.com/160x160',
    sales: 5000,
    rating: 4.9,
    shopTitle: '飞傲官方旗舰店',
  ),
  // ... 更多商品
];
```

# 范围限制
- 不实现真实 API 调用，使用 Mock 数据
- 状态管理仅使用 Riverpod
- 商品详情弹窗复用现有组件
- 确保所有代码可编译运行

# 文件依赖关系
chat_page.dart
  └── imports: message_bubble.dart, chat_input.dart, quick_suggestions.dart
  └── uses: chat_provider.dart

message_bubble.dart
  └── imports: streaming_text.dart, product_cards_row.dart
  └── uses: chat_message.dart

product_cards_row.dart
  └── uses: ProductModel (from products feature)
```

---

## 使用指南

### 最佳实践

1. **分步生成**: 先生成框架，再逐个生成组件，最后组合
2. **提供上下文**: 每次生成前先提供项目基础上下文
3. **迭代优化**: 根据生成结果调整提示词，逐步完善
4. **人工审查**: AI 生成的代码必须人工审查和测试

### 常见问题

**Q: 生成的代码有编译错误怎么办？**
A: 检查导入语句和依赖关系，必要时提供更多上下文信息。

**Q: 样式与设计稿不符怎么办？**
A: 在提示词中提供更具体的视觉规范代码示例。

**Q: 如何生成更复杂的交互？**
A: 将复杂交互拆分为多个步骤，逐一描述并生成。

---

**文档维护者**: UX 设计团队  
**审核者**: 开发团队  
**最后更新**: 2026-01-06

---

*本文档提供的提示词经过优化，适用于主流 AI UI 生成工具