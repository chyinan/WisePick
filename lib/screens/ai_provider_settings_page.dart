import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';

/// AI服务商API自定义设置页面
/// 支持：API KEY输入、自定义OpenAI域名、获取模型列表并选择
class AiProviderSettingsPage extends StatefulWidget {
  const AiProviderSettingsPage({super.key});

  @override
  State<AiProviderSettingsPage> createState() => _AiProviderSettingsPageState();
}

class _AiProviderSettingsPageState extends State<AiProviderSettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  
  bool _obscureApiKey = true;
  bool _loading = false;
  bool _loadingModels = false;
  bool _testingConnection = false;
  
  List<String> _models = [];
  String? _modelError;
  String? _connectionTestResult;
  bool? _connectionTestSuccess;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final box = await Hive.openBox('settings');
      if (mounted) {
        setState(() {
          _apiKeyController.text = (box.get('openai_api') as String?) ?? '';
          _baseUrlController.text = (box.get('openai_base') as String?) ?? '';
          _modelController.text = (box.get('openai_model') as String?) ?? 'gpt-3.5-turbo';
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  /// 规范化Base URL
  String _normalizeBaseUrl(String url) {
    String normalizedBase = url.trim();
    if (normalizedBase.isEmpty) {
      return 'https://api.openai.com';
    }
    // 添加协议前缀
    if (!normalizedBase.startsWith('http://') &&
        !normalizedBase.startsWith('https://')) {
      normalizedBase = 'https://$normalizedBase';
    }
    // 移除尾部斜杠
    normalizedBase = normalizedBase.replaceAll(RegExp(r'/+$'), '');
    // 移除可能存在的 /chat/completions 后缀
    const completionsSuffix = '/chat/completions';
    if (normalizedBase.toLowerCase().endsWith(completionsSuffix)) {
      normalizedBase = normalizedBase.substring(
        0,
        normalizedBase.length - completionsSuffix.length,
      );
    }
    return normalizedBase;
  }

  /// 获取模型列表URL
  String _getModelsUrl(String baseUrl) {
    final normalizedBase = _normalizeBaseUrl(baseUrl);
    final baseHasV1 = normalizedBase.toLowerCase().endsWith('/v1');
    return baseHasV1
        ? '$normalizedBase/models'
        : '$normalizedBase/v1/models';
  }

  /// 获取可用模型列表
  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelError = null;
      _models = [];
    });

    try {
      final baseUrl = _baseUrlController.text.trim();
      final apiKey = _apiKeyController.text.trim();
      
      final modelsUrl = _getModelsUrl(baseUrl);
      debugPrint('Fetching models from: $modelsUrl');

      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 15);
      dio.options.receiveTimeout = const Duration(seconds: 30);
      
      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      final resp = await dio.get(modelsUrl, options: Options(headers: headers));
      
      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        final list = data['data'] as List<dynamic>?;
        if (list != null) {
          final modelIds = list
              .map((e) => (e as Map<String, dynamic>)['id'] as String)
              .toList();
          // 排序模型列表，常用模型优先
          modelIds.sort((a, b) {
            // GPT-4 系列优先
            final aIsGpt4 = a.toLowerCase().contains('gpt-4');
            final bIsGpt4 = b.toLowerCase().contains('gpt-4');
            if (aIsGpt4 && !bIsGpt4) return -1;
            if (!aIsGpt4 && bIsGpt4) return 1;
            // GPT-3.5 次之
            final aIsGpt35 = a.toLowerCase().contains('gpt-3.5');
            final bIsGpt35 = b.toLowerCase().contains('gpt-3.5');
            if (aIsGpt35 && !bIsGpt35) return -1;
            if (!aIsGpt35 && bIsGpt35) return 1;
            return a.compareTo(b);
          });
          setState(() {
            _models = modelIds;
          });
        }
      } else {
        setState(() {
          _modelError = '获取模型列表失败: HTTP ${resp.statusCode}';
        });
      }
    } on DioException catch (e) {
      String errorMsg;
      if (e.type == DioExceptionType.connectionTimeout) {
        errorMsg = '连接超时，请检查网络或域名';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMsg = '响应超时';
      } else if (e.response?.statusCode == 401) {
        errorMsg = 'API Key 无效或未授权';
      } else if (e.response?.statusCode == 403) {
        errorMsg = '访问被拒绝';
      } else if (e.response?.statusCode == 404) {
        errorMsg = '接口地址不存在，请检查域名';
      } else {
        errorMsg = e.message ?? '未知错误';
      }
      setState(() {
        _modelError = errorMsg;
      });
    } catch (e) {
      setState(() {
        _modelError = '获取模型列表失败: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _loadingModels = false);
      }
    }
  }

  /// 测试API连接
  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionTestResult = null;
      _connectionTestSuccess = null;
    });

    try {
      final baseUrl = _baseUrlController.text.trim();
      final apiKey = _apiKeyController.text.trim();
      final model = _modelController.text.trim();

      final normalizedBase = _normalizeBaseUrl(baseUrl);
      final baseHasV1 = normalizedBase.toLowerCase().endsWith('/v1');
      final completionsUrl = baseHasV1
          ? '$normalizedBase/chat/completions'
          : '$normalizedBase/v1/chat/completions';

      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 15);
      dio.options.receiveTimeout = const Duration(seconds: 30);
      
      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      // 发送一个简单的测试请求
      final testBody = {
        'model': model.isNotEmpty ? model : 'gpt-3.5-turbo',
        'messages': [
          {'role': 'user', 'content': 'Hello'}
        ],
        'max_tokens': 5,
      };

      final resp = await dio.post(
        completionsUrl,
        data: testBody,
        options: Options(headers: headers),
      );

      if (resp.statusCode == 200) {
        setState(() {
          _connectionTestSuccess = true;
          _connectionTestResult = '连接成功！API 正常工作。';
        });
      } else {
        setState(() {
          _connectionTestSuccess = false;
          _connectionTestResult = '连接失败: HTTP ${resp.statusCode}';
        });
      }
    } on DioException catch (e) {
      String errorMsg;
      if (e.type == DioExceptionType.connectionTimeout) {
        errorMsg = '连接超时，请检查网络或域名';
      } else if (e.type == DioExceptionType.receiveTimeout) {
        errorMsg = '响应超时';
      } else if (e.response?.statusCode == 401) {
        errorMsg = 'API Key 无效或未授权';
      } else if (e.response?.statusCode == 403) {
        errorMsg = '访问被拒绝';
      } else if (e.response?.statusCode == 404) {
        errorMsg = '接口地址不存在，请检查域名';
      } else if (e.response?.statusCode == 429) {
        // 429 也说明API可以工作，只是被限流
        setState(() {
          _connectionTestSuccess = true;
          _connectionTestResult = '连接成功！（请求被限流，但API正常）';
        });
        return;
      } else {
        errorMsg = e.message ?? '未知错误';
      }
      setState(() {
        _connectionTestSuccess = false;
        _connectionTestResult = errorMsg;
      });
    } catch (e) {
      setState(() {
        _connectionTestSuccess = false;
        _connectionTestResult = '测试失败: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _testingConnection = false);
      }
    }
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    try {
      setState(() => _loading = true);
      final box = await Hive.openBox('settings');
      await box.put('openai_api', _apiKeyController.text.trim());
      await box.put('openai_base', _baseUrlController.text.trim());
      await box.put('openai_model', _modelController.text.trim());
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Theme.of(context).colorScheme.onPrimary),
              const SizedBox(width: 8),
              const Text('保存成功'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onError),
              const SizedBox(width: 8),
              const Text('保存失败'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 重置为默认值
  Future<void> _resetToDefault() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置设置'),
        content: const Text('确定要重置所有AI服务商设置为默认值吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _apiKeyController.clear();
        _baseUrlController.clear();
        _modelController.text = 'gpt-3.5-turbo';
        _models = [];
        _modelError = null;
        _connectionTestResult = null;
        _connectionTestSuccess = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('AI 服务商设置', style: textTheme.titleMedium),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重置为默认',
            onPressed: _resetToDefault,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 提示信息卡片
            Card(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '配置您的AI服务商API，支持OpenAI官方API或兼容的第三方服务。',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // API Key 设置卡片
            _buildSectionCard(
              title: 'API Key',
              icon: Icons.key,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '输入您的 OpenAI API Key',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      hintText: 'sk-...',
                      prefixIcon: const Icon(Icons.vpn_key_outlined),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscureApiKey
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () {
                              setState(() => _obscureApiKey = !_obscureApiKey);
                            },
                            tooltip: _obscureApiKey ? '显示' : '隐藏',
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _apiKeyController.text),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已复制到剪贴板'),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                            tooltip: '复制',
                          ),
                        ],
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // API Base URL 设置卡片
            _buildSectionCard(
              title: '自定义域名',
              icon: Icons.dns,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '留空使用 OpenAI 官方域名，或输入第三方服务地址',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseUrlController,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                      hintText: 'https://api.openai.com/v1',
                      prefixIcon: const Icon(Icons.link),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildQuickUrlChip('OpenAI官方', 'https://api.openai.com/v1'),
                      _buildQuickUrlChip('DeepSeek', 'https://api.deepseek.com'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 模型选择卡片
            _buildSectionCard(
              title: '模型选择',
              icon: Icons.psychology,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '选择要使用的AI模型',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _loadingModels ? null : _fetchModels,
                        icon: _loadingModels
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.primary,
                                ),
                              )
                            : const Icon(Icons.refresh, size: 18),
                        label: Text(_loadingModels ? '加载中' : '获取模型列表'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_modelError != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: colorScheme.error,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _modelError!,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (_models.isNotEmpty)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _models.contains(_modelController.text)
                          ? _modelController.text
                          : null,
                      items: _models
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(
                                  m,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _modelController.text = v);
                        }
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                      ),
                      hint: Text(
                        _modelController.text.isNotEmpty
                            ? _modelController.text
                            : '选择模型',
                      ),
                    )
                  else
                    TextField(
                      controller: _modelController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                        hintText: '手动输入模型名称，如 gpt-4',
                        prefixIcon: const Icon(Icons.edit),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildQuickModelChip('GPT-4o', 'gpt-4o'),
                      _buildQuickModelChip('GPT-4', 'gpt-4'),
                      _buildQuickModelChip('GPT-3.5', 'gpt-3.5-turbo'),
                      _buildQuickModelChip('DeepSeek', 'deepseek-chat'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 连接测试卡片
            _buildSectionCard(
              title: '连接测试',
              icon: Icons.network_check,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '测试当前配置是否能正常连接到AI服务',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _testingConnection ? null : _testConnection,
                          icon: _testingConnection
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onPrimary,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(_testingConnection ? '测试中...' : '测试连接'),
                        ),
                      ),
                    ],
                  ),
                  if (_connectionTestResult != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _connectionTestSuccess == true
                            ? Colors.green.withOpacity(0.1)
                            : colorScheme.errorContainer.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _connectionTestSuccess == true
                                ? Icons.check_circle
                                : Icons.error_outline,
                            color: _connectionTestSuccess == true
                                ? Colors.green
                                : colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _connectionTestResult!,
                              style: textTheme.bodyMedium?.copyWith(
                                color: _connectionTestSuccess == true
                                    ? Colors.green.shade700
                                    : colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _loading ? null : _saveSettings,
                    child: _loading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : const Text('保存设置'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 构建设置区域卡片
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  /// 快速填充URL的Chip
  Widget _buildQuickUrlChip(String label, String url) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _baseUrlController.text == url;

    return ActionChip(
      label: Text(label),
      avatar: isSelected
          ? Icon(Icons.check, size: 16, color: colorScheme.primary)
          : null,
      backgroundColor: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      side: BorderSide(
        color: isSelected ? colorScheme.primary : Colors.transparent,
      ),
      onPressed: () {
        setState(() {
          _baseUrlController.text = url;
        });
      },
    );
  }

  /// 快速填充模型的Chip
  Widget _buildQuickModelChip(String label, String model) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = _modelController.text == model;

    return ActionChip(
      label: Text(label),
      avatar: isSelected
          ? Icon(Icons.check, size: 16, color: colorScheme.primary)
          : null,
      backgroundColor: isSelected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest,
      side: BorderSide(
        color: isSelected ? colorScheme.primary : Colors.transparent,
      ),
      onPressed: () {
        setState(() {
          _modelController.text = model;
        });
      },
    );
  }
}
