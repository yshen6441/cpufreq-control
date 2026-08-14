#!/bin/bash
# 在 macOS 上编译 node 22 for iOS, 产出 NodeMobile.framework
# 用法: bash scripts/build-node22-ios.sh <nodejs-mobile目录> <输出目录>
set -e

SRC="${1:?nodejs-mobile 目录}"
OUT="${2:?输出目录}"
mkdir -p "$OUT"

cd "$SRC"

echo "==> 确认 node 版本"
grep -E "NODE_MAJOR_VERSION|NODE_MINOR_VERSION|NODE_PATCH_VERSION" src/node_version.h | head -3

echo "==> configure (ios arm64, jitless)"
make clean 2>/dev/null || true
GYP_DEFINES="target_arch=arm64 host_os=mac target_os=ios" ./configure \
  --dest-os=ios \
  --dest-cpu=arm64 \
  --with-intl=none \
  --cross-compiling \
  --enable-static \
  --openssl-no-asm \
  --v8-options=--jitless \
  --without-node-code-cache \
  --without-node-snapshot

echo "==> make (低并行防 OOM)"
make -j2

echo "==> 组装 framework (prepare)"
bash tools/ios_framework_prepare.sh

echo "==> xcodebuild"
xcodebuild -project tools/ios-framework/NodeMobile.xcodeproj \
  -target NodeMobile \
  -configuration Release \
  -sdk iphoneos \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  build

echo "==> 收集产物"
FW=$(find "$SRC" -path "*Release-iphoneos/NodeMobile.framework" -type d | head -1)
if [ -z "$FW" ]; then
  FW=$(find "$SRC/tools/ios-framework" -name "NodeMobile.framework" -type d | head -1)
fi
echo "framework: $FW"
[ -n "$FW" ] || { echo "ERROR: NodeMobile.framework 未找到"; exit 1; }
cp -R "$FW" "$OUT/"
ls -la "$OUT/NodeMobile.framework/"
echo "DONE"
