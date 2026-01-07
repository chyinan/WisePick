# Epic 7: 管理员设置

**Epic ID**: E7  
**创建日期**: 2026-01-06  
**状态**: Draft  
**优先级**: P1

---

## Epic 描述

实现管理员设置功能，包括 API 配置、模型选择和调试选项，需要密码验证才能访问。

## 业务价值

- 支持 API 配置灵活性
- 便于开发和调试
- 保护敏感配置安全

## 依赖关系

- 依赖 Epic 1（应用基础架构）
- 依赖 Epic 8（后端代理服务）

---

## Story 7.1: 管理员入口与验证

### Status
Draft

### Story
**As a** 管理员,  
**I want** 通过密码验证访问后台设置,  
**so that** 敏感配置受到保护

### Acceptance Criteria

1. 点击"关于"7 次触发入口
2. 弹出密码输入框
3. 密码正确后进入管理员设置页
4. 密码错误显示提示
5. 密码通过后端验证

### Tasks / Subtasks

- [ ] 实现隐藏入口 (AC: 1)
  - [ ] 计数器统计点击次数
  - [ ] 7 次后重置并触发
- [ ] 实现密码验证 (AC: 2, 4, 5)
  - [ ] 密码输入对话框
  - [ ] 调用后端 /admin/login
  - [ ] 错误提示
- [ ] 实现页面跳转 (AC: 3)
  - [ ] 验证成功后导航
  - [ ] 进入 AdminSettingsPage

### Dev Notes

**点击计数**:
```dart
int _aboutTapCount = 0;

void _onAboutTap() {
  _aboutTapCount++;
  if (_aboutTapCount >= 7) {
    _aboutTapCount = 0;
    _showAdminLoginDialog();
  }
}
```

**密码验证对话框**:
```dart
void _showAdminLoginDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('管理员登录'),
      content: TextField(
        controller: _passwordController,
        obscureText: true,
        decoration: InputDecoration(
          labelText: '请输入管理员密码',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('取消')),
        FilledButton(onPressed: _verifyPassword, child: Text('确认')),
      ],
    ),
  );
}

Future<void> _verifyPassword() async {
  final response = await apiClient.post('/admin/login', {
    'password': _passwordController.text,
  });
  
  if (response['success'] == true) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => AdminSettingsPage()));
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('密码错误')),
    );
  }
}
```

### Testing

**测试文件位置**: `test/screens/admin_entry_test.dart`

**测试要求**:
- 测试点击计数
- 测试密码验证
- 测试页面跳转

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 7.2: API 配置页面

### Status
Draft

### Story
**As a** 管理员,  
**I want** 配置 OpenAI API 和后端地址,  
**so that** 应用能正确调用 AI 服务

### Acceptance Criteria

1. API Key 输入框（支持显示/隐藏）
2. API 地址输入框
3. AI 模型选择下拉框
4. Max Tokens 输入框
5. 后端代理地址输入框
6. 京东联盟参数配置（subUnionId、pid）
7. 保存按钮
8. 配置验证和测试连接

### Tasks / Subtasks

- [ ] 创建管理员设置页面 (AC: 1-6)
  - [ ] 创建 `lib/screens/admin_settings_page.dart`
  - [ ] OpenAI 配置分组
  - [ ] 后端配置分组
  - [ ] 京东联盟配置分组
- [ ] 实现 API Key 输入 (AC: 1)
  - [ ] 密码输入框
  - [ ] 显示/隐藏切换
  - [ ] 格式验证
- [ ] 实现模型选择 (AC: 3)
  - [ ] DropdownButtonFormField
  - [ ] 获取可用模型列表
- [ ] 实现保存功能 (AC: 7, 8)
  - [ ] 表单验证
  - [ ] 保存到 Hive
  - [ ] 测试连接按钮

### Dev Notes

**配置项**:
| 配置项 | 类型 | 说明 |
|--------|------|------|
| openai_api_key | String | OpenAI API Key |
| openai_api_url | String | API 地址 |
| ai_model | String | AI 模型名称 |
| max_tokens | int | 最大 Token 数 |
| backend_base | String | 后端代理地址 |
| jd_sub_union_id | String | 京东子联盟 ID |
| jd_pid | String | 京东 PID |

**API Key 输入框**:
```dart
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
```

**模型选择**:
```dart
DropdownButtonFormField<String>(
  value: _selectedModel,
  decoration: InputDecoration(
    labelText: 'AI 模型',
    prefixIcon: Icon(Icons.smart_toy),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  ),
  items: ['gpt-4', 'gpt-4-turbo', 'gpt-3.5-turbo'].map((model) => 
    DropdownMenuItem(value: model, child: Text(model))
  ).toList(),
  onChanged: (value) => setState(() => _selectedModel = value),
)
```

### Testing

**测试文件位置**: `test/screens/admin_settings_page_test.dart`

**测试要求**:
- 测试表单验证
- 测试保存功能
- 测试配置读取

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |

---

## Story 7.3: 调试选项与 Mock 模式

### Status
Draft

### Story
**As a** 开发者,  
**I want** 调试选项和 Mock 模式,  
**so that** 我能方便地开发和测试

### Acceptance Criteria

1. Prompt 嵌入开关
2. 显示原始响应开关
3. Mock AI 模式开关
4. Mock 模式下使用模拟数据

### Tasks / Subtasks

- [ ] 实现调试开关 (AC: 1, 2, 3)
  - [ ] SwitchListTile 组件
  - [ ] 保存到 Hive
- [ ] 实现 Mock 模式 (AC: 4)
  - [ ] 检测 Mock 开关
  - [ ] 返回模拟响应
  - [ ] 模拟商品数据

### Dev Notes

**调试开关**:
```dart
SwitchListTile(
  title: Text('Prompt 嵌入'),
  subtitle: Text('在响应中显示系统 Prompt'),
  value: _embedPrompt,
  onChanged: (value) {
    setState(() => _embedPrompt = value);
    _settingsBox.put('embed_prompt', value);
  },
),

SwitchListTile(
  title: Text('显示原始响应'),
  subtitle: Text('显示 AI 返回的原始 JSON'),
  value: _showRawResponse,
  onChanged: (value) {
    setState(() => _showRawResponse = value);
    _settingsBox.put('show_raw_response', value);
  },
),

SwitchListTile(
  title: Text('Mock AI 模式'),
  subtitle: Text('使用模拟数据，不调用真实 API'),
  value: _useMockAI,
  onChanged: (value) {
    setState(() => _useMockAI = value);
    _settingsBox.put('use_mock_ai', value);
  },
),
```

**Mock 响应数据**:
```dart
const mockResponse = '''
为您推荐以下商品：

1. **FiiO K7 台式解码耳放** - ¥2399
   高性能桌面音频设备，适合发烧友

2. **山灵 M0 Pro** - ¥799
   便携高清播放器，性价比之选
''';

const mockProducts = [
  ProductModel(
    id: 'mock_1',
    platform: 'jd',
    title: 'FiiO K7 台式解码耳放一体机',
    price: 2399,
    originalPrice: 2699,
    // ...
  ),
];
```

### Testing

**测试文件位置**: `test/screens/debug_options_test.dart`

**测试要求**:
- 测试开关状态
- 测试 Mock 模式响应

### Change Log

| Date | Version | Description | Author |
|------|---------|-------------|--------|
| 2026-01-06 | 1.0 | 初始创建 | Sarah (PO) |



