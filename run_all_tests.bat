@echo off
REM ============================================================
REM  WisePick 自动化测试运行脚本 (Windows)
REM  运行项目中所有单元测试和集成测试
REM ============================================================

echo ============================================================
echo   WisePick - 全量自动化测试
echo ============================================================
echo.

set FAIL=0

REM ---- 主项目测试 (Flutter/Dart) ----
echo [1/2] 运行主项目测试 (test\)...
echo ------------------------------------------------------------
call dart test test\ --reporter expanded
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [FAIL] 主项目测试失败!
    set FAIL=1
) else (
    echo.
    echo [PASS] 主项目测试全部通过.
)
echo.

REM ---- 服务端项目测试 (server\test\) ----
echo [2/2] 运行服务端项目测试 (server\test\)...
echo ------------------------------------------------------------
pushd server
call dart pub get
call dart test test\ --reporter expanded
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [FAIL] 服务端测试失败!
    set /A FAIL=1
) else (
    echo.
    echo [PASS] 服务端测试全部通过.
)
popd
echo.

REM ---- 汇总 ----
echo ============================================================
if %FAIL% EQU 0 (
    echo   ✅ 所有测试通过!
) else (
    echo   ❌ 部分测试失败，请检查上方日志.
)
echo ============================================================

exit /b %FAIL%
