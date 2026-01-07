import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/storage/hive_config.dart';
import 'services/notification_service.dart';
import 'services/price_refresh_service.dart';

/// 应用入口
/// 
/// 初始化顺序：
/// 1. WidgetsFlutterBinding.ensureInitialized()
/// 2. 桌面端窗口配置（window_manager）
/// 3. NotificationService 初始化
/// 4. Hive 初始化并注册适配器（通过 HiveConfig）
/// 5. 运行应用（ProviderScope）
/// 6. 启动 PriceRefreshService（后台）
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端窗口配置
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
      title: '快淘帮 WisePick',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // 初始化通知服务
  await NotificationService.instance.init();

  // 初始化 Hive 本地存储（包括注册 Adapter 和打开 Box）
  await HiveConfig.init();

  // 运行应用
  runApp(const ProviderScope(child: WisePickApp()));

  // 启动后台价格刷新服务（不阻塞启动）
  unawaited(PriceRefreshService().refreshCartPrices());
}
