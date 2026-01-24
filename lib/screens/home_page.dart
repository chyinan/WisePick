import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hive_flutter/hive_flutter.dart';
import '../core/theme/theme_provider.dart';
import '../features/cart/cart_page.dart';
import '../features/chat/chat_providers.dart';
import '../features/chat/conversation_model.dart';
import '../features/auth/auth_providers.dart';
import '../features/auth/login_page.dart';
import '../features/auth/profile_page.dart';
import '../features/auth/token_manager.dart';
import '../services/sync/sync_manager.dart';
import '../widgets/macos_window_buttons.dart';
import '../widgets/sync_status_indicator.dart';
import 'admin_settings_page.dart';
import 'ai_provider_settings_page.dart';
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

class _HomePageState extends ConsumerState<HomePage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  int _aboutTapCount = 0;
  bool _showConversationPanel = false;  // 控制桌面端消息列表面板显示

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 应用恢复时自动同步
      _syncOnResume();
    }
  }

  Future<void> _syncOnResume() async {
    try {
      final isLoggedIn = ref.read(isLoggedInProvider);
      if (isLoggedIn) {
        final syncManager = ref.read(syncManagerProvider.notifier);
        await syncManager.syncAll();
      }
    } catch (_) {
      // 忽略同步错误，不影响用户体验
    }
  }

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
        // 切换到非 AI 助手页面时，自动关闭消息列表面板
        if (idx != 0) {
          _showConversationPanel = false;
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

  /// 判断是否为桌面端
  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  Widget build(BuildContext context) {
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
            body: Column(
              children: [
                // macOS 风格自定义标题栏
                if (_isDesktopPlatform) const MacOSTitleBar(),
                Expanded(
                  child: Row(
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
                          child: Tooltip(
                            message: _currentIndex == 0
                                ? (_showConversationPanel ? '关闭对话列表' : '打开对话列表')
                                : '返回 AI 助手',
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (_currentIndex == 0) {
                                    // 在 AI 助手页面：切换消息列表面板
                                    _showConversationPanel = !_showConversationPanel;
                                  } else {
                                    // 在其他页面：跳转回 AI 助手并打开消息列表
                                    _currentIndex = 0;
                                    _showConversationPanel = true;
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(24),
                              child: CircleAvatar(
                                radius: 24,
                                backgroundColor: (_currentIndex == 0 && _showConversationPanel)
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : const Color(0xFF6750A4), // 消息列表按钮无论深色模式还是浅色模式都固定深紫色主题色
                                child: Icon(
                                  (_currentIndex == 0 && _showConversationPanel) 
                                      ? Icons.close 
                                      : Icons.shopping_bag_outlined,
                                  color: (_currentIndex == 0 && _showConversationPanel)
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                        destinations: [
                          const NavigationRailDestination(
                            icon: Icon(Icons.smart_toy_outlined),
                            selectedIcon: Icon(Icons.smart_toy),
                            label: Text('AI 助手'),
                          ),
                          const NavigationRailDestination(
                            icon: Icon(Icons.shopping_cart_outlined),
                            selectedIcon: Icon(Icons.shopping_cart),
                            label: Text('购物车'),
                          ),
                          const NavigationRailDestination(
                            icon: Icon(Icons.settings_outlined),
                            selectedIcon: Icon(Icons.settings),
                            label: Text('设置'),
                          ),
                        ],
                      ),
                      const VerticalDivider(thickness: 1, width: 1),
                      // 桌面端消息列表面板
                      if (_showConversationPanel && _currentIndex == 0)
                        _DesktopConversationPanel(
                          onClose: () => setState(() => _showConversationPanel = false),
                        ),
                      if (_showConversationPanel && _currentIndex == 0)
                        const VerticalDivider(thickness: 1, width: 1),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // 移动端：使用 BottomNavigationBar 底部导航
        return Scaffold(
          body: Column(
            children: [
              // macOS 风格自定义标题栏（移动端布局但在桌面平台运行时也显示）
              if (_isDesktopPlatform) const MacOSTitleBar(),
              Expanded(child: body),
            ],
          ),
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
              const NavigationDestination(
                icon: Icon(Icons.shopping_cart_outlined),
                selectedIcon: Icon(Icons.shopping_cart),
                label: '购物车',
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
      subtitle: const Text('当购物车中的商品降价时发送通知'),
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
    final authState = ref.watch(authStateProvider);
    final isLoggedIn = authState.isLoggedIn;
    final user = authState.user;

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
              // 账号部分
              const _SectionHeader(title: '账号'),
              Card(
                child: isLoggedIn && user != null
                    ? _buildLoggedInCard(context, user)
                    : _buildLoginCard(context),
              ),
              // 同步状态（仅登录后显示）
              if (isLoggedIn) ...[
                const SizedBox(height: 16),
                const SyncStatusIndicator(),
              ],
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
              const _SectionHeader(title: 'AI 服务设置'),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.smart_toy,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: const Text('AI 服务商配置'),
                  subtitle: const Text('配置 API Key、自定义域名、选择模型'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AiProviderSettingsPage(),
                      ),
                    );
                  },
                ),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/icon/app_logo.png',
                width: 80,
                height: 80,
                fit: BoxFit.cover,
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

  /// 已登录状态的账号卡片
  Widget _buildLoggedInCard(BuildContext context, user) {
    final theme = Theme.of(context);
    final tokenManager = TokenManager.instance;
    final sessionRemaining = tokenManager.sessionRemainingTime;
    
    // 格式化会话剩余时间
    String sessionInfo = user.email;
    if (sessionRemaining != null) {
      if (sessionRemaining.inDays > 0) {
        sessionInfo = '${user.email} · 登录有效期 ${sessionRemaining.inDays} 天';
      } else if (sessionRemaining.inHours > 0) {
        sessionInfo = '${user.email} · 登录有效期 ${sessionRemaining.inHours} 小时';
      } else {
        sessionInfo = '${user.email} · 登录即将过期';
      }
    }
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage:
            user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
        child: user.avatarUrl == null
            ? Text(
                user.displayName[0].toUpperCase(),
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              )
            : null,
      ),
      title: Text(user.displayName),
      subtitle: Text(sessionInfo),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      },
    );
  }

  /// 未登录状态的账号卡片
  Widget _buildLoginCard(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person_outline,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: const Text('登录 / 注册'),
      subtitle: const Text('登录后可同步购物车和聊天记录'),
      trailing: FilledButton(
        onPressed: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const LoginPage()),
          );
          // 登录成功后，页面会自动刷新（Riverpod 状态管理）
        },
        child: const Text('登录'),
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

/// 桌面端消息列表面板
class _DesktopConversationPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  
  const _DesktopConversationPanel({required this.onClose});

  @override
  ConsumerState<_DesktopConversationPanel> createState() => _DesktopConversationPanelState();
}

class _DesktopConversationPanelState extends ConsumerState<_DesktopConversationPanel> {
  List<ConversationModel> _conversations = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;

  List<ConversationModel> get _filteredConversations {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _conversations;
    return _conversations.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final repo = ref.read(conversationRepositoryProvider);
      final list = await repo.listConversations();
      if (mounted) {
        setState(() {
          _conversations = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _newConversation() async {
    final notifier = ref.read(chatStateNotifierProvider.notifier);
    await notifier.createNewConversation();
    await _loadConversations();
  }

  Future<void> _deleteConversation(ConversationModel c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定要删除「${c.title}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final notifier = ref.read(chatStateNotifierProvider.notifier);
      await notifier.deleteConversationById(c.id);
      await _loadConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentId = ref.watch(chatStateNotifierProvider).currentConversationId;
    
    return Container(
      width: 280,
      color: theme.colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('对话列表', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.add, size: 20, color: theme.colorScheme.primary),
                  tooltip: '新建对话',
                  onPressed: _newConversation,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          // 搜索框
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索对话...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.5)),
                ),
              ),
              style: theme.textTheme.bodyMedium,
              onChanged: (_) => setState(() {}),
            ),
          ),
          // 对话列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredConversations.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_outlined, size: 48, color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            Text('暂无对话', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _newConversation,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('新建对话'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _filteredConversations.length,
                        itemBuilder: (ctx, idx) {
                          final c = _filteredConversations[idx];
                          final isSelected = c.id == currentId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Material(
                              color: isSelected 
                                  ? theme.colorScheme.primaryContainer.withOpacity(0.5)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  final notifier = ref.read(chatStateNotifierProvider.notifier);
                                  notifier.loadConversation(c);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              c.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${c.messages.length} 条消息',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: theme.colorScheme.outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.outline),
                                        tooltip: '删除',
                                        onPressed: () => _deleteConversation(c),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}



