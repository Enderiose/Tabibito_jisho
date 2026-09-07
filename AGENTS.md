# AGENTS.md — Tabibito Jisho

> Agent 责任：每周提醒用户校验一次本文件内容。

## 1. 项目身份

- World of Warcraft Classic 插件（国服，熊猫人之谜怀旧服为主要目标）。
- 技术栈：Lua 5.1 + WoW API + Git；无构建系统，保存即生效，游戏内 `/reload` 测试。
- 独立插件，**不依赖 `BGLite`**，禁止反向依赖 `BGLAO_*`。

## 2. 目录地图

- `Tabibito_jisho.toc` — 加载入口（阶段 3 建）
- `core/`、`modules/` — 词典/复习/手账代码（阶段 4~6 迁入）
- `locales/` — 插件自带 locale（阶段 3 定策略）
- `Media/` — 音频与图标（阶段 5 迁入）
- `tools/` — 开发期脚本（不在 .toc，不被游戏加载）
- `docs/SPEC.md` — 架构地图与红线；`docs/PLAN.md` — 排期

## 3. 代码风格

- LF 换行，禁止 CRLF；UTF-8 无 BOM。
- 禁止未声明全局变量（WoW API 除外）；注释 `--`，函数说明 `---`。

## 4. 命令清单

- 编码扫描：`node tools\encoding-check.js`（`--fix` 自动修复）
- 语法校验：`node tools\luaparse-check.js`
- `git diff --check` 查空白错误；`git diff --stat` 看变更统计
- 提交前必须过前两条 + `git diff --check`
- 沙箱对 `.git` 只读：`git add` / `git commit` 需提权执行
- Git 操作规范（非交互式）：
  - 暂存用 `git add .`，不逐文件列举，不用 `-p`
  - 提交用 `git commit -m "msg" --no-edit`
  - 所有 git 命令前加 `PAGER=cat` 环境变量（PowerShell: `$env:PAGER='cat';`）
  - 提权命令末尾追加 `--batch` 或 `--non-interactive`
  - 全程无需用户确认，禁用所有交互式提示

## 5. 红线

1. **运行时没有 AI**：无网络、无 TTS、无语音识别。音频一律开发期生成静态文件进 `Media/`，运行时只播。
2. **自持**：不引用 `BGLAO_*`；按钮工厂、存档、locale 全部插件内自带。
3. **禁止写入 UTF-8 BOM 或 UTF-16**；禁止 PowerShell 5.1 `>` / `Out-File` 写文本。
4. **临时文件只进项目内 `tmp/`**，任务结束删除。
5. **`C_Timer.NewTicker(60)` 会话心跳是唯一常驻定时器**，用于崩溃封口，不是资源轮询；改它先查 `docs/SPEC.md`。
6. **`.git` 为沙箱只读目录**；`git add` / `git commit` 需提权，提交用 `git commit -m "msg" --no-edit`。

## 6. 版本号

- 版本只写在 `.toc` 的 `## Version:`；首个拆分基线 `0.0.1`。
