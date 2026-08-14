# CPUFreqControl - 自定义CPU限频插件 (iOS 17 / Dopamine rootless)
# 构建: export THEOS=/opt/theos && make package
#
# 重要: arm64e 设备 (A12+ / iPhone XS 及以上) 的系统进程只加载
#       arm64e "新ABI" 代码, 该 ABI 只能在 macOS 上编译。
#       Linux 上只能编 arm64 (给 arm64 设备用, 或调试用)。

export TARGET := iphone:clang:latest:15.0
export THEOS_PACKAGE_SCHEME := rootless
export DEBUG := 0
export FINALPACKAGE := 1

# 架构: macOS -> arm64 + arm64e 双切片; Linux -> 仅 arm64 (clang 编不出真 arm64e)
ifeq ($(shell uname),Linux)
export ARCHS := arm64
else
export ARCHS := arm64 arm64e
endif

# Linux 工具链 (macOS 上自动使用 Xcode 自带 clang)
ifeq ($(shell uname),Linux)
export TARGET_CC := clang-19
export TARGET_CXX := clang++-19
export TARGET_LD := clang-19
export TARGET_STRIP := llvm-strip-19
ADDITIONAL_LDFLAGS = -fuse-ld=lld -B/usr/local/bin
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CPUFreq
CPUFreq_FILES = Tweak.x
CPUFreq_CFLAGS = -fno-objc-arc -Wno-deprecated-declarations -Wno-objc-messaging-id

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = CPUFreqPrefs
CPUFreqPrefs_FILES = CPUFreqPrefs.m ioreport.m
CPUFreqPrefs_INSTALL_PATH = /Library/PreferenceBundles
CPUFreqPrefs_FRAMEWORKS = UIKit
CPUFreqPrefs_PRIVATE_FRAMEWORKS = Preferences
CPUFreqPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
