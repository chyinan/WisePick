import 'package:flutter/material.dart';
import 'api_client.dart';
import 'server_config_service.dart';

/// 服务器配置对话框
///
/// 提供预设环境快选、自定义地址输入、连接测试功能。
/// 返回 true 表示已切换服务器。
class ServerConfigDialog extends StatefulWidget {
  const ServerConfigDialog({super.key});

  /// 显示配置对话框，返回是否已切换服务器
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const ServerConfigDialog(),
    );
  }

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

enum _TestStatus { idle, testing, success, failed }

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  final _urlController = TextEditingController();
  int _selectedPresetIndex = -1;
  _TestStatus _testStatus = _TestStatus.idle;
  String? _testError;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUrl();
  }

  Future<void> _loadCurrentUrl() async {
    final url = await ServerConfigService.getSavedUrl();
    if (!mounted) return;
    _urlController.text = url;
    // 匹配预设
    final idx = ServerConfigService.presets.indexWhere((p) => p.url == url);
    setState(() => _selectedPresetIndex = idx);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _onPresetSelected(int index) {
    setState(() {
      _selectedPresetIndex = index;
      _urlController.text = ServerConfigService.presets[index].url;
      _testStatus = _TestStatus.idle;
      _testError = null;
    });
  }

  Future<void> _testConnection() async {
    final url = ServerConfigService.normalizeUrl(_urlController.text);
    setState(() {
      _testStatus = _TestStatus.testing;
      _testError = null;
    });

    final ok = await ServerConfigService.testConnection(url);
    if (!mounted) return;
    setState(() {
      _testStatus = ok ? _TestStatus.success : _TestStatus.failed;
      _testError = ok ? null : '无法连接到 $url/health';
    });
  }

  Future<void> _save() async {
    final url = ServerConfigService.normalizeUrl(_urlController.text);
    setState(() => _isSaving = true);

    try {
      await ServerConfigService.saveUrl(url);
      ApiClient.reconfigure(url);
      // 清除旧 token
      await sharedSecureStorage.delete(key: 'auth_token');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                Icon(Icons.dns_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('服务器配置',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 24),

            // 预设环境
            Text('预设环境', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(
                ServerConfigService.presets.length,
                (i) => ChoiceChip(
                  label: Text(ServerConfigService.presets[i].name),
                  selected: _selectedPresetIndex == i,
                  onSelected: (_) => _onPresetSelected(i),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 自定义地址
            Text('服务器地址', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'http://localhost:9527',
                prefixIcon: Icon(Icons.link),
              ),
              onChanged: (_) {
                if (_selectedPresetIndex != -1) {
                  setState(() => _selectedPresetIndex = -1);
                }
                if (_testStatus != _TestStatus.idle) {
                  setState(() {
                    _testStatus = _TestStatus.idle;
                    _testError = null;
                  });
                }
              },
            ),
            const SizedBox(height: 16),

            // 连接测试
            _buildTestRow(theme),
            const SizedBox(height: 24),

            // 操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestRow(ThemeData theme) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _testStatus == _TestStatus.testing ? null : _testConnection,
          icon: const Icon(Icons.wifi_tethering, size: 18),
          label: const Text('测试连接'),
        ),
        const SizedBox(width: 12),
        if (_testStatus == _TestStatus.testing)
          const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        if (_testStatus == _TestStatus.success)
          Row(children: [
            Icon(Icons.check_circle, color: Colors.green[600], size: 20),
            const SizedBox(width: 4),
            Text('连接成功', style: TextStyle(color: Colors.green[600], fontSize: 13)),
          ]),
        if (_testStatus == _TestStatus.failed)
          Flexible(
            child: Row(children: [
              Icon(Icons.error_outline, color: Colors.red[600], size: 20),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  _testError ?? '连接失败',
                  style: TextStyle(color: Colors.red[600], fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
      ],
    );
  }
}
