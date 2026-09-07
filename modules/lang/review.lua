-- review.lua
--- SM-2 间隔重复引擎 + 复习队列管理。
--- 只读 TJ_Store（存档）和 TJ_Kana（数据），无外部依赖。

local Store = _G.TJ_Store
local Kana = _G.TJ_Kana

-- SM-2 标准参数
local INITIAL_EF = 2.5
local MIN_EF = 1.3
local SESSION_MAX = 20
local MASTERED_THRESHOLD = 21 -- interval >= 21 天算掌握

--- 获取今天日期字符串 "YYYY-MM-DD"。
local function Today()
    return date("%Y-%m-%d")
end

--- 日期字符串加 N 天，返回新的日期字符串。
--- WoW 沙箱没有 os 库，用 Fliegel–Van Flandern 公式做纯算术日期换算。
local function DateToSerial(y, m, d)
    local a = math.floor((14 - m) / 12)
    local yy = y + 4800 - a
    local mm = m + 12 * a - 3
    return d + math.floor((153 * mm + 2) / 5) + 365 * yy
        + math.floor(yy / 4) - math.floor(yy / 100) + math.floor(yy / 400) - 32045
end

local function SerialToDate(serial)
    local a = serial + 32044
    local b = math.floor((4 * a + 3) / 146097)
    local c = a - math.floor(146097 * b / 4)
    local dd = math.floor((4 * c + 3) / 1461)
    local e = c - math.floor(1461 * dd / 4)
    local mm = math.floor((5 * e + 2) / 153)
    local day = e - math.floor((153 * mm + 2) / 5) + 1
    local month = mm + 3 - 12 * math.floor(mm / 10)
    local year = 100 * b + dd - 4800 + math.floor(mm / 10)
    return year, month, day
end

local function AddDays(dateStr, days)
    local y, m, d = dateStr:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return Today() end
    local ny, nm, nd = SerialToDate(DateToSerial(tonumber(y), tonumber(m), tonumber(d)) + days)
    return string.format("%04d-%02d-%02d", ny, nm, nd)
end

--- 两个日期字符串相减，返回天数差（a - b）。a 比 b 晚则为正。
local function DaysDiff(a, b)
    local ay, am, ad = a:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    local by, bm, bd = b:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not (ay and by) then return 0 end
    return DateToSerial(tonumber(ay), tonumber(am), tonumber(ad))
        - DateToSerial(tonumber(by), tonumber(bm), tonumber(bd))
end

--- 确保 cards 表里有所有 46 个音节的条目，缺的补默认。
local function InitCards()
    local db = Store.DB()
    if not db.review then db.review = {} end
    if not db.review.cards then db.review.cards = {} end
    local cards = db.review.cards
    local today = Today()
    Kana.ForEachCell(function(cell)
        if not cards[cell.r] then
            cards[cell.r] = {
                interval = 0,
                repetitions = 0,
                easeFactor = INITIAL_EF,
                dueDate = today,
            }
        end
    end)
end

--- 取今天应复习的卡片（dueDate <= today）。
local function GetDueCards()
    InitCards()
    local db = Store.DB()
    local cards = db.review.cards
    local today = Today()
    local due = {}
    for romaji, card in pairs(cards) do
        if card.dueDate and card.dueDate <= today then
            due[#due + 1] = { romaji = romaji, card = card }
        end
    end
    return due
end

--- 取从未复习过的卡片（interval=0, repetitions=0）。
local function GetNewCards()
    InitCards()
    local db = Store.DB()
    local cards = db.review.cards
    local today = Today()
    local newCards = {}
    for romaji, card in pairs(cards) do
        if card.interval == 0 and card.repetitions == 0 then
            newCards[#newCards + 1] = { romaji = romaji, card = card }
        end
    end
    return newCards
end

--- Fisher-Yates 洗牌。
local function Shuffle(arr)
    for i = #arr, 2, -1 do
        local j = math.random(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

--- 构建一轮复习 session：due + new 合并，随机打乱，截断到 maxCards。
local function BuildSession(maxCards)
    maxCards = maxCards or SESSION_MAX
    local due = GetDueCards()
    local newCards = GetNewCards()
    -- 合并：due 优先，再补 new
    local pool = {}
    for i = 1, #due do pool[#pool + 1] = due[i] end
    for i = 1, #newCards do pool[#pool + 1] = newCards[i] end
    Shuffle(pool)
    if #pool > maxCards then
        local truncated = {}
        for i = 1, maxCards do truncated[i] = pool[i] end
        pool = truncated
    end
    return pool
end

--- 执行 SM-2 更新。quality: 5=知道, 3=模糊, 1=不知道。
local function ReviewCard(romaji, quality)
    InitCards()
    local db = Store.DB()
    local card = db.review.cards[romaji]
    if not card then return end

    local q = tonumber(quality) or 1
    local ef = card.easeFactor or INITIAL_EF

    if q >= 3 then
        -- 成功：递增 repetitions 和 interval
        card.repetitions = (card.repetitions or 0) + 1
        if card.repetitions == 1 then
            card.interval = 1
        elseif card.repetitions == 2 then
            card.interval = 6
        else
            card.interval = math.max(1, math.floor(card.interval * ef + 0.5))
        end
    else
        -- 失败：重置
        card.repetitions = 0
        card.interval = 1
    end

    -- 更新 EF：EF' = EF + (0.1 - (5-q)*(0.08 + (5-q)*0.02))
    ef = ef + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
    card.easeFactor = math.max(MIN_EF, ef)

    card.dueDate = AddDays(Today(), card.interval)
end

--- 计算复习统计。
local function GetStats()
    InitCards()
    local db = Store.DB()
    local cards = db.review.cards
    local stats = db.review.stats or {}
    local mastered = 0
    local total = 0
    for _, card in pairs(cards) do
        total = total + 1
        if card.interval >= MASTERED_THRESHOLD then
            mastered = mastered + 1
        end
    end
    local today = Today()
    local dueCount = 0
    for _, card in pairs(cards) do
        if card.dueDate and card.dueDate <= today then
            dueCount = dueCount + 1
        end
    end
    return {
        streak = stats.streak or 0,
        mastered = mastered,
        dueCount = dueCount,
        totalReviewed = stats.totalReviewed or 0,
        mastery = total > 0 and math.floor(mastered / total * 100 + 0.5) or 0,
        total = total,
    }
end

--- 更新 streak 和累计复习次数，在 session 结束时调用。
local function MarkReviewed()
    local db = Store.DB()
    if not db.review.stats then db.review.stats = {} end
    local stats = db.review.stats
    local today = Today()
    local last = stats.lastReviewDate

    if last == today then
        -- 同一天已记录过，只增累计
    elseif last == AddDays(today, -1) then
        stats.streak = (stats.streak or 0) + 1
    else
        stats.streak = 1
    end
    stats.lastReviewDate = today
    stats.totalReviewed = (stats.totalReviewed or 0) + 1
end

--- 复习是否有 due 或 new 卡片。
local function HasWork()
    InitCards()
    local db = Store.DB()
    local cards = db.review.cards
    local today = Today()
    for _, card in pairs(cards) do
        if (card.dueDate and card.dueDate <= today) or (card.interval == 0 and card.repetitions == 0) then
            return true
        end
    end
    return false
end

local function IsEnabled()
    local db = Store.DB()
    return db.review and db.review.kanaEnabled or false
end

local function SetEnabled(flag)
    local db = Store.DB()
    if not db.review then db.review = {} end
    db.review.kanaEnabled = flag and true or false
end

local function GetMode()
    local db = Store.DB()
    return (db.review and db.review.kanaMode) or "recognize"
end

local function SetMode(mode)
    local db = Store.DB()
    if not db.review then db.review = {} end
    db.review.kanaMode = (mode == "listen") and "listen" or "recognize"
end

local function GetAudioAutoPlay()
    local db = Store.DB()
    return db.review and db.review.settings and db.review.settings.audioAutoPlay
end

local function SetAudioAutoPlay(flag)
    local db = Store.DB()
    if not db.review then db.review = {} end
    if not db.review.settings then db.review.settings = {} end
    db.review.settings.audioAutoPlay = flag and true or false
end

--- 根据 romaji 找到 kana 数据表里的 cell。
local function FindCell(romaji)
    local found = nil
    Kana.ForEachCell(function(cell)
        if cell.r == romaji then found = cell end
    end)
    return found
end

--- 取所有音节的 romaji 列表（用于听音辨字模式选干扰项）。
local function GetAllRomaji()
    local list = {}
    Kana.ForEachCell(function(cell)
        list[#list + 1] = cell.r
    end)
    return list
end

_G.TJ_Review = {
    SESSION_MAX = SESSION_MAX,
    MASTERED_THRESHOLD = MASTERED_THRESHOLD,
    InitCards = InitCards,
    GetDueCards = GetDueCards,
    GetNewCards = GetNewCards,
    BuildSession = BuildSession,
    ReviewCard = ReviewCard,
    GetStats = GetStats,
    MarkReviewed = MarkReviewed,
    HasWork = HasWork,
    IsEnabled = IsEnabled,
    SetEnabled = SetEnabled,
    GetMode = GetMode,
    SetMode = SetMode,
    GetAudioAutoPlay = GetAudioAutoPlay,
    SetAudioAutoPlay = SetAudioAutoPlay,
    FindCell = FindCell,
    GetAllRomaji = GetAllRomaji,
    Today = Today,
    AddDays = AddDays,
    DaysDiff = DaysDiff,
}
