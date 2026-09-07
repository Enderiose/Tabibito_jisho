# 提示词：S2 假名 SM-2 复习（已实现，迁移自主库 prompt/kana-review.md）

对应主库 PLAN.md P1 S2（拆分后归本仓库 PLAN.md）。五十音假名间隔重复复习系统，基于 SM-2 算法。

## 当前实现状态（2026-09-08）

- `modules/lang/review.lua`：SM-2 引擎，导出 `TJ_Review`
- `modules/lang/ui_review.lua`：闪卡 UI，导出 `TJ_ReviewUI`
- `modules/lang/store.lua`：`review` 块在 DEFAULTS 中
- `modules/lang/ui_kana.lua`：Tab 容器（五十音 | 复习 | 词典 | 单词）
- `modules/lang/lang.lua`：`/jisho` 主命令（`/kana` 别名已删）
- `locales/zhCN.lua` / `enUS.lua` / `zhTW.lua`：`reviewLoginReminder` / `wordReviewLoginReminder`
- 音频：`Media/sound/lang/` 46 个 mp3，`tools/kana-gen.js --check` 46/46

## 本文件保留的价值

- SM-2 算法参数（quality 阈值 3、interval 公式、EF 公式、streak 计算规则）
- 状态机：idle → question → answer → rating
- 认读 / 听音辨字双模式设计决策
- session 上限 20 张、同日随机打乱

后续改动（调参、改 UI、加模式）以本文件为设计口径，不要另开文档。
