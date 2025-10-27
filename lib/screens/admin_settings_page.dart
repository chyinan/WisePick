import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';

// config not used here

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final TextEditingController _openAiController = TextEditingController();
  // 淘宝/京东配置已改由后端环境变量管理，移除前端输入项
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _backendBaseController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  List<String> _models = [];
  bool _loadingModels = false;
  String? _modelError;
  bool _embedPrompts = true;
  bool _debugAiResponse = false;
  bool _copyFullReturn = false;
  bool _useMockAi = false;
  bool _showProductJson = false;
  String _maxTokens = 'unlimited';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final box = await Hive.openBox('settings');
      final String? openai = box.get('openai_api') as String?;
      // VEAPI 已弃用，不再读取 veapi_key
      final String? backendBase = box.get('backend_base') as String?;
      final String? base = box.get('openai_base') as String?;
      final String? model = box.get('openai_model') as String?;
      // 淘宝/京东配置由后端环境变量管理，前端不再读取这些键
      final bool? embed = box.get('embed_prompts') as bool?;
      final bool? debug = box.get('debug_ai_response') as bool?;
      final bool? copyFull = box.get('copy_full_return') as bool?;
      final bool? mock = box.get('use_mock_ai') as bool?;
      final bool? showJson = box.get('show_product_json') as bool?;
      final String? maxT = box.get('max_tokens') as String?;
      if (mounted) {
        setState(() {
          _openAiController.text = openai ?? '';
          // VEAPI 已弃用，不再展示或设置 veapi_key
          _baseUrlController.text = base ?? '';
          _backendBaseController.text = backendBase ?? 'http://localhost:8080';
          _modelController.text = model ?? 'gpt-3.5-turbo';
          _embedPrompts = embed ?? true;
          _debugAiResponse = debug ?? false;
          _copyFullReturn = copyFull ?? false;
          _useMockAi = mock ?? false;
          _showProductJson = showJson ?? false;
          _maxTokens = maxT ?? 'unlimited';
        });
      }
      // Attempt to fetch available models after loading settings
      _fetchModels();
    } catch (_) {}
  }

  @override
  void dispose() {
    _openAiController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('后台管理设置', style: Theme.of(context).textTheme.titleMedium),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Card(
                surfaceTintColor: colorScheme.surfaceTint,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('后端 Proxy 地址', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _backendBaseController,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: colorScheme.surfaceVariant,
                          hintText: 'http://localhost:8080 或 https://api.yourdomain.com',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('max_tokens', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _maxTokens,
                        items: ['unlimited', '300', '800', '1000', '2000']
                            .map((v) => DropdownMenuItem(value: v, child: Text(v == 'unlimited' ? '不限 (unlimited)' : v)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _maxTokens = v);
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: colorScheme.surfaceVariant,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                surfaceTintColor: colorScheme.surfaceTint,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _embedPrompts,
                      onChanged: (v) => setState(() => _embedPrompts = v),
                      title: Text('嵌入预设提示词', style: Theme.of(context).textTheme.bodyLarge),
                      subtitle: Text('在发送到 AI 前自动将用户问题合并到预设的 system/user prompt 中，便于调试开关。', style: Theme.of(context).textTheme.bodySmall),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    ),
                    const Divider(height: 0),
                    SwitchListTile(
                      value: _debugAiResponse,
                      onChanged: (v) => setState(() => _debugAiResponse = v),
                      title: Text('显示 AI 原始返回', style: Theme.of(context).textTheme.bodyLarge),
                      subtitle: Text('开启后在聊天中会显示从 AI 返回的完整原始 JSON，便于调试。慎选，可能包含较多信息。', style: Theme.of(context).textTheme.bodySmall),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    ),
                    const Divider(height: 0),
                    SwitchListTile(
                      value: _copyFullReturn,
                      onChanged: (v) => setState(() => _copyFullReturn = v),
                      title: Text('复制完整返回', style: Theme.of(context).textTheme.bodyLarge),
                      subtitle: Text('开启后聊天界面右侧的复制按钮将复制 AI 的原始返回（用于调试），关闭则复制展示文本。', style: Theme.of(context).textTheme.bodySmall),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    ),
                    const Divider(height: 0),
                    SwitchListTile(
                      value: _useMockAi,
                      onChanged: (v) => setState(() => _useMockAi = v),
                      title: Text('使用本地 Mock AI', style: Theme.of(context).textTheme.bodyLarge),
                      subtitle: Text('启用后应用将使用内置的假后端响应，节约调用真实 API 的费用（仅用于开发/调试）。', style: Theme.of(context).textTheme.bodySmall),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    ),
                    const Divider(height: 0),
                    SwitchListTile(
                      value: _showProductJson,
                      onChanged: (v) => setState(() => _showProductJson = v),
                      title: Text('显示商品 JSON 按钮', style: Theme.of(context).textTheme.bodyLarge),
                      subtitle: Text('控制商品详情页右上角的 "查看 JSON" 按钮是否可见（便于调试）。', style: Theme.of(context).textTheme.bodySmall),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () async {
                      try {
                        final box = await Hive.openBox('settings');
                        await box.put('openai_api', _openAiController.text.trim());
                        await box.put('openai_base', _baseUrlController.text.trim());
                        await box.put('openai_model', _modelController.text.trim());
                        await box.put('backend_base', _backendBaseController.text.trim());
                        await box.put('debug_ai_response', _debugAiResponse);
                        await box.put('embed_prompts', _embedPrompts);
                        await box.put('copy_full_return', _copyFullReturn);
                        await box.put('show_product_json', _showProductJson);
                        await box.put('max_tokens', _maxTokens);
                        await box.put('use_mock_ai', _useMockAi);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存成功')));
                        Navigator.of(context).pop();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败')));
                      }
                    },
                    child: Text('保存', style: Theme.of(context).textTheme.labelLarge),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('取消', style: Theme.of(context).textTheme.labelLarge),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  String _effectiveBase() {
    final b = _baseUrlController.text.trim();
    if (b.isNotEmpty) return b;
    return 'https://api.openai.com';
  }

  String? _effectiveKey() {
    final v = _openAiController.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelError = null;
      _models = [];
    });
    try {
      final base = _effectiveBase();
      final key = _effectiveKey();
      final dio = Dio();
      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (key != null) headers['Authorization'] = 'Bearer $key';

      // Build models URL: support both base like 'https://host' and 'https://host/v1'
      // Normalize by trimming whitespace and removing trailing slashes
      final normalizedBase = base.trim().replaceAll(RegExp(r'/+ '), '');
      final baseNoTrailing = normalizedBase.replaceAll(RegExp(r'/+$'), '');
      String modelsUrl;
      if (RegExp(r'/v1$', caseSensitive: false).hasMatch(baseNoTrailing)) {
        modelsUrl = '$baseNoTrailing/models';
      } else {
        modelsUrl = '$baseNoTrailing/v1/models';
      }
      final resp = await dio.get(modelsUrl, options: Options(headers: headers));
      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        final list = data['data'] as List<dynamic>?;
        if (list != null) {
          _models = list.map((e) => (e as Map<String, dynamic>)['id'] as String).toList();
        }
      } else {
        _modelError = 'HTTP ${resp.statusCode}';
      }
    } catch (e) {
      _modelError = e.toString();
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }
}

