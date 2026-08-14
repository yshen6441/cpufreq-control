# CPUFreqControl — 自定义 CPU 频率控制插件

为越狱 iPhone（iOS 15–17，Dopamine / rootless）开发的 CPU 限频 + 实时频率显示插件。
在 iPhone 12 mini（A14 / iOS 17.0 / Dopamine 3）上开发验证。

## 功能

| 功能 | 说明 |
|---|---|
| 多档限频 | 关闭 / 标准 / 轻度 / 中度 / 重度，对应系统热仿真等级 |
| 自定义模式字符串 | 手动输入任意热仿真模式名（如 `moderate`） |
| 低电量联动 | 可设置"仅低电量模式下生效" |
| 实时频率显示 | 设置页每秒刷新 P 核（大核）/ E 核（小核）当前频率（MHz） |
| 即时生效 | 设置变更后无需注销，自动应用 |

## 原理（重要）

- **限频机制**：与开源插件 [Powercuff](https://github.com/rpetrich/Powercuff) 相同——
  调用 `thermalmonitord` 中 `CommonProduct` 的私有方法
  `putDeviceInThermalSimulationMode:`，用**热仿真**让系统电源管理把 CPU 最高频率
  限制到对应档位。这不是直接写频率寄存器，而是系统级限频。
- **频率读取**：IOReport 私有 API（`CPU Stats` → `CPU Frequency` 通道），
  用户态可读，无需内核权限。
- **限制（务必知晓）**：
  - ❌ **不能超频**，不能锁死到任意 MHz —— iOS 用户态没有内核频率接口，
    Dopamine 不提供内核内存写入能力。
  - ⚠️ 热仿真 API 是私有 API，iOS 17 上如系统改动该方法名则静默失效
    （可在系统日志中查看 `[CPUFreq]` 前缀日志确认是否生效）。

## 构建

### 方法一：GitHub Actions 自动构建（推荐，产出 arm64e 双切片）

> **为什么必须这样构建**：iPhone 12 mini（A14）是 **arm64e** 设备。iOS 15+ 上
> arm64e 设备的系统进程（Settings / SpringBoard / thermalmonitord）**只加载
> arm64e "新 ABI" 代码**，arm64 或旧 ABI 的插件都无法注入。而新 ABI 只能在
> macOS 上用 Apple 工具链编译（Linux clang 编不出真正的 arm64e）。

1. 在 GitHub 新建一个仓库（公开即可）
2. 把整个工程目录（含 `.github/workflows/build.yml`）push 上去：

```sh
cd cpufreq-control
git init
git add .
git commit -m "init"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

3. 打开仓库的 **Actions** 页面，等待构建完成（约 5 分钟）
4. 在构建记录里下载 **CPUFreqControl-deb** 产物（.deb 文件，内含 arm64+arm64e 双切片）
5. 传手机安装（见下方"安装"）

以后每次 push 代码都会自动重新构建；也可在 Actions 页面手动触发。

### 方法二：macOS 本地构建

```sh
# 需要: Theos (https://theos.dev/docs/installation) + iOS SDK (theos/sdks)
export THEOS=/path/to/theos
gmake clean package FINALPACKAGE=1
```

### 方法三：Linux 构建（仅 arm64，只能用于 arm64 设备如 iPhone 8 及更早）

```sh
export THEOS=/path/to/theos   # 需要 clang-19 lld-19 ldid, 及 ld64.lld 包装
make clean package            # 产物仅为 arm64 切片, arm64e 设备上无法注入系统进程
```

说明：`ARCHS=arm64`（A14 等 arm64e 设备可运行 arm64 切片；Linux 上无法编译 arm64e）。

## 安装（iPhone 12 mini / Dopamine 3）

1. 把 `.deb` 传到手机（爱思助手 / SFTP / 微信文件均可）。
2. 用 Sileo / Zebra 安装：右上角添加 → 本地文件 → 选择 deb；
   或终端（NewTerm）：`sudo dpkg -i 包名.deb`，再 `sbreload`。
3. 设置 → CPU频率控制，配置模式并点"立即应用"。
4. 验证：设置页看实时频率是否被压低；或 `log stream --predicate 'process == "thermalmonitord"'` 查看 `[CPUFreq]` 日志。

## 文件结构

```
Makefile                  # Theos 构建配置 (rootless)
control                   # 包元数据
Tweak.x                   # 插件主体: thermalmonitord + SpringBoard 钩子
CPUFreqPrefs.m            # 设置面板控制器 (含实时频率显示)
ioreport.h / ioreport.m   # IOReport 私有 API 封装 (dlsym 动态加载)
layout/                   # 过滤器 plist / 设置界面 / PreferenceLoader 入口
```

## 已知问题 / 后续

- iOS 17 上 `CommonProduct` 的 `putDeviceInThermalSimulationMode:` 是否可用需真机验证
  （Powercuff 在 iOS 15–16 可用，本插件机制相同）。
- 若该方法失效，可尝试 hook `CommonProduct` 的 `thermalMode` 或改用
  直接修改 `powerd` 行为，需要更多逆向。
