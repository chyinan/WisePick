import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:wisepick_dart_version/screens/chat_page.dart';
import 'package:wisepick_dart_version/screens/admin_settings_page.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/cart/cart_page.dart';

// 1. 创建一个 Provider 来管理和提供当前的主题种子颜色
final seedColorProvider = StateProvider<Color>(
  (ref) => const Color(0xFFFF7043),
);

const String _defaultBackendBase = String.fromEnvironment(
  'BACKEND_BASE',
  defaultValue: 'http://localhost:8080',
);
const String _adminAuthPath = '/admin/login';

Future<void> main() async {
  // 初始化 Flutter 绑定
  WidgetsFlutterBinding.ensureInitialized();

  // 仅在桌面平台初始化 window_manager，避免在 Android/iOS 上阻塞或抛错
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
  }

  // 初始化 Hive，用于本地存储（收藏、历史）
  await Hive.initFlutter();

  // 注册 Hive TypeAdapter（手写或生成的 adapter）
  Hive.registerAdapter(ProductModelAdapter());

  // 使用 Riverpod 的 ProviderScope 包裹整个应用
  runApp(const ProviderScope(child: WisePickApp()));

  // 仅在桌面平台设置窗口标题
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.setTitle('快淘帮');
  }
}

/// 应用根组件：快淘帮（WisePick）MVP
/// 使用简洁的 Material 主题，首页为聊天页面（ChatPage）
class WisePickApp extends ConsumerWidget {
  const WisePickApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 2. 监听 Provider 的状态，当颜色变化时，MaterialApp 会使用新颜色重建
    final seedColor = ref.watch(seedColorProvider);
    final ColorScheme colorScheme = ColorScheme.fromSeed(seedColor: seedColor);

    return MaterialApp(
      title: '快淘帮',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        // 使用 Noto Sans SC 本地字体（在 pubspec.yaml 中以 assets 声明）并提升标题/按钮权重以增强力度
        fontFamily: 'NotoSansSC',
        textTheme: ThemeData.light().textTheme
            .apply(fontFamily: 'NotoSansSC')
            .copyWith(
              headlineLarge: ThemeData.light().textTheme.headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
              headlineMedium: ThemeData.light().textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              titleLarge: ThemeData.light().textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              bodyMedium: ThemeData.light().textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              labelLarge: ThemeData.light().textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
        // 应用级的简单 M3 组件样式覆盖，使用 colorScheme 代替硬编码颜色
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primaryContainer,
          foregroundColor: colorScheme.onPrimaryContainer,
          centerTitle: true,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: colorScheme.surface,
          selectedItemColor: colorScheme.primary,
          unselectedItemColor: colorScheme.onSurfaceVariant,
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// 带底部导航的主页（聊天 + 收藏）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  int _aboutTapCount = 0; // 用于触发隐藏管理入口

  // 使用 _pages 字段已不再需要（我们按 currentIndex 动态渲染），保留注释以便未来扩展
  // static const List<Widget> _pages = <Widget>[ChatPage(), CartPage()];

  Future<String> _resolveBackendBase() async {
    try {
      final box = await Hive.openBox('settings');
      final stored = box.get('backend_base') as String?;
      if (stored != null && stored.trim().isNotEmpty) {
        return stored.trim();
      }
    } catch (_) {}
    return _defaultBackendBase;
  }

  Future<bool> _verifyAdminPassword(String password) async {
    final trimmed = password.trim();
    if (trimmed.isEmpty) {
      throw Exception('密码不能为空');
    }
    final base = await _resolveBackendBase();
    final sanitizedBase = base.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$sanitizedBase$_adminAuthPath');
    http.Response resp;
    try {
      resp = await http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'password': trimmed}),
      );
    } catch (e) {
      throw Exception('无法连接后台：$e');
    }

    Map<String, dynamic>? body;
    if (resp.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {}
    }

    if (resp.statusCode != 200) {
      final message =
          body?['message']?.toString() ??
          body?['error']?.toString() ??
          '服务器返回错误(${resp.statusCode})';
      throw Exception(message);
    }

    final success = body?['success'] == true;
    if (!success) {
      final message = body?['message']?.toString() ?? '密码错误';
      throw Exception(message);
    }

    return true;
  }

  void _onTap(int idx) => setState(() {
    // 如果切换到非「关于」页，重置关于按钮连续计数，确保必须连续按 7 次关于才能触发
    if (idx != 2) {
      _aboutTapCount = 0;
    }
    _currentIndex = idx;
  });

  void _onAboutTapped(BuildContext context) async {
    // 记录连续按下「关于」的次数；如果中途切换到其他 tab，会在 _onTap 中重置
    _aboutTapCount++;

    // 只有在连续按 7 次时触发弹窗
    if (_aboutTapCount >= 7) {
      _aboutTapCount = 0;
      final TextEditingController pwController = TextEditingController();
      final bool unlocked =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                '输入管理员密码以进入后台管理',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              content: TextField(
                controller: pwController,
                obscureText: true,
                decoration: InputDecoration(hintText: '管理员密码'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    '取消',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(
                    '确定',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          ) ??
          false;
      final passwordInput = pwController.text.trim();
      pwController.dispose();

      if (unlocked) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        final loading = messenger.showSnackBar(
          SnackBar(
            content: const Text('正在验证管理员密码...'),
            duration: const Duration(seconds: 30),
          ),
        );
        try {
          await _verifyAdminPassword(passwordInput);
          loading.close();
          if (!mounted) return;
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AdminSettingsPage()));
        } catch (e) {
          loading.close();
          if (!mounted) return;
          final msg = e.toString().replaceFirst('Exception: ', '').trim();
          final normalizedMsg = msg.isEmpty ? '验证失败' : msg;
          final isNetworkIssue = normalizedMsg.startsWith('无法连接后台');
          final isConfigMissing = normalizedMsg.toUpperCase().contains(
            'ADMIN_PASSWORD',
          );
          messenger.showSnackBar(
            SnackBar(
              content: Text(normalizedMsg),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          if (isNetworkIssue || isConfigMissing) {
            final proceedOffline =
                await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(
                      '无法连接后端',
                      style: Theme.of(ctx).textTheme.titleMedium,
                    ),
                    content: const Text('当前后端不可用。是否跳过验证并进入设置以修改后端地址？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('继续'),
                      ),
                    ],
                  ),
                ) ??
                false;
            if (proceedOffline && mounted) {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminSettingsPage()),
              );
            }
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_currentIndex == 0) {
      body = const ChatPage();
    } else if (_currentIndex == 1) {
      body = const CartPage();
    } else {
      body = const AboutPage();
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (idx) {
          if (idx == 2) {
            _onAboutTapped(context);
          }
          _onTap(idx);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: '聊天'),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: '购物车',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.info_outline), label: '关于'),
        ],
      ),
    );
  }
}

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  Future<void> _openExternalUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '无法打开链接',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const String appName = '快淘帮 — WisePick';
    const String version = '0.0.1';

    return Scaffold(
      appBar: AppBar(
        title: Text('关于', style: Theme.of(context).textTheme.titleMedium),
      ),
      body: ListView(
        children: [
          const _SectionHeader(title: '基本信息'),
          const ListTile(
            leading: Icon(Icons.apps_outlined),
            title: Text('应用名称'),
            subtitle: Text(appName),
          ),
          ListTile(
            leading: const Icon(Icons.verified_outlined),
            title: const Text('版本'),
            subtitle: Text(
              version,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),

          const _SectionHeader(title: '开发者'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('作者'),
            subtitle: Text(
              'chyinan',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.link_outlined),
            title: const Text('开发者主页'),
            subtitle: const Text('https://github.com/chyinan'),
            onTap: () =>
                _openExternalUrl(context, 'https://github.com/chyinan'),
          ),

          // 3. 在“关于”页添加主题选择 UI
          const _SectionHeader(title: '个性化'),
          const _ThemeColorSelector(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// 后台设置页面已拆分到 `lib/screens/admin_settings_page.dart`

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 主题颜色选择器组件
class _ThemeColorSelector extends ConsumerWidget {
  const _ThemeColorSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 定义可选的颜色列表
    final List<Color> themeColors = [
      const Color(0xFFFF7043), // 默认橙色
      Colors.blue,
      Colors.teal,
      Colors.purple,
      Colors.pink, // 浅红色/粉红色
    ];

    final currentSeedColor = ref.watch(seedColorProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 8.0,
        children: themeColors.map((color) {
          final isSelected = currentSeedColor.value == color.value;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              // 点击后更新 Provider 中的颜色值
              ref.read(seedColorProvider.notifier).state = color;
            },
            child: CircleAvatar(
              radius: 20,
              backgroundColor: color,
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white)
                  : null,
            ),
          );
        }).toList(),
      ),
    );
  }
}
