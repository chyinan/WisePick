import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:wisepick_dart_version/core/theme/app_theme.dart';
import 'package:wisepick_dart_version/screens/chat_page.dart';
import 'package:wisepick_dart_version/screens/admin_settings_page.dart';
import 'package:wisepick_dart_version/features/products/product_model.dart';
import 'package:wisepick_dart_version/features/cart/cart_page.dart';
import 'package:wisepick_dart_version/services/notification_service.dart';
import 'package:wisepick_dart_version/services/price_refresh_service.dart';

const String _defaultAdminPasswordHash =
    'b054968e7426730e9a005f1430e6d5cd70a03b08370a82323f9a9b231cf270be';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await NotificationService.instance.init();
  await Hive.initFlutter();
  Hive.registerAdapter(ProductModelAdapter());

  runApp(const ProviderScope(child: WisePickApp()));

  unawaited(PriceRefreshService().refreshCartPrices());

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.setTitle('快淘帮 WisePick');
  }
}

class WisePickApp extends StatelessWidget {
  const WisePickApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '快淘帮',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

  void _onAboutTapped(BuildContext context) async {
    _aboutTapCount++;
    if (_aboutTapCount >= 7) {
      _aboutTapCount = 0;
      final TextEditingController pwController = TextEditingController();
      final bool unlocked =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('管理员验证'),
              content: TextField(
                controller: pwController,
                obscureText: true,
                decoration: const InputDecoration(hintText: '请输入管理员密码', prefixIcon: Icon(Icons.lock_outline)),
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
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AdminSettingsPage()));
        } catch (e) {
          if (!mounted) return;
          final msg = e.toString().replaceFirst('Exception: ', '').trim();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
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

    // Responsive Layout: Use NavigationRail for Desktop/Wide screens
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth > 800;

        if (isDesktop) {
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
                      child: const Icon(Icons.shopping_bag_outlined, color: Colors.white),
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.chat_bubble_outline),
                      selectedIcon: Icon(Icons.chat_bubble),
                      label: Text('AI 助手'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.shopping_cart_outlined),
                      selectedIcon: Icon(Icons.shopping_cart),
                      label: Text('选品车'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.info_outline),
                      selectedIcon: Icon(Icons.info),
                      label: Text('关于'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          body: body,
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (idx) {
              if (idx == 2) _onAboutTapped(context);
              _onTap(idx);
            },
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), activeIcon: Icon(Icons.chat_bubble), label: 'AI 助手'),
              BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), activeIcon: Icon(Icons.shopping_cart), label: '选品车'),
              BottomNavigationBarItem(icon: Icon(Icons.info_outline), activeIcon: Icon(Icons.info), label: '关于'),
            ],
          ),
        );
      },
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

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
  Widget build(BuildContext context) {
    const String appName = '快淘帮';
    const String version = '1.0.0';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('关于应用'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _buildInfoCard(context, appName, version),
              const SizedBox(height: 24),
              const _SectionHeader(title: '开发者信息'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: const Text('作者'),
                      trailing: const Text('chyinan'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.code),
                      title: const Text('GitHub'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openExternalUrl(context, 'https://github.com/chyinan'),
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
               child: Icon(Icons.shopping_bag, size: 40, color: Theme.of(context).colorScheme.primary),
             ),
             const SizedBox(height: 16),
             Text(name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
             const SizedBox(height: 8),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
               decoration: BoxDecoration(
                 color: Theme.of(context).colorScheme.surfaceContainerHighest,
                 borderRadius: BorderRadius.circular(12),
               ),
               child: Text('v$version', style: Theme.of(context).textTheme.labelMedium),
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
          color: Theme.of(context).colorScheme.secondary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
