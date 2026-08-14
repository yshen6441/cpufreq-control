#!/bin/bash
# Linux 上交叉编译 node 22 for iOS (ubuntu CI, 16GB 内存)
# 用法: bash build-node22-linux.sh <nodejs-mobile目录> <输出目录> <iOS SDK路径>
set -e

SRC="${1:?nodejs-mobile 目录}"
OUT="${2:?输出目录}"
SDK="${3:?iOS SDK 路径}"
FAKEBIN=/tmp/fakebin
mkdir -p "$OUT" "$FAKEBIN"

# ── 伪造 macOS 工具 (gyp 需要) ──────────────────────────────
cat > "$FAKEBIN/xcrun" <<EOF
#!/bin/bash
SDK="$SDK"
if [[ "\$*" == *"--show-sdk-path"* ]]; then echo "\$SDK"; exit 0; fi
if [[ "\$*" == *"--show-sdk-version"* ]]; then echo "17.0"; exit 0; fi
args=("\$@")
for i in "\${!args[@]}"; do
  if [[ "\${args[\$i]}" == "-f" || "\${args[\$i]}" == "--find" ]]; then
    tool="\${args[\$((i+1))]}"
    command -v "\$tool" 2>/dev/null && exit 0
    echo "/usr/bin/\$tool"; exit 0
  fi
done
exit 0
EOF
cat > "$FAKEBIN/xcodebuild" <<EOF
#!/bin/bash
SDK="$SDK"
if [[ "\$*" == *"-version"* && "\$*" == *"-sdk"* ]]; then
  echo "iPhoneOS17.0.sdk - (iphoneos17.0)"
  echo "SDKVersion: 17.0"
  echo "Path: \$SDK"
  exit 0
fi
if [[ "\$*" == *"-showsdks"* ]]; then
  echo "iphoneos17.0 - iOS 17.0 (iphoneos)"
  exit 0
fi
if [[ "\$*" == *"-version"* ]]; then
  echo "Xcode 16.0"
  echo "Build version 16A0000"
  exit 0
fi
exit 0
EOF

# ── host 编译器包装 (过滤 iOS 专属 flags) ──────────────────
cat > "$FAKEBIN/hostcc" <<'EOF'
#!/bin/bash
args=()
skip=0
for a in "$@"; do
  if [ "$skip" = "1" ]; then skip=0; continue; fi
  case "$a" in
    -arch|-isysroot|-target) skip=1; continue;;
    -mios-version-min=*|-miphoneos-version-min=*|-stdlib=libc++|-fembed-bitcode) continue;;
  esac
  args+=("$a")
done
exec gcc "${args[@]}"
EOF
cat > "$FAKEBIN/hostcxx" <<'EOF'
#!/bin/bash
args=()
skip=0
for a in "$@"; do
  if [ "$skip" = "1" ]; then skip=0; continue; fi
  case "$a" in
    -arch|-isysroot|-target) skip=1; continue;;
    -mios-version-min=*|-miphoneos-version-min=*|-stdlib=libc++|-fembed-bitcode) continue;;
  esac
  args+=("$a")
done
exec g++ "${args[@]}"
EOF
chmod +x "$FAKEBIN/xcrun" "$FAKEBIN/xcodebuild" "$FAKEBIN/hostcc" "$FAKEBIN/hostcxx"

# ── configure ──────────────────────────────────────────────
cd "$SRC"
echo "==> node 版本:"
grep -E "NODE_MAJOR_VERSION|NODE_MINOR_VERSION|NODE_PATCH_VERSION" src/node_version.h | head -3
export GYP_DEFINES="target_arch=arm64 host_os=linux target_os=ios"
export CC="clang-19 --target=arm64-apple-ios15.0 -isysroot $SDK"
export CXX="clang++-19 --target=arm64-apple-ios15.0 -isysroot $SDK"
export CC_host="$FAKEBIN/hostcc"
export CXX_host="$FAKEBIN/hostcxx"
export PATH="$FAKEBIN:$PATH"
./configure --dest-os=ios --dest-cpu=arm64 --cross-compiling \
  --with-intl=none --enable-static --openssl-no-asm \
  --v8-options=--jitless --without-node-code-cache \
  --without-node-snapshot --without-amaro 2>&1 | tail -3

# ── make ───────────────────────────────────────────────────
echo "==> make -j4 (约 40-70 分钟)"
make -j4

# ── 组装 NodeMobile.framework ──────────────────────────────
echo "==> 链接 framework"
mkdir -p "$OUT/NodeMobile.framework/Headers"
cp tools/ios-framework/NodeMobile/NodeMobile.h "$OUT/NodeMobile.framework/Headers/"
cp tools/ios-framework/NodeMobile/Info.plist "$OUT/NodeMobile.framework/"
LIBS=$(ls out/Release/*.a 2>/dev/null | tr '\n' ' ')
echo "静态库: $LIBS"
ld64.lld -arch arm64 -platform_version ios 15.0 17.0 -dylib -all_load \
  -framework CoreFoundation \
  -syslibroot "$SDK" \
  -install_name @rpath/NodeMobile.framework/NodeMobile \
  $LIBS -o "$OUT/NodeMobile.framework/NodeMobile"
ldid -S "$OUT/NodeMobile.framework/NodeMobile"
echo "==> 产物:"
ls -la "$OUT/NodeMobile.framework/"
echo "DONE"
