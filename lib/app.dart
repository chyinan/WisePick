import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/decision/product_comparison_page.dart';
import 'features/home/home_page.dart';

/// WisePickApp 根组件
/// 配置 MaterialApp、主题管理和路由
class WisePickApp extends ConsumerStatefulWidget {
  const WisePickApp({super.key});

  @override
  ConsumerState<WisePickApp> createState() => _WisePickAppState();
}

class _WisePickAppState extends ConsumerState<WisePickApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: '快淘帮 WisePick',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const HomePage(),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/comparison':
            return MaterialPageRoute(
              builder: (_) => const ProductComparisonPage(),
            );
          default:
            return null;
        }
      },
    );
  }
}























