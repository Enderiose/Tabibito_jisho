# PLAN.md — Tabibito Jisho 排期

> 阶段 1~2 已在主库 `docs/PLAN.md` T0 节完成底账；本文件承接后续阶段。

## 已完成

- 阶段 1：全库重扫、硬依赖清单、改名映射、检测页分类结论（见主库 `docs/handnew.md`）。
- 阶段 2：本仓库 `git init` + 脚手架（`.editorconfig` / `.gitattributes` / `.gitignore` /
  `tools/encoding-check.js` / `tools/luaparse-check.js` / 本文档 / `AGENTS.md`）。

## 待做

1. **（完成 2026-09-08）** 阶段 3：`.toc`（版本 `0.0.1`）、`TJ_*` 命名空间、
   自带 locale（`modules/lang/locale.lua` + 三语登录提醒键）、`/kana` 别名删除。
2. **（完成 2026-09-08）** 阶段 4 + 6：`core/journal.lua` 迁入；`TabibitoJishoDB` 自带存档层
   （`migratedFrom` / `migratedAt` 标记 + 一次性深拷贝旧库）；`NowSeconds()` / `CharacterKey()` 同源复刻
   （`realm-name` 顺序与主插件一致）；`ShowWhenClear` 去掉 `BGLAO_WelcomeFrame` 反向依赖；
   `/journal` 并入 `/jisho sz` 子命令；帧名改 `TJ_JournalFrame` / `TJ_JournalScrollFrame`；
   导出改 `TJ_JournalShow` / `TJ_JournalSetEnabled`。
3. **（完成 2026-09-08）** 阶段 5：词典/五十音 UI（11 个 Lua）与 46 + 504 个音频、
   `play.tga`、`.dev` 图标源、词源工具链迁入；`ADDON_NAME` 路径未改写（按主库结论保持原样）。
4. **（已并入第 2 条）** 阶段 6。
5. 阶段 7：主插件清理（与阶段 5~6 同一轮落地，防 `SlashCmdList` 覆盖）。
6. 阶段 8：双库闸门（本仓库跑 encoding-check + luaparse-check + `git diff --check`）。
7. 阶段 9：游戏内验收。
8. 阶段 10：双库 commit。
