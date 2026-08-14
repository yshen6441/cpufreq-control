# DSH iOS App - DeepSeek Harness WebUI 客户端
# 一个极简 WKWebView 壳 App: 打开即连 DSH 服务器, 全屏 WebUI。
# 构建: Theos (与 cpufreq-control 同工具链)

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
DSH_FRAMEWORKS = UIKit WebKit
DSH_CFLAGS = -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/application.mk
