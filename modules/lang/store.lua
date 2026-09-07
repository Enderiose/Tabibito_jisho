-- store.lua
--- 插件自有存档层：词典/复习数据与手账数据共用一个 TJ_LangDB。

local DB_NAME = "TJ_LangDB"

local DEFAULTS = {
    version = 1,
    kana = {
        katakana = false, -- 假名显示模式：false 平假名，true 片假名
        point = nil,      -- 五十音盘窗口位置，nil 表示还没拖过，用默认居中
    },
    review = {
        kanaEnabled = false,     -- 假名复习总开关，默认关闭
        kanaMode = "recognize",  -- "recognize"(认读) | "listen"(听音辨字)
        cards = {},              -- romaji → { interval, repetitions, easeFactor, dueDate }
        stats = {
            totalReviewed = 0,   -- 累计复习次数
            streak = 0,          -- 连续复习天数
            lastReviewDate = nil, -- 最后复习日期 "YYYY-MM-DD"
        },
        settings = {
            audioAutoPlay = true, -- 揭示时自动播放音频
        },
    },
    wordReview = {
        enabled = false,         -- 单词复习总开关，默认关闭
        cards = {},              -- word id → { interval, repetitions, easeFactor, dueDate }
        stats = {
            totalReviewed = 0,   -- 累计复习次数
            streak = 0,          -- 连续复习天数
            lastReviewDate = nil, -- 最后复习日期 "YYYY-MM-DD"
        },
        settings = {
            audioAutoPlay = true, -- 揭示时自动播放单词音频
        },
    },
}

local initialised = false

--- 逐字段补默认，不做整表覆盖：老存档里用户调过的设置不能被新版本的默认值冲掉。
local function CopyDefaults(target, source)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function Init()
    if initialised then return end
    initialised = true
    if type(_G[DB_NAME]) ~= "table" then _G[DB_NAME] = {} end
    CopyDefaults(_G[DB_NAME], DEFAULTS)
end

--- 取存档。首次调用顺手补默认，调用方不用关心初始化顺序。
local function DB()
    Init()
    return _G[DB_NAME]
end

_G.TJ_Store = {
    DB_NAME = DB_NAME,
    Init = Init,
    DB = DB,
}
