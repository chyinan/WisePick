import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hive_flutter/hive_flutter.dart';
import '../core/theme/theme_provider.dart';
import '../features/cart/cart_page.dart';
import '../features/cart/cart_providers.dart';
import 'admin_settings_page.dart';
import 'chat_page.dart';
import '../core/storage/hive_config.dart';

const String _defaultAdminPasswordHash =
    'b054968e7426730e9a005f1430e6d5cd70a03b08370a82323f9a9b231cf270be';

/// 应用主页 - 包含响应式导航框架
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;
  int _aboutTapCount = 0;

  Future<bool> _verifyAdminPassword(String password) async {
    final trimmed = password.trim();
    if (trimmed.isEmpty) {
      throw Exception('密码不能为空');
    }
    final inputHash = sha256.convert(utf8.encode(trimmed)).toString();
    if (inputHash == _defaultAdminPasswordHash) {
      return true;
    }
    throw Exception('密码错误');
  }

  void _onTap(int idx) => setState(() {
        if (idx != 2) {
          _aboutTapCount = 0;
        }
        _currentIndex = idx;
      });

  Future<bool> _getPriceNotificationEnabled() async {
    final box = await Hive.openBox(HiveConfig.settingsBox);
    return box.get(HiveConfig.priceNotificationEnabledKey, defaultValue: true) as bool;
  }

  Future<void> _setPriceNotificationEnabled(bool enabled) async {
    final box = await Hive.openBox(HiveConfig.settingsBox);
    await box.put(HiveConfig.priceNotificationEnabledKey, enabled);
  }

  void _onAboutTapped(BuildContext context) async {
    _aboutTapCount++;
    if (_aboutTapCount >= 7) {
      _aboutTapCount = 0;
      final TextEditingController pwController = TextEditingController();
      final bool unlocked = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('管理员验证'),
              content: TextField(
                controller: pwController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: '请输入管理员密码',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('确定'),
                ),
              ],
            ),
          ) ??
          false;

      if (unlocked) {
        if (!mounted) return;
        _handleAdminUnlock(pwController.text);
      }
      pwController.dispose();
    }
  }

  Future<void> _handleAdminUnlock(String password) async {
    try {
      await _verifyAdminPassword(password);
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AdminSettingsPage()));
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听选品车数量用于显示徽章
    final cartCount = ref.watch(cartCountProvider);

    final Widget body;
    if (_currentIndex == 0) {
      body = const ChatPage();
    } else if (_currentIndex == 1) {
      body = const CartPage();
    } else {
      body = const _SettingsPage();
    }

    // 响应式布局：使用 LayoutBuilder 检测屏幕宽度
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth > 800;

        if (isDesktop) {
          // 桌面端：使用 NavigationRail 左侧导航
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (idx) {
                    if (idx == 2) _onAboutTapped(context);
                    _onTap(idx);
                  },
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0, top: 12.0),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: const Icon(Icons.shopping_bag_outlined,
                          color: Colors.white),
                    ),
                  ),
                  destinations: [
                    const NavigationRailDestination(
                      icon: Icon(Icons.smart_toy_outlined),
                      selectedIcon: Icon(Icons.smart_toy),
                      label: Text('AI 助手'),
                    ),
                    NavigationRailDestination(
                      icon: Badge(
                        isLabelVisible: cartCount > 0,
                        label: Text('$cartCount'),
                        child: const Icon(Icons.shopping_cart_outlined),
                      ),
                      selectedIcon: Badge(
                        isLabelVisible: cartCount > 0,
                        label: Text('$cartCount'),
                        child: const Icon(Icons.shopping_cart),
                      ),
                      label: const Text('选品车'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('设置'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        // 移动端：使用 BottomNavigationBar 底部导航
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (idx) {
              if (idx == 2) _onAboutTapped(context);
              _onTap(idx);
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.smart_toy_outlined),
                selectedIcon: Icon(Icons.smart_toy),
                label: 'AI 助手',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: cartCount > 0,
                  label: Text('$cartCount'),
                  child: const Icon(Icons.shopping_cart_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: cartCount > 0,
                  label: Text('$cartCount'),
                  child: const Icon(Icons.shopping_cart),
                ),
                label: '选品车',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 价格变化通知开关组件
class _PriceNotificationSwitch extends ConsumerStatefulWidget {
  const _PriceNotificationSwitch();

  @override
  ConsumerState<_PriceNotificationSwitch> createState() => _PriceNotificationSwitchState();
}

class _PriceNotificationSwitchState extends ConsumerState<_PriceNotificationSwitch> {
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final box = await Hive.openBox(HiveConfig.settingsBox);
    setState(() {
      _enabled = box.get(HiveConfig.priceNotificationEnabledKey, defaultValue: true) as bool;
      _loading = false;
    });
  }

  Future<void> _updateSetting(bool value) async {
    final box = await Hive.openBox(HiveConfig.settingsBox);
    await box.put(HiveConfig.priceNotificationEnabledKey, value);
    setState(() {
      _enabled = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ListTile(
        title: Text('价格变化通知'),
        trailing: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return SwitchListTile(
      title: const Text('价格变化通知'),
      subtitle: const Text('当选品车中的商品降价时发送通知'),
      value: _enabled,
      onChanged: _updateSetting,
    );
  }
}

/// 设置页面 - 包含外观设置、关于信息
class _SettingsPage extends ConsumerWidget {
  const _SettingsPage();

  Future<void> _openExternalUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const String appName = '快淘帮';
    const String version = '1.0.0';
    final currentMode = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildInfoCard(context, appName, version),
              const SizedBox(height: 24),
              const _SectionHeader(title: '外观设置'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('深色模式'),
                      subtitle: Text(
                        currentMode == ThemeMode.system
                            ? '跟随系统'
                            : (currentMode == ThemeMode.dark ? '已开启' : '已关闭'),
                      ),
                      value: currentMode == ThemeMode.dark,
                      onChanged: (val) {
                        ref.read(themeProvider.notifier).setThemeMode(
                              val ? ThemeMode.dark : ThemeMode.light,
                            );
                      },
                    ),
                    const Divider(height: 1, indent: 16),
                    ListTile(
                      title: const Text('跟随系统设置'),
                      leading: const Icon(Icons.brightness_auto),
                      trailing: currentMode == ThemeMode.system
                          ? Icon(Icons.check,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        ref
                            .read(themeProvider.notifier)
                            .setThemeMode(ThemeMode.system);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionHeader(title: '通知设置'),
              Card(
                child: _PriceNotificationSwitch(),
              ),
              const SizedBox(height: 24),
              const _SectionHeader(title: '开发者信息'),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.person_outline),
                      title: Text('作者'),
                      trailing: Text('chyinan'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: const Text('GitHub'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          _openExternalUrl(context, 'https://github.com/chyinan'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionHeader(title: '关于'),
              Card(
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('版本'),
                      trailing: Text('v$version'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('开源许可'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        showLicensePage(
                          context: context,
                          applicationName: appName,
                          applicationVersion: version,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String name, String version) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.shopping_bag,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'v$version',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}



