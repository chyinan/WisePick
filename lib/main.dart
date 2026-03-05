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
import 'features/auth/auth_providers.dart';
import 'features/auth/token_manager.dart';
import 'features/auth/user_model.dart';
import 'services/notification_service.dart';
import 'services/price_refresh_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    dev.log(
      'FlutterError: ${details.exceptionAsString()}',
      name: 'main',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: '快淘帮 WisePick',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  await NotificationService.instance.init();
  await HiveConfig.init();
  Config.validate();
  BackendConfig.warnIfDefaultInProduction();
  await TokenManager.instance.init();

  // 在 runApp 前预先读取认证状态，用于初始化 ProviderScope
  final tokenManager = TokenManager.instance;
  AuthState initialAuthState = const AuthState();
  if (tokenManager.isLoggedIn) {
    final cachedUserData = await tokenManager.getCachedUserData();
    if (cachedUserData != null) {
      initialAuthState = AuthState(
        status: AuthStatus.authenticated,
        user: User.fromJson(cachedUserData),
        isLoading: false,
      );
      dev.log('从缓存恢复登录状态', name: 'main');
    }
  }

  runApp(ProviderScope(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => AuthStateNotifier(
          authService: ref.read(authServiceProvider),
          tokenManager: ref.read(tokenManagerProvider),
          initialState: initialAuthState,
        ),
      ),
    ],
    child: const WisePickApp(),
  ));

  runZonedGuarded(() {
    unawaited(PriceRefreshService().refreshCartPrices());
  }, (Object error, StackTrace stack) {
    dev.log('Unhandled async error', name: 'main', error: error, stackTrace: stack);
  });
}
