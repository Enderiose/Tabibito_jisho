-- wordreview.lua
--- 单词 SM-2 间隔重复引擎。
--- 与假名 review.lua 刻意保持独立：两个数据源、两套进度，将来拆分插件时可以整块带走。

local Store = _G.TJ_Store
local Words = _G.TJ_Words

-- SM-2 标准参数，与假名复习保持同一节奏。
local INITIAL_EF = 2.5
local MIN_EF = 1.3
local SESSION_MAX = 20
local MASTERED_THRESHOLD = 21

local function Today()
    return date("%Y-%m-%d")
end

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

--- 按 word id 建卡。卡片key跟词库数据走，不依赖读音唯一性。
local function InitCards()
    local db = Store.DB()
    if not db.wordReview then db.wordReview = {} end
    if not db.wordReview.cards then db.wordReview.cards = {} end

    local cards = db.wordReview.cards
    local today = Today()
    local data = Words.GetData()
    for index = 1, #data do
        local id = data[index].id
        if not cards[id] then
            cards[id] = {
                interval = 0,
                repetitions = 0,
                easeFactor = INITIAL_EF,
                dueDate = today,
            }
        end
    end
end

local function GetDueCards()
    InitCards()
    local db = Store.DB()
    local cards = db.wordReview.cards
    local today = Today()
    local due = {}
    for id, card in pairs(cards) do
        if card.dueDate and card.dueDate <= today then
            due[#due + 1] = { id = id, card = card }
        end
    end
    return due
end

local function GetNewCards()
    InitCards()
    local db = Store.DB()
    local cards = db.wordReview.cards
    local newCards = {}
    for id, card in pairs(cards) do
        if card.interval == 0 and card.repetitions == 0 then
            newCards[#newCards + 1] = { id = id, card = card }
        end
    end
    return newCards
end

local function Shuffle(arr)
    for i = #arr, 2, -1 do
        local j = math.random(i)
        arr[i], arr[j] = arr[j], arr[i]
    end
end

--- 一轮 session：到期卡优先，新卡补位，同日卡片随机打乱。
local function BuildSession(maxCards)
    maxCards = maxCards or SESSION_MAX
    local pool = {}
    local due = GetDueCards()
    local newCards = GetNewCards()
    local seen = {}
    for i = 1, #due do pool[#pool + 1] = due[i] end
    for i = 1, #due do seen[due[i].id] = true end
    for i = 1, #newCards do
        if not seen[newCards[i].id] then
            pool[#pool + 1] = newCards[i]
            seen[newCards[i].id] = true
        end
    end
    Shuffle(pool)

    if #pool > maxCards then
        local truncated = {}
        for i = 1, maxCards do truncated[i] = pool[i] end
        pool = truncated
    end
    return pool
end

--- quality: 5=知道, 3=模糊, 1=不知道。
local function ReviewCard(id, quality)
    InitCards()
    local db = Store.DB()
    local card = db.wordReview.cards[id]
    if not card then return end

    local q = tonumber(quality) or 1
    local ef = card.easeFactor or INITIAL_EF

    if q >= 3 then
        card.repetitions = (card.repetitions or 0) + 1
        if card.repetitions == 1 then
            card.interval = 1
        elseif card.repetitions == 2 then
            card.interval = 6
        else
            card.interval = math.max(1, math.floor(card.interval * ef + 0.5))
        end
    else
        card.repetitions = 0
        card.interval = 1
    end

    ef = ef + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02))
    card.easeFactor = math.max(MIN_EF, ef)
    card.dueDate = AddDays(Today(), card.interval)
end

local function GetStats()
    InitCards()
    local db = Store.DB()
    local cards = db.wordReview.cards
    local stats = db.wordReview.stats or {}
    local today = Today()

    local mastered = 0
    local total = 0
    local dueCount = 0
    for _, card in pairs(cards) do
        total = total + 1
        if card.interval >= MASTERED_THRESHOLD then
            mastered = mastered + 1
        end
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

local function MarkReviewed()
    local db = Store.DB()
    if not db.wordReview then db.wordReview = {} end
    if not db.wordReview.stats then db.wordReview.stats = {} end

    local stats = db.wordReview.stats
    local today = Today()
    local last = stats.lastReviewDate

    if last ~= today then
        if last == AddDays(today, -1) then
            stats.streak = (stats.streak or 0) + 1
        else
            stats.streak = 1
        end
    end
    stats.lastReviewDate = today
    stats.totalReviewed = (stats.totalReviewed or 0) + 1
end

local function HasWork()
    InitCards()
    local db = Store.DB()
    local cards = db.wordReview.cards
    local today = Today()
    for _, card in pairs(cards) do
        if (card.dueDate and card.dueDate <= today)
            or (card.interval == 0 and card.repetitions == 0) then
            return true
        end
    end
    return false
end

local function IsEnabled()
    local db = Store.DB()
    return db.wordReview and db.wordReview.enabled or false
end

local function SetEnabled(flag)
    local db = Store.DB()
    if not db.wordReview then db.wordReview = {} end
    db.wordReview.enabled = flag and true or false
end

--- 老存档没有 settings.audioAutoPlay 时按默认开启。
local function GetAudioAutoPlay()
    local db = Store.DB()
    if db.wordReview and db.wordReview.settings and db.wordReview.settings.audioAutoPlay ~= nil then
        return db.wordReview.settings.audioAutoPlay
    end
    return true
end

local function SetAudioAutoPlay(flag)
    local db = Store.DB()
    if not db.wordReview then db.wordReview = {} end
    if not db.wordReview.settings then db.wordReview.settings = {} end
    db.wordReview.settings.audioAutoPlay = flag and true or false
end

local function FindEntry(id)
    return Words.GetByID(id)
end

_G.TJ_WordReview = {
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
    GetAudioAutoPlay = GetAudioAutoPlay,
    SetAudioAutoPlay = SetAudioAutoPlay,
    FindEntry = FindEntry,
    Today = Today,
}
