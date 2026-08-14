#!/bin/bash
# 组装 DSH iOS runtime 目录 (node_modules + pty + server + bash 包装)
# 输出到 dsh-ios-app/layout/Applications/DSH.app/runtime/
set -e

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$APP_DIR/layout/Applications/DSH.app/runtime"
NODE="${NODE_BIN:-node}"

echo "==> 清理旧 runtime"
rm -rf "$RUNTIME"
mkdir -p "$RUNTIME"

echo "==> npm 安装 DSH (忽略原生编译, node-pty 用预编译 iOS 版)"
cd "$RUNTIME"
npm init -y >/dev/null 2>&1
npm install @deepseek-ai/dsh --ignore-scripts --no-fund --no-audit --loglevel=error

echo "==> 放入 iOS 版 node-pty (预编译)"
mkdir -p node_modules/node-pty/build/Release
cp "$APP_DIR/vendor/pty/pty.node" node_modules/node-pty/build/Release/pty.node
cp "$APP_DIR/vendor/pty/spawn-helper" node_modules/node-pty/build/Release/spawn-helper
chmod 755 node_modules/node-pty/build/Release/spawn-helper

echo "==> 复制启动脚本与 bash 包装"
cp "$APP_DIR/runtime/server.mjs" "$RUNTIME/server.mjs"
mkdir -p "$RUNTIME/bin"
cp "$APP_DIR/runtime/bin/bash" "$RUNTIME/bin/bash"
chmod 755 "$RUNTIME/bin/bash"

echo "==> 清理 (测试/缓存/文档)"
rm -rf node_modules/.cache
find node_modules -name "*.md" -delete 2>/dev/null || true
find node_modules -name "test" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find node_modules -name "*.map" -delete 2>/dev/null || true

echo "==> runtime 大小"
du -sh "$RUNTIME"
echo "DONE"
