#!/bin/bash
# ============================================================
#  WisePick 自动化测试运行脚本 (Linux/macOS)
#  运行项目中所有单元测试和集成测试
# ============================================================

set -e

echo "============================================================"
echo "  WisePick - 全量自动化测试"
echo "============================================================"
echo ""

FAIL=0

# ---- 主项目测试 (Flutter/Dart) ----
echo "[1/2] 运行主项目测试 (test/)..."
echo "------------------------------------------------------------"
if dart test test/ --reporter expanded; then
    echo ""
    echo "[PASS] 主项目测试全部通过."
else
    echo ""
    echo "[FAIL] 主项目测试失败!"
    FAIL=1
fi
echo ""

# ---- 服务端项目测试 (server/test/) ----
echo "[2/2] 运行服务端项目测试 (server/test/)..."
echo "------------------------------------------------------------"
pushd server > /dev/null
dart pub get
if dart test test/ --reporter expanded; then
    echo ""
    echo "[PASS] 服务端测试全部通过."
else
    echo ""
    echo "[FAIL] 服务端测试失败!"
    FAIL=1
fi
popd > /dev/null
echo ""

# ---- 汇总 ----
echo "============================================================"
if [ $FAIL -eq 0 ]; then
    echo "  ✅ 所有测试通过!"
else
    echo "  ❌ 部分测试失败，请检查上方日志."
fi
echo "============================================================"

exit $FAIL
