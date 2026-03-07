@echo off
chcp 65001 >nul 2>&1
title WisePick Admin - 快速修复启动

echo.
echo  ========================================
echo   WisePick Admin 快速修复启动工具
echo  ========================================
echo.

echo  [1/4] 清理构建缓存...
call flutter clean >nul 2>&1
echo        完成

echo  [2/4] 重建 Web SDK 缓存...
call flutter precache --web >nul 2>&1
echo        完成

echo  [3/4] 获取依赖...
call flutter pub get >nul 2>&1
echo        完成

echo  [4/4] 启动 Chrome 调试...
echo.
echo  ----------------------------------------
echo   如果启动成功会自动打开浏览器
echo   按 Ctrl+C 停止运行
echo  ----------------------------------------
echo.
call flutter run -d chrome

pause
