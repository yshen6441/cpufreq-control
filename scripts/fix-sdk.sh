#!/bin/bash
# 修复 iOS SDK zip 中损坏的符号链接
# 背景: xybp888/iOS-SDKs 的 zip 把 SDK 里的符号链接压成了纯文本路径文件
#      (如 pthread.h 内容为 "pthread/pthread.h"), 会导致编译/链接失败。
# 用法: bash scripts/fix-sdk.sh <SDK目录>
set -e
SDK_DIR="${1:?用法: fix-sdk.sh <SDK目录>}"

python3 - "$SDK_DIR" <<'EOF'
import os, re, sys
SDK = sys.argv[1]
pattern = re.compile(r'^[A-Za-z0-9._/-]+$')
fixed = 0
for root, dirs, files in os.walk(SDK):
    for fn in files:
        p = os.path.join(root, fn)
        try:
            with open(p, 'rb') as f:
                data = f.read()
        except OSError:
            continue
        if len(data) == 0 or len(data) > 300:
            continue
        try:
            content = data.decode('utf-8').strip()
        except UnicodeDecodeError:
            continue
        if '\n' in content or '\r' in content:
            continue
        if not pattern.match(content):
            continue
        if content.startswith('/'):
            continue  # 绝对路径不是链接目标
        # 相对路径 (含 ../), 校验目标存在后转为符号链接
        target = os.path.normpath(os.path.join(root, content))
        if os.path.exists(target):
            os.remove(p)
            os.symlink(content, p)
            fixed += 1
print(f"fix-sdk: 修复 {fixed} 个损坏的符号链接")
EOF
