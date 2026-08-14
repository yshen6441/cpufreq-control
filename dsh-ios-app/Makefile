# DSH iOS App - DeepSeek Harness 客户端
# 本地模式: 内嵌 Node.js (NodeMobile.framework) 直接运行 DSH, 无需电脑
# 远程模式: WKWebView 连接局域网服务器 (备选)
#
# 构建 (CI):
#   1. scripts/build-node22-ios.sh  -> vendor/NodeMobile.framework (node 22 iOS)
#   2. scripts/assemble-runtime.sh  -> layout/.../DSH.app/runtime/ (DSH + 依赖)
#   3. make package                 -> deb + ipa

export TARGET := iphone:clang:17.0:15.0
export THEOS_PACKAGE_SCHEME := rootless
export DEBUG := 0
export FINALPACKAGE := 1

ifeq ($(shell uname),Linux)
export ARCHS := arm64
export TARGET_CC := clang-19
export TARGET_CXX := clang++-19
export TARGET_LD := clang-19
export TARGET_STRIP := llvm-strip-19
ADDITIONAL_LDFLAGS = -fuse-ld=lld -B/usr/local/bin
else
export ARCHS := arm64 arm64e
endif

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = DSH
DSH_FILES = main.m AppDelegate.m ViewController.m
DSH_FRAMEWORKS = UIKit WebKit NodeMobile
DSH_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Ivendor/NodeMobile.framework/Headers
# NodeMobile.framework 来自 vendor/ (CI 由 build-node22-ios.sh 生成)
DSH_LDFLAGS = -Fvendor -rpath @executable_path/Frameworks

include $(THEOS_MAKE_PATH)/application.mk
