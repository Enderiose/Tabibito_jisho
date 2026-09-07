# 提示词：S1 单词数据层 + S3 词典标签页（已实现，迁移自主库 prompt/word-dict.md）

对应主库 PLAN.md P1 S1（数据层）和 S3（词典 UI），拆分后归本仓库。

## 当前实现状态（2026-09-08）

- `tools/word-source.json`：504 条 WoW 术语（id / kanji / reading / romaji / english / category）
- `tools/word-gen.js`：读词源生成 `modules/lang/words.lua` + `tools/tts-words.json`
- `modules/lang/words.lua`：504 条单词数据表，导出 `TJ_Words`
- `modules/lang/ui_dict.lua`：词典 UI（搜索 / 分类筛选 / 分页 / 详情），导出 `TJ_DictUI`
- `Media/sound/words/`：504 个单词 mp3，`tools/word-gen-audio.js --check` 504/504
- `tools/tts_synth.py`：edge-tts 合成器，被 kana-gen 与 word-gen-audio 调用

## 本文件保留的价值

- 词源数据结构：`id` 必须唯一、`category` 白名单（item/spell/zone/general）、
  `reading` 必须是平假名（TTS 喂假名才不会拼英文字母）
- `word-gen.js` 的校验规则与排序规则（先 category 再 id）
- 词典 UI 交互：搜索实时过滤、分类按钮组、懒创建列表行、点击展开详情
- 音频路径约定：`Media/sound/words/<id>.mp3`，由 `ADDON_NAME` 动态拼接（拆分后无需改）

后续扩词（新增 500 词、加分类）以本文件为口径：改 `word-source.json` → 跑 `word-gen.js` →
跑 `word-gen-audio.js` 合成音频 → 跑两套 `--check` 确认。
