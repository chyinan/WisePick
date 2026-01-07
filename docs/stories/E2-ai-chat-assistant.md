# Epic 2: AI 聊天助手

**Epic ID**: E2  
**创建日期**: 2026-01-06  
**状态**: Draft  
**优先级**: P0

---

## Epic 描述

实现 AI 聊天助手核心功能，这是应用的核心入口。用户通过自然语言对话获取商品推荐，AI 能够流式返回响应并嵌入商品卡片展示。

## 业务价值

- 提供智能化的购物推荐体验
- 降低用户搜索商品的门槛
- 通过 AI 对话提高用户粘性和使用时长

## 依赖关系

- 依赖 Epic 1（应用基础架构）
- 依赖 Epic 8（后端代理服务）

---

## Story 2.1: 聊天页面基础布局

### Status
Draft

### Story
**As a** 用户,  
**I want** 有一个清晰的聊天界面,  
**so that** 我可以方便地与 AI 助手对话

### Acceptance Criteria

1. 页面包含顶部标题栏、消息列表和底部输入区
2. 顶部标题栏显示会话标题，包含新建/清空按钮
3. 消息列表可滚动，新消息自动滚动到底部
4. 输入框支持多行输入（最多 5 行）
5. 发送按钮在输入为空时置灰
6. 键盘弹出时输入框不被遮挡

### Tasks / Subtasks

- [ ] 创建聊天页面结构 (AC: 1)
  - [ ] 创建 `lib/screens/chat_page.dart`
  - [ ] 使用 Scaffold + Column 布局
  - [ ] 配置 AppBar
- [ ] 实现消息列表 (AC: 3)
  - [ ] 使用 ListView.builder 实现懒加载
  - [ ] 实现自动滚动到底部
  - [ ] 添加 ScrollController
- [ ] 实现输入区域 (AC: 4, 5, 6)
  - [ ] 创建自适应高度 TextField
  - [ ] 配置 maxLines: 5
  - [ ] 实现发送按钮状态控制
  - [ ] 处理键盘遮挡问题
- [ ] 实现顶部操作栏 (AC: 2)
  - [ ] 显示会话标题
  - [ ] 添加新建会话按钮
  - [ ] 添加清空对话按钮

### Dev Notes

**布局结构**:
```
┌─────────────────────────────────────┐
│  AppBar (会话标题 + 操作按钮)        │
├─────────────────────────────────────┤
│                                     │
│  ListView.builder (消息列表)         │
│                                     │
├─────────────────────────────────────┤
│  快捷建议区 (可选)                   │
├─────────────────────────────────────┤
│  TextField + 发送按钮                │
└─────────────────────────────────────┘
```

**输入框配置**:
```dart
TextField(
  controller: _textController,
  maxLines: 5,
  minLines: 1,
  decoration: InputDecoration(
    hintText: '输入您的需求...',
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(24),
    ),
    suffixIcon: IconButton(
      icon: Icon(Icons.send),
      onPressed: _textController.text.isEmpty ? null : _sendMessage,
    ),
  ),
)
```

### Testing

**测试文件位置**: `test/screens/chat_page_test.dart`

**测试要求**:
- 测试页面渲染
- 测试输入框状态
- 测试滚动行为

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 2.2: 消息气泡组件

### Status
Draft

### Story
**As a** 用户,  
**I want** 清晰区分用户消息和 AI 消息,  
**so that** 我能轻松跟踪对话内容

### Acceptance Criteria

1. 用户消息右对齐，紫色背景，白色文字
2. AI 消息左对齐，灰色背景，带 AI 头像
3. 系统消息居中显示，灰色小字
4. 气泡圆角：16dp，发送方向角为 4dp
5. 长按消息可复制内容
6. 支持嵌入商品卡片（AI 消息）

### Tasks / Subtasks

- [ ] 创建消息气泡组件 (AC: 1, 2, 3)
  - [ ] 创建 `lib/features/chat/widgets/message_bubble.dart`
  - [ ] 实现 UserBubble 变体
  - [ ] 实现 AssistantBubble 变体
  - [ ] 实现 SystemBubble 变体
- [ ] 配置气泡样式 (AC: 4)
  - [ ] 用户气泡：右上角 4dp，其他 16dp
  - [ ] AI 气泡：左上角 4dp，其他 16dp
- [ ] 实现交互功能 (AC: 5)
  - [ ] 长按显示复制菜单
  - [ ] 复制成功显示 SnackBar
- [ ] 支持商品卡片嵌入 (AC: 6)
  - [ ] 检测消息中的商品数据
  - [ ] 渲染商品卡片横向列表

### Dev Notes

**消息模型**:
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

**气泡样式**:
```dart
// 用户消息气泡
BoxDecoration(
  color: Theme.of(context).colorScheme.primary,
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(16),
    topRight: Radius.circular(4),
    bottomLeft: Radius.circular(16),
    bottomRight: Radius.circular(16),
  ),
)

// AI 消息气泡
BoxDecoration(
  color: Theme.of(context).colorScheme.surfaceVariant,
  borderRadius: BorderRadius.only(
    topLeft: Radius.circular(4),
    topRight: Radius.circular(16),
    bottomLeft: Radius.circular(16),
    bottomRight: Radius.circular(16),
  ),
)
```

### Testing

**测试文件位置**: `test/features/chat/widgets/message_bubble_test.dart`

**测试要求**:
- 测试不同类型气泡渲染
- 测试长按复制功能
- 测试商品卡片嵌入

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 2.3: 流式文字动画

### Status
Draft

### Story
**As a** 用户,  
**I want** 看到 AI 逐字输出回复,  
**so that** 我知道 AI 正在处理我的请求

### Acceptance Criteria

1. AI 回复逐字显示（打字机效果）
2. 每字符显示间隔约 25-30ms
3. 显示闪烁的输入光标
4. 光标闪烁频率 500ms
5. 文字完成后光标消失
6. 支持取消动画（页面切换时）

### Tasks / Subtasks

- [ ] 创建流式文字组件 (AC: 1, 2)
  - [ ] 创建 `lib/features/chat/widgets/streaming_text.dart`
  - [ ] 使用 Timer 控制字符显示
  - [ ] 支持配置显示间隔
- [ ] 实现光标动画 (AC: 3, 4, 5)
  - [ ] 创建闪烁光标 Widget
  - [ ] 使用 AnimationController 控制闪烁
  - [ ] 文字完成后停止闪烁
- [ ] 性能优化 (AC: 6)
  - [ ] 使用 AnimatedBuilder 减少重绘
  - [ ] 在 dispose 中取消动画
  - [ ] 大文本分段渲染

### Dev Notes

**组件接口**:
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
```

**光标实现**:
```dart
AnimatedBuilder(
  animation: _cursorController,
  builder: (context, child) {
    return Opacity(
      opacity: _cursorController.value,
      child: Text('|', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  },
)
```

### Testing

**测试文件位置**: `test/features/chat/widgets/streaming_text_test.dart`

**测试要求**:
- 测试文字逐字显示
- 测试光标闪烁
- 测试动画取消

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 2.4: AI 对话服务集成

### Status
Draft

### Story
**As a** 用户,  
**I want** 与 AI 进行真实对话并获取商品推荐,  
**so that** 我能找到符合需求的商品

### Acceptance Criteria

1. 支持调用 OpenAI 兼容 API
2. 支持流式响应接收
3. 支持通过后端代理调用
4. 能够解析 AI 返回的商品推荐 JSON
5. 错误情况有友好提示
6. 支持 Mock AI 模式（离线开发）

### Tasks / Subtasks

- [ ] 创建 ChatService (AC: 1, 2)
  - [ ] 创建 `lib/features/chat/chat_service.dart`
  - [ ] 实现 `getAiReply()` 非流式方法
  - [ ] 实现 `getAiReplyStream()` 流式方法
- [ ] 集成 API 客户端 (AC: 3)
  - [ ] 配置 ApiClient 请求
  - [ ] 支持直接调用或代理调用
  - [ ] 处理 SSE 流式响应
- [ ] 实现响应解析 (AC: 4)
  - [ ] 解析纯文本响应
  - [ ] 解析 JSON 格式商品推荐
  - [ ] 提取商品列表
- [ ] 错误处理 (AC: 5)
  - [ ] 网络错误处理
  - [ ] API 错误处理（401、429、500）
  - [ ] 显示友好错误提示
- [ ] Mock 模式支持 (AC: 6)
  - [ ] 检测 Mock AI 开关
  - [ ] 返回模拟响应

### Dev Notes

**ChatService 接口**:
```dart
class ChatService {
  Future<String> getAiReply(List<ChatMessage> messages);
  Stream<String> getAiReplyStream(List<ChatMessage> messages);
  Future<String> generateConversationTitle(List<ChatMessage> messages);
}
```

**API 请求格式**:
```dart
{
  "model": "gpt-4",
  "messages": [
    {"role": "system", "content": "你是购物助手..."},
    {"role": "user", "content": "推荐一款耳机"}
  ],
  "stream": true
}
```

**商品推荐 JSON 格式**:
```json
{
  "type": "recommendation",
  "products": [
    {
      "id": "123",
      "platform": "jd",
      "title": "商品名称",
      "price": 799,
      ...
    }
  ],
  "summary": "为您推荐以下商品..."
}
```

### Testing

**测试文件位置**: `test/features/chat/chat_service_test.dart`

**测试要求**:
- 测试流式响应解析
- 测试商品 JSON 解析
- 测试 Mock 模式
- 测试错误处理

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 2.5: 会话管理功能

### Status
Draft

### Story
**As a** 用户,  
**I want** 管理多个对话会话,  
**so that** 我可以在不同购物需求间切换

### Acceptance Criteria

1. 支持创建新会话
2. 支持切换历史会话
3. 支持删除会话
4. 会话自动保存
5. 会话标题自动生成
6. 侧边栏显示会话列表

### Tasks / Subtasks

- [ ] 创建会话数据模型 (AC: 1, 4)
  - [ ] 创建 `lib/features/chat/conversation_model.dart`
  - [ ] 实现 Hive TypeAdapter
- [ ] 创建会话仓库 (AC: 4)
  - [ ] 创建 `lib/features/chat/conversation_repository.dart`
  - [ ] 实现 CRUD 操作
  - [ ] 实现自动保存
- [ ] 创建会话状态管理 (AC: 1, 2, 3)
  - [ ] 创建 `lib/features/chat/chat_providers.dart`
  - [ ] 实现 currentConversationProvider
  - [ ] 实现 conversationsProvider
- [ ] 实现会话标题生成 (AC: 5)
  - [ ] 调用 AI 生成标题
  - [ ] 基于首条消息生成
- [ ] 创建会话列表侧边栏 (AC: 6)
  - [ ] 创建 HomeDrawer Widget
  - [ ] 显示会话列表
  - [ ] 支持选中和删除

### Dev Notes

**会话模型**:
```dart
@HiveType(typeId: 1)
class Conversation {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  String title;
  
  @HiveField(2)
  final List<ChatMessage> messages;
  
  @HiveField(3)
  final DateTime createdAt;
  
  @HiveField(4)
  DateTime updatedAt;
}
```

**Provider 结构**:
```dart
final conversationsProvider = StateNotifierProvider<ConversationsNotifier, List<Conversation>>;
final currentConversationProvider = StateProvider<Conversation?>;
final messagesProvider = Provider<List<ChatMessage>>;
```

### Testing

**测试文件位置**: `test/features/chat/conversation_repository_test.dart`

**测试要求**:
- 测试会话 CRUD
- 测试自动保存
- 测试标题生成

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 2.6: 快捷建议与输入增强

### Status
Draft

### Story
**As a** 用户,  
**I want** 有快捷的输入方式,  
**so that** 我能更高效地与 AI 交互

### Acceptance Criteria

1. 输入框上方显示快捷建议芯片
2. 建议芯片水平可滚动
3. 点击芯片填充到输入框
4. 桌面端支持 Enter 发送消息
5. Shift+Enter 换行
6. 预设建议：推荐耳机、查看优惠、比较价格等

### Tasks / Subtasks

- [ ] 创建快捷建议组件 (AC: 1, 2, 3)
  - [ ] 创建 `lib/features/chat/widgets/quick_suggestions.dart`
  - [ ] 使用 SingleChildScrollView + Row
  - [ ] 使用 ActionChip
- [ ] 配置预设建议 (AC: 6)
  - [ ] 定义默认建议列表
  - [ ] 支持动态更新
- [ ] 实现键盘快捷键 (AC: 4, 5)
  - [ ] 检测 Enter 键
  - [ ] 检测 Shift 修饰符
  - [ ] 区分发送和换行

### Dev Notes

**建议芯片样式**:
```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: suggestions.map((s) => Padding(
      padding: EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(s),
        onPressed: () => _fillInput(s),
      ),
    )).toList(),
  ),
)
```

**键盘处理**:
```dart
RawKeyboardListener(
  onKey: (event) {
    if (event is RawKeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (!event.isShiftPressed) {
          _sendMessage();
          return;
        }
      }
    }
  },
  child: TextField(...),
)
```

### Testing

**测试文件位置**: `test/features/chat/widgets/quick_suggestions_test.dart`

**测试要求**:
- 测试建议点击
- 测试键盘快捷键

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |



