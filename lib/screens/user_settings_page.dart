import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';

class UserSettingsPage extends StatefulWidget {
  const UserSettingsPage({super.key});

  @override
  State<UserSettingsPage> createState() => _UserSettingsPageState();
}

class _UserSettingsPageState extends State<UserSettingsPage> {
  final TextEditingController _openAiController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  bool _loading = false;
  List<String> _models = [];
  bool _loadingModels = false;
  String? _modelError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox('settings');
      setState(() {
        _openAiController.text = (box.get('openai_api') as String?) ?? '';
        _baseUrlController.text = (box.get('openai_base') as String?) ?? '';
        _modelController.text = (box.get('openai_model') as String?) ?? '';
      });
      // 每次打开时尝试拉取可用模型列表
      _fetchModels();
    } catch (_) {}
  }

  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _modelError = null;
      _models = [];
    });
    try {
      final baseRaw = _baseUrlController.text.trim();
      String base = baseRaw.isNotEmpty ? baseRaw : 'https://api.openai.com';
      final key = _openAiController.text.trim();
      final dio = Dio();
      final headers = <String, dynamic>{'Content-Type': 'application/json'};
      if (key.isNotEmpty) headers['Authorization'] = 'Bearer $key';

      String normalizedBase = base.trim();
      if (normalizedBase.isEmpty) {
        normalizedBase = 'https://api.openai.com';
      }
      if (!normalizedBase.startsWith('http://') &&
          !normalizedBase.startsWith('https://')) {
        normalizedBase = 'https://$normalizedBase';
      }
      normalizedBase = normalizedBase.replaceAll(RegExp(r'/+$'), '');
      final lower = normalizedBase.toLowerCase();
      const completionsSuffix = '/chat/completions';
      if (lower.endsWith(completionsSuffix)) {
        normalizedBase = normalizedBase.substring(
          0,
          normalizedBase.length - completionsSuffix.length,
        );
      }
      final baseHasV1 = normalizedBase.toLowerCase().endsWith('/v1');
      final modelsUrl = baseHasV1
          ? '$normalizedBase/models'
          : '$normalizedBase/v1/models';

      final resp = await dio.get(modelsUrl, options: Options(headers: headers));
      if (resp.statusCode == 200) {
        final data = resp.data as Map<String, dynamic>;
        final list = data['data'] as List<dynamic>?;
        if (list != null) {
          _models = list
              .map((e) => (e as Map<String, dynamic>)['id'] as String)
              .toList();
        }
      } else {
        _modelError = 'HTTP ${resp.statusCode}';
        if (mounted) {
          // Show a transient snackbar instead of exposing the full error inline
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('获取模型列表失败'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      _modelError = e.toString();
      if (mounted) {
        // Show a transient snackbar instead of exposing the full error inline
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('获取模型列表失败'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
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
        title: Text('AI模型设置', style: Theme.of(context).textTheme.titleMedium),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              surfaceTintColor: colorScheme.surfaceTint,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OpenAI API Key',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _openAiController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme.surfaceVariant,
                        hintText: 'sk-...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'API Base URL (可选，留空使用默认)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _baseUrlController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: colorScheme.surfaceVariant,
                        hintText: 'https://api.openai.com/v1',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Model (例如 gpt-3.5-turbo 或 gpt-4)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loadingModels)
                      Row(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(width: 12),
                          const Text('正在加载可用模型...'),
                        ],
                      )
                    else if (_modelError != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '获取模型列表失败: $_modelError',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _modelController,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: colorScheme.surfaceVariant,
                              hintText: '手动输入模型，例如 gpt-3.5-turbo',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _models.contains(_modelController.text)
                            ? _modelController.text
                            : null,
                        items: _models
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            _modelController.text = v;
                          });
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: colorScheme.surfaceVariant,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                        ),
                        hint: Text(
                          _modelController.text.isNotEmpty
                              ? _modelController.text
                              : '选择模型或稍等自动加载',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton(
                  onPressed: () async {
                    try {
                      setState(() => _loading = true);
                      final box = await Hive.openBox('settings');
                      await box.put(
                        'openai_api',
                        _openAiController.text.trim(),
                      );
                      await box.put(
                        'openai_base',
                        _baseUrlController.text.trim(),
                      );
                      await box.put(
                        'openai_model',
                        _modelController.text.trim(),
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('保存成功')));
                      Navigator.of(context).pop();
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('保存失败')));
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          '保存',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: colorScheme.onPrimary),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
