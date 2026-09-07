# AGENTS.md — Tabibito Jisho

> Agent 责任：每周提醒用户校验一次本文件内容。

## 1. 项目身份

- World of Warcraft Classic 插件（国服，熊猫人之谜怀旧服为主要目标）。
- 技术栈：Lua 5.1 + WoW API + Git；无构建系统，保存即生效，游戏内 `/reload` 测试。
- 独立插件，**不依赖 `BGLite`**，禁止反向依赖 `BGLAO_*`。

## 2. 目录地图

- `Tabibito_jisho.toc` — 加载入口：Interface 版本列表、加载顺序、SavedVariables
- `core/journal.lua` — 冒险家手账（会话采集、登录时讲述上一次冒险、`/jisho sz`）
- `modules/lang/` — 旅人辞典：五十音、SM-2 闪卡复习、词典；自带控件工厂与存档
- `locales/zhCN.lua`、`locales/enUS.lua`、`locales/zhTW.lua` — 插件自带 locale（登录提醒）
- `Media/sound/lang/` — 46 个假名 mp3；`Media/sound/words/` — 504 个单词 mp3；`Media/icon/play.tga` — 播放图标
- `tools/` — 开发期脚本（不在 .toc，不被游戏加载）：`encoding-check.js`（编码扫描）、
  `luaparse-check.js`（语法校验）、`kana-gen.js`（假名音频闸门）、`word-gen.js`（词源生成）、
  `word-gen-audio.js`（单词音频闸门）、`tts_synth.py`（edge-tts 合成器）、
  `word-source.json` / `tts-words.json`（词源与 TTS 清单）
- `.dev/media/icon/play.png` — 图标开发源文件
- `docs/SPEC.md` — 架构地图与红线；`docs/PLAN.md` — 排期
- `prompt/` — 设计口径与术语表（review.md / word-dict.md / glossary.txt / README.md）

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
  - 提权命令末尾追加 `--batch` 或 `--non-interactive`；全程禁用所有交互式提示

## 5. Session 工作流

每次新 session / fork 启动时按以下顺序建立上下文：
1. 读本文件（索引）。
2. 读 `docs/SPEC.md`（模块职责 + 数据模型 + 事件流 + 红线）。
3. `git log --oneline -5` + `git status` 确认当前状态。
4. 按任务类型选择工作流（见下）。

### WoW 外部资料查询

涉及 WoW API、FrameXML 或游戏数据时，遵循：

1. **项目内优先**
   * 先检查项目文档、代码、FrameXML、注释、本地测试及已有查询结果。
   * 项目内能够确定答案时，不调用外部查询。
2. **API / FrameXML → `wow-api`**
   * 项目内资料不足时，委派 `wow-api` subagent 查询 `wow-api` MCP。
   * `wow-api` 只负责 API / FrameXML 查询与验证，不修改项目。
3. **游戏数据 → `wowdata`**
   * 涉及 Spell、Item、Creature、Quest、Achievement、ID、本地化名称或多版本数据时，使用 `wowdata` subagent。
   * `wowdata` 使用本地 `wowdata` CLI 查询 Blizzard CDN，不作为 MCP 使用。
4. **API 与数据同时涉及**
   * 分别委派给对应 subagent，不混淆职责。
5. **禁止猜测**
   * API、ID、DB2 数据、本地化名称及版本差异不得仅凭模型记忆确定。
   * WoW 数据高度依赖版本；任务指定的版本、Build、Region、Locale 等必须传递给对应 subagent。
6. **外部网页**
   * `wow-api` MCP 能回答时，不再进行网页搜索。
   * 仅在项目资料和对应 subagent 均无法回答，或确需额外资料交叉验证时，才允许网页搜索。

### Session 类型
- **bugfix**：用户报 bug → SPEC.md 模块职责表定位文件 → 读该模块代码 + 相关红线 → 修复 → luaparse → encoding-check → `git diff --check` → 游戏内 `/reload` 验证 → commit。
- **feature**：读 SPEC.md 数据模型 → 实现 → 补 locales（三语同步）→ luaparse → encoding-check → `git diff --check` → 测试 → commit。
- **review**：encoding-check → luaparse 全量扫描 → `git diff --check` → 逐条核对红线 → 输出报告。

### 目录地图维护

- **每次增删文件或目录，必须同步更新本文件 §2 目录地图。**
- 新增运行期文件：确认 `.toc` 加载清单 + 本文件 §2 都登记了。
- 新增开发期脚本：确认本文件 §2 + §4 命令清单（如有新命令）都登记了。
- 新增 `Media/` 子目录：确认本文件 §2 已登记；若要进发布包还要看将来是否有 pack 脚本。
- 删除文件：从 §2 地图删掉对应行，不留"已删除"注释。
- 判断标准：一个新人只读 AGENTS.md §2 就能知道这个文件是干什么的、归哪个模块管。

### 版本号规则
- 小版本号（第三段 patch）不得大于 9：加到 10 时进位次版本号（minor）并把 patch 归 0。
- 单纯的 bug 修复不做版本号变更。
- 版本号只在 `.toc` 的 `## Version:`；当前 `0.0.1`。

### 隔离原则
- 一个 session 聚焦一个任务：不混 bugfix 和 feature，不顺带跨模块改无关代码。
- session 结束时：commit 描述清楚改了什么；如有新架构债，更新 `docs/SPEC.md` 已知架构债节。
- session 结束时：从 `docs/PLAN.md` 删除已完成条目；版本变更时同步 `.toc` 版本号。
- fork 恢复锚点固定为：AGENTS.md → SPEC.md → git log。上下文活在仓库里，不依赖聊天记录传递。

## 6. 红线

1. **运行时没有 AI**：无网络、无 TTS、无语音识别。音频一律开发期生成静态文件进 `Media/`，运行时只播。
2. **自持**：不引用 `BGLAO_*`；按钮工厂、存档、locale 全部插件内自带。
3. **禁止写入 UTF-8 BOM 或 UTF-16**；禁止 PowerShell 5.1 `>` / `Out-File` 写文本。
4. **临时文件只进项目内 `tmp/`**，任务结束删除。
5. **`C_Timer.NewTicker(60)` 会话心跳是唯一常驻定时器**，用于崩溃封口，不是资源轮询；改它先查 `docs/SPEC.md`。
6. **`.git` 为沙箱只读目录**；`git add` / `git commit` 需提权，提交用 `git commit -m "msg" --no-edit`。

## 7. 版本号

- 版本只写在 `.toc` 的 `## Version:`；首个拆分基线 `0.0.1`。
- 每次提升版本号，在玩家可见的变更说明中记录（暂无 patch 窗口；后续若加，另行登记）。
- `0.0.1` 之前无历史版本号规则包袱。
