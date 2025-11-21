import 'dart:developer';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:windows_notification/notification_message.dart';
import 'package:windows_notification/windows_notification.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final String? _windowsAppId =
      Platform.environment['WINDOWS_NOTIFICATION_APP_ID'];
  WindowsNotification? _windowsNotification;
  bool _initialized = false;
  int _notificationId = 0;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings();
    final linuxSettings = LinuxInitializationSettings(
      defaultActionName: '打开应用',
    );

    final initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await _plugin.initialize(initializationSettings);

    if (Platform.isWindows && (_windowsAppId?.isNotEmpty ?? false)) {
      _windowsNotification = WindowsNotification(applicationId: _windowsAppId);
      try {
        await _windowsNotification!.init();
      } catch (e, st) {
        log('初始化 Windows 通知失败: $e', stackTrace: st);
        _windowsNotification = null;
      }
    } else if (Platform.isWindows) {
      log(
        '未设置 WINDOWS_NOTIFICATION_APP_ID，已禁用 Windows 系统通知。',
        name: 'NotificationService',
      );
    }

    _initialized = true;
  }

  Future<void> showPriceDropNotification({
    required String title,
    required double dropAmount,
    double? latestPrice,
  }) async {
    await init();
    final dropText = dropAmount.toStringAsFixed(2);
    final priceText =
        latestPrice != null ? '最新价格：¥${latestPrice.toStringAsFixed(2)}' : '';
    final body = '“$title”商品比您加入购物车时降价了¥$dropText！$priceText';

    if (Platform.isWindows) {
      if (_windowsNotification != null) {
        try {
          final message = NotificationMessage.fromPluginTemplate(
            'price_drop_${DateTime.now().millisecondsSinceEpoch}',
            '降价提醒',
            body,
          );
          await _windowsNotification!.showNotificationPluginTemplate(message);
        } catch (e, st) {
          log('发送 Windows 通知失败: $e', stackTrace: st);
        }
      } else {
        log(
          'Windows 通知未启用（缺少有效的 APP ID），已跳过系统通知。',
          name: 'NotificationService',
        );
      }
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'price_drop_channel',
      '降价提醒',
      channelDescription: '购物车商品降价提醒',
      importance: Importance.max,
      priority: Priority.high,
    );
    const darwinDetails = DarwinNotificationDetails();
    final linuxDetails = LinuxNotificationDetails();
    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      linux: linuxDetails,
    );

    await _plugin.show(
      _notificationId++,
      '降价提醒',
      body,
      notificationDetails,
    );
  }
}


