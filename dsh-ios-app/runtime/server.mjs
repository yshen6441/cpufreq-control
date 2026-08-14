// ============================================================
// DSH iOS 本地服务器启动脚本 (由 App 内嵌 Node.js 执行)
// 位置: DSH.app/runtime/server.mjs
// ============================================================
import { readFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

// ── 1. 路径准备 ─────────────────────────────────────────────
const runtimeDir = dirname(new URL(import.meta.url).pathname);
const home = homedir();
process.env.HOME = home;

// ── 2. DeepSeek API Key (由 App 设置页写入 Documents/dsh-key.txt) ──
const keyFile = join(home, "Documents", "dsh-key.txt");
try {
	const key = readFileSync(keyFile, "utf8").trim();
	if (key) process.env.DEEPSEEK_API_KEY = key;
} catch {}
if (!process.env.DEEPSEEK_API_KEY) process.env.DEEPSEEK_API_KEY = "";

// ── 3. iOS 适配 ─────────────────────────────────────────────
// App 沙盒本身就是进程隔离: bash 走本地执行, 免审批弹窗
process.env.DSH_PERMISSION_MODE = "danger-full-access";

// iOS 没有 /bin/bash, 用自带 zsh 包装 (runtime/bin/bash)
const binDir = join(runtimeDir, "bin");
process.env.PATH = binDir + ":" + (process.env.PATH || "/usr/bin:/bin:/usr/sbin:/sbin");

// DSH 数据目录 (会话、配置、日志 — 可写)
const dshHome = join(home, ".dsh");
mkdirSync(dshHome, { recursive: true });
process.env.DSH_HOME = dshHome;

// ── 4. 启动 DSH web profile ─────────────────────────────────
process.argv = ["node", "server.mjs", "--profile", "web", "--port", "3080"];
await import("@deepseek-ai/dsh/lib/bin.js");
