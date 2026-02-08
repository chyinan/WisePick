import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/backend_config.dart';
import 'core/config.dart';
import 'core/storage/hive_config.dart';
import 'features/auth/token_manager.dart';
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

  // Capture Flutter framework errors (widget build failures, etc.)
  // so they are logged rather than silently swallowed in release mode.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details); // default presentation (prints in debug)
    dev.log(
      'FlutterError: ${details.exceptionAsString()}',
      name: 'main',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // Wrap the entire startup in a guarded zone so that any unhandled
  // asynchronous errors (e.g. from unawaited futures) are logged
  // instead of crashing silently.
  runZonedGuarded(() async {
    // 桌面端窗口配置
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      await windowManager.ensureInitialized();

      const windowOptions = WindowOptions(
        size: Size(1200, 800),
        minimumSize: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle:
            TitleBarStyle.hidden, // 隐藏原生标题栏，使用自定义 macOS 风格
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

    // 检查配置项完整性（输出警告，不阻塞启动）
    Config.validate();

    // 检查后端地址是否仍为默认开发值（非 debug 模式下警告）
    BackendConfig.warnIfDefaultInProduction();

    // 初始化 Token 管理器（用户认证）
    await TokenManager.instance.init();

    // 运行应用
    runApp(const ProviderScope(child: WisePickApp()));

    // 启动后台价格刷新服务（不阻塞启动）
    unawaited(PriceRefreshService().refreshCartPrices());
  }, (Object error, StackTrace stack) {
    // Last-resort handler for async errors that escaped all try/catch blocks.
    dev.log(
      'Unhandled async error',
      name: 'main',
      error: error,
      stackTrace: stack,
    );
  });
}
