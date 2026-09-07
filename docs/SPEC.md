# SPEC.md — Tabibito Jisho 项目地图

> 本文件是骨架，代码迁移时逐节充实。当前事实以 `docs/PLAN.md` 为准。

## 一句话

独立插件：旅人辞典（WoW 术语日语学习）+ 冒险家手账（会话记录），从 `BGLite_AccountOverview` 拆出。

## 加载顺序

阶段 3 定义。原则：widgets → 数据 → 复习数据层 → UI → 入口，线性依赖，前面的模块不引用后面的。

## 命名空间

- 前缀 `TJ_*`，不做 `BGLAO_*` 别名。
- 全局帧名只有 `TJ_MainFrame`（原 `BGLAO_LangKanaFrame`）与 `TJ_JournalFrame` / `TJ_JournalScrollFrame`。
- SavedVariables：`TabibitoJishoDB`（手账一次性迁移源为 `BGLiteAccountOverviewDB.data.journal`）
  与继承的 `BGLAOLangDB`（词典/复习）。

## 数据迁移

阶段 4 实现，口径见主库 `docs/handnew.md`《手账旧数据迁移写入口径》：一次性深拷贝 + `migratedFrom` 标记，
旧字段暂不删除，新库只读写自己的库。

## 已知架构债

- 阶段 3 前空缺。
