import 'package:dio/dio.dart';
import 'api_client.dart';

/// 预设服务器环境
class ServerPreset {
  final String name;
  final String url;

  const ServerPreset({required this.name, required this.url});
}

/// 服务器配置服务
///
/// 负责读写后端服务器地址配置，支持连接测试和地址标准化。
/// 使用 [sharedSecureStorage] 持久化存储。
class ServerConfigService {
  static const String _storageKey = 'server_url';
  static const String defaultUrl = 'http://localhost:9527';

  /// 预设环境列表
  static const List<ServerPreset> presets = [
    ServerPreset(name: '本地开发', url: 'http://localhost:9527'),
    ServerPreset(name: '局域网', url: 'http://192.168.1.x:9527'),
  ];

  /// 读取已保存的服务器地址，无则返回默认值
  static Future<String> getSavedUrl() async {
    try {
      final url = await sharedSecureStorage.read(key: _storageKey);
      return (url != null && url.isNotEmpty) ? url : defaultUrl;
    } catch (_) {
      return defaultUrl;
    }
  }

  /// 保存服务器地址
  static Future<void> saveUrl(String url) async {
    await sharedSecureStorage.write(key: _storageKey, value: url);
  }

  /// 测试连接，GET {url}/api/v1/reliability/health，超时 5s
  static Future<bool> testConnection(String url) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final response = await dio.get('$url/api/v1/reliability/health');
      return response.statusCode != null && response.statusCode! < 400;
    } catch (_) {
      return false;
    }
  }

  /// 标准化 URL 输入（补 http://、去尾部斜杠）
  static String normalizeUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return defaultUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }
}
