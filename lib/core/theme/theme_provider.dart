import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 主题状态管理
/// 
/// 支持 light/dark/system 三种模式
/// 状态持久化到 Hive
class ThemeNotifier extends StateNotifier<ThemeMode> {
  static const String _boxName = 'settings';
  static const String _key = 'theme_mode';

  ThemeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  /// 从本地存储加载主题设置
  Future<void> _loadTheme() async {
    try {
      final box = await Hive.openBox(_boxName);
      final savedMode = box.get(_key) as String?;
      if (savedMode != null) {
        state = ThemeMode.values.firstWhere(
          (e) => e.name == savedMode,
          orElse: () => ThemeMode.system,
        );
      }
    } catch (e) {
      // 如果加载失败，保持默认值
      debugPrint('加载主题设置失败: $e');
    }
  }

  /// 设置主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final box = await Hive.openBox(_boxName);
      await box.put(_key, mode.name);
    } catch (e) {
      debugPrint('保存主题设置失败: $e');
    }
  }

  /// 切换深色模式
  void toggleDarkMode() {
    if (state == ThemeMode.dark) {
      setThemeMode(ThemeMode.light);
    } else {
      setThemeMode(ThemeMode.dark);
    }
  }
}

/// 主题状态 Provider
final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});

/// 判断当前是否为深色模式
final isDarkModeProvider = Provider<bool>((ref) {
  final themeMode = ref.watch(themeProvider);
  // 注意：这个 Provider 需要 BuildContext 来获取系统主题，
  // 实际使用时应该在 Widget 中判断
  return themeMode == ThemeMode.dark;
});
