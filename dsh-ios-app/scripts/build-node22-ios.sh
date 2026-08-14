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

echo "==> 限制 make 并行度为 -j2 (防 OOM)"
sed -i.bak 's/make -j$(getconf _NPROCESSORS_ONLN)/make -j1/g' tools/ios_framework_prepare.sh
grep -n "make -j1" tools/ios_framework_prepare.sh | head -3

echo "==> 构建 (官方流程: configure + make + xcodebuild)"
bash tools/ios_framework_prepare.sh arm64

echo "==> 收集产物"
FW=$(find "$SRC/out_ios_arm64" -path "*Release-iphoneos/NodeMobile.framework" -type d | head -1)
echo "framework: $FW"
[ -n "$FW" ] || { echo "ERROR: NodeMobile.framework 未找到"; exit 1; }
rm -rf "$OUT/NodeMobile.framework"
cp -R "$FW" "$OUT/"
ls -la "$OUT/NodeMobile.framework/"
echo "DONE"
