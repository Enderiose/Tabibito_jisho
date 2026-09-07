-- journal.lua
--- 冒险家手账：把冷数据讲成一段话。
---
--- 为什么不在登出时讲（旅店/主城小退不读条这件事只是表象）：
---   1. PLAYER_LOGOUT 触发时客户端已经在拆 UI，此刻 CreateFrame 是禁止操作，讲不出来；
---   2. 休息区小退不读条，从事件到进程结束只有一瞬，重活既来不及做也没人看得见；
---   3. 野外那 20 秒读条，玩家的注意力已经在"退出"上了，弹什么都是打扰。
--- 所以登出只落一个 ended 时间戳（就一个数字，任何退出路径都写得起），
--- "讲"这件事推迟到下一次登录。附带好处：崩溃和强退根本不触发 PLAYER_LOGOUT，
--- 靠心跳 lastSeen 封口照样能讲出上一次，只是标一句异常退出。

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil
local NEW_SECONDS = GetServerTime or time
local Store = _G.TJ_Store

local Widgets = _G.TJ_Widgets
local MAX_HISTORY = 20

local HEARTBEAT_SECONDS = 60
-- 短于这个时长的会话不讲：切号看一眼就走也会产生会话，句句都弹等于没有日记。
local MIN_TELL_SECONDS = 300
local MAIN_BACKGROUND_COLOR = { 0.015, 0.03, 0.07 }


local frame = nil
-- ---- 数据层 ----

--- 存档走 TJ_LangDB（store.lua 提供），手账挂在 journal 顶层。
local function NowSeconds()
    return NEW_SECONDS()
end

local function CharacterKey()
    local name, realm = UnitName("player")
    return (realm or GetRealmName() or "Unknown") .. "-" .. (name or "Unknown")
end

local function JournalRoot()
    local data = Store and Store.DB and Store.DB()
    if type(data) ~= "table" then return nil end
    if type(data.journal) ~= "table" then data.journal = {} end
    return data.journal
end

local function CharacterJournal()
    local root = JournalRoot()
    if not root then return nil end
    local key = CharacterKey()
    if not key then return nil end
    if type(root[key]) ~= "table" then root[key] = { history = {} } end
    if type(root[key].history) ~= "table" then root[key].history = {} end
    return root[key]
end

local function Session()
    local journal = CharacterJournal()
    return journal and type(journal.pending) == "table" and journal.pending or nil
end

--- 登录弹窗开关。存在 data.journal 下而不是 data.settings 里：settings 归主插件的设置页管，
--- 手账是自带的东西，开关也自己收着，将来挪出去不用去 settings 里挑出来。
local function IsEnabled()
    local root = JournalRoot()
    return not root or root.enabled ~= false
end

local function SetEnabled(enabled)
    local root = JournalRoot()
    if root then root.enabled = enabled end
end

local function StartSession()
    local journal = CharacterJournal()
    if not journal then return end

    local now = NowSeconds()
    local zone = GetZoneText()
    local level = UnitLevel("player")

    journal.pending = {
        start = now,
        lastSeen = now,
        ended = nil,
        zone = zone,
        zones = zone ~= "" and { zone } or {},
        zoneSeen = zone ~= "" and { [zone] = true } or {},
        kills = 0,
        bosses = {},
        moneyStart = GetMoney() or 0,
        moneyEnd = GetMoney() or 0,
        levelStart = level,
        levelEnd = level,
    }
end

--- 登出时唯一要做的事：写一个数字。别的都在登录侧算。
local function CloseSession()
    local session = Session()
    if not session then return end
    session.ended = NowSeconds()
    session.lastSeen = session.ended
    session.levelEnd = UnitLevel("player")
    session.moneyEnd = GetMoney() or session.moneyEnd
end

-- ---- 文本生成 ----

local function FormatDuration(seconds)
    seconds = tonumber(seconds) or 0
    if seconds < 60 then return string.format("%d秒", seconds) end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then return string.format("%d分钟", minutes) end
    local hours = math.floor(minutes / 60)
    local rest = minutes % 60
    if rest == 0 then return string.format("%d小时", hours) end
    return string.format("%d小时%d分", hours, rest)
end

--- 金币差只取整金：手账是给"这趟赚了多少"一个量级感，精确到银铜反而啰嗦。
local function FormatGoldDelta(copper)
    local delta = tonumber(copper) or 0
    if delta == 0 then return nil end
    local gold = math.floor(math.abs(delta) / 10000)
    if gold == 0 then return nil end
    local sign = delta > 0 and "+" or "-"
    local color = delta > 0 and "|cffffd200" or "|cffff6b6b"
    return color .. sign .. gold .. "金|r"
end

--- 把一段会话讲成几行。只讲发生变化的事，没打首领就不提首领，金币没动就不提金币。
local function ComposeEntry(session, ended, crashed)
    local lines = {}
    local duration = math.max(0, (tonumber(ended) or session.start) - (tonumber(session.start) or 0))
    if duration < MIN_TELL_SECONDS then return lines end

    -- 显示层用本地时区解释服务器时间戳，跟玩家对"今天几号"的直觉对齐；
    -- 写入与比较一律走 DB.NowSeconds()，不在这里另起一套时间源（红线 8）。
    local dateText = date("%m月%d日", session.start) or ""
    local zone = session.zone
    if type(zone) ~= "string" or zone == "" then zone = "艾泽拉斯" end

    local head = string.format("|cffffd200【%s】|r 你在 |cff00ff00%s|r 停留了 |cffffd200%s|r",
        dateText, zone, FormatDuration(duration))
    if crashed then head = head .. "  |cff888888（上次异常退出）|r" end
    lines[#lines + 1] = head

    local kills = tonumber(session.kills) or 0
    if kills > 0 then
        local detail = ""
        local bosses = session.bosses
        if type(bosses) == "table" and #bosses > 0 then
            detail = "（" .. table.concat(bosses, "、") .. "）"
        end
        lines[#lines + 1] = string.format("  击败首领 |cffffd200%d|r 次%s", kills, detail)
    end

    local gold = FormatGoldDelta((tonumber(session.moneyEnd) or 0) - (tonumber(session.moneyStart) or 0))
    if gold then lines[#lines + 1] = "  金币 " .. gold end

    local levelStart, levelEnd = tonumber(session.levelStart), tonumber(session.levelEnd)
    if levelStart and levelEnd and levelEnd > levelStart then
        lines[#lines + 1] = string.format("  等级 |cff00ff00%d → %d|r", levelStart, levelEnd)
    end

    local zones = session.zones
    if type(zones) == "table" and #zones > 1 then
        lines[#lines + 1] = "  足迹 " .. table.concat(zones, " → ")
    end

    return lines
end

-- ---- UI ----

local JOURNAL_WIDTH = 460
local JOURNAL_MIN_H = 180
local JOURNAL_MAX_H = 420
local JOURNAL_HEADER_H = 44
local JOURNAL_BTN_H = 48
local JOURNAL_PAD = 26

local currentIndex = 1

local function BuildFrame()
    local panel = CreateFrame("Frame", "TJ_JournalFrame", UIParent, BACKDROP_TEMPLATE)
    panel:SetSize(JOURNAL_WIDTH, JOURNAL_MIN_H)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)

    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 3,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        panel:SetBackdropColor(MAIN_BACKGROUND_COLOR[1], MAIN_BACKGROUND_COLOR[2],
            MAIN_BACKGROUND_COLOR[3], 0.85)
    end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("冒险家手账")
    panel.title = title

    -- 内容区滚动
    -- 这个客户端的基础 ScrollFrameTemplate 也会带出可见滚动条，所以用裸 ScrollFrame + 手动滚轮。
    local scrollFrame = CreateFrame("ScrollFrame", "TJ_JournalScrollFrame", panel)
    scrollFrame:SetPoint("TOPLEFT", JOURNAL_PAD, -JOURNAL_HEADER_H)
    scrollFrame:SetPoint("RIGHT", -JOURNAL_PAD, 0)
    scrollFrame:SetPoint("BOTTOM", 0, JOURNAL_BTN_H)
    panel.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(JOURNAL_WIDTH - JOURNAL_PAD * 2)
    scrollFrame:SetScrollChild(scrollChild)
    panel.scrollChild = scrollChild
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, scrollChild:GetHeight() - scrollFrame:GetHeight())
        local offset = math.max(0, math.min(scrollFrame:GetVerticalScroll() - delta * 24, maxOffset))
        scrollFrame:SetVerticalScroll(offset)
    end)

    local content = scrollChild:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    content:SetPoint("TOPLEFT", 0, 0)
    content:SetPoint("RIGHT", 0, 0)
    content:SetJustifyH("LEFT")
    content:SetJustifyV("TOP")
    content:SetNonSpaceWrap(true)
    panel.content = content

    -- 按钮行：统一 Widgets 皮肤
    local prevButton = Widgets.CreateButton(panel)
    prevButton:SetSize(88, 24)
    prevButton:SetPoint("BOTTOMLEFT", JOURNAL_PAD, 12)
    prevButton:SetText("上一条")
    prevButton:SetScript("OnClick", function()
        if currentIndex > 1 then
            currentIndex = currentIndex - 1
            panel:UpdateDisplay()
        end
    end)
    panel.prevButton = prevButton

    local closeButton = Widgets.CreateButton(panel)
    closeButton:SetSize(88, 24)
    closeButton:SetPoint("BOTTOM", 0, 12)
    closeButton:SetText("知道了")
    closeButton:SetScript("OnClick", function() panel:Hide() end)

    local nextButton = Widgets.CreateButton(panel)
    nextButton:SetSize(88, 24)
    nextButton:SetPoint("BOTTOMRIGHT", -JOURNAL_PAD, 12)
    nextButton:SetText("下一条")
    nextButton:SetScript("OnClick", function()
        local journal = CharacterJournal()
        local max = journal and #journal.history or 0
        if currentIndex < max then
            currentIndex = currentIndex + 1
            panel:UpdateDisplay()
        end
    end)
    panel.nextButton = nextButton

    function panel:UpdateDisplay()
        local journal = CharacterJournal()
        local history = journal and journal.history or {}
        local max = #history
        if max == 0 then
            self.content:SetText("|cff888888当前数据为空，游玩后自动记录。冒险家手账会在每次登录时讲述上一次的冒险故事。|r")
            self.prevButton:Hide()
            self.nextButton:Hide()
            self.title:SetText("冒险家手账")
            self:SetHeight(JOURNAL_MIN_H)
            return
        end
        if currentIndex < 1 then currentIndex = 1 end
        if currentIndex > max then currentIndex = max end
        self.content:SetText(history[currentIndex].text or "")
        self.title:SetText(string.format("冒险家手账（%d/%d）", currentIndex, max))
        self.prevButton:SetShown(currentIndex > 1)
        self.nextButton:SetShown(currentIndex < max)
        C_Timer.After(0, function()
            local contentH = self.content:GetStringHeight() or 0
            local totalH = JOURNAL_HEADER_H + contentH + JOURNAL_BTN_H + 16
            totalH = math.max(JOURNAL_MIN_H, math.min(totalH, JOURNAL_MAX_H))
            self:SetHeight(totalH)
            self.scrollChild:SetHeight(contentH + 8)
            self.scrollFrame:UpdateScrollChildRect()
        end)
    end

    return panel
end

--- 全量显示（登录讲述用，不走单条导航）
local function ShowLines(lines)
    if not frame then frame = BuildFrame() end
    frame.content:SetText(table.concat(lines, "\n"))
    frame.title:SetText("冒险家手账")
    frame.prevButton:Hide()
    frame.nextButton:Hide()
    C_Timer.After(0, function()
        local contentH = frame.content:GetStringHeight() or 0
        local totalH = JOURNAL_HEADER_H + contentH + JOURNAL_BTN_H + 16
        totalH = math.max(JOURNAL_MIN_H, math.min(totalH, JOURNAL_MAX_H))
        frame:SetHeight(totalH)
        frame.scrollChild:SetHeight(contentH + 8)
        frame.scrollFrame:UpdateScrollChildRect()
    end)
end

--- 单条历史浏览（/journal 和手账按钮调用）
local function ShowHistory(startIndex)
    if not frame then frame = BuildFrame() end
    currentIndex = startIndex or 1
    frame:UpdateDisplay()
    frame:Show()
end

--- 欢迎窗还开着就先不弹
local function ShowWhenClear(lines, attempts)
    ShowLines(lines)
end
-- ---- 讲述 ----

local function Archive(journal, session, lines)
    local entry = {
        start = session.start,
        ended = session.ended or session.lastSeen or session.start,
        text = table.concat(lines, "\n"),
    }
    table.insert(journal.history, 1, entry)
    while #journal.history > MAX_HISTORY do
        table.remove(journal.history, #journal.history)
    end
end

local function TellPreviousSession()
    local journal = CharacterJournal()
    if not journal then return end

    local session = journal.pending
    if type(session) ~= "table" or not session.start then return end

    local ended = session.ended
    local crashed = false
    if not ended then
        -- 没有 ended 说明 PLAYER_LOGOUT 没跑成（崩溃/强退/进程被杀），用心跳时间封口。
        ended = session.lastSeen or session.start
        crashed = true
    end

    local lines = ComposeEntry(session, ended, crashed)
    if #lines > 0 then
        -- 不管弹不弹都存档：关掉弹窗的人照样能在 /journal 里翻到。
        Archive(journal, session, lines)
        if IsEnabled() then ShowWhenClear(lines) end
    end

    -- 无论讲没讲，上一次会话到此为止，pending 马上会被 StartSession 覆盖。
    journal.pending = nil
end

-- ---- 事件 ----
--- 这个帧刻意独立于 options.lua 的事件帧：那边有一套 DB_WRITE_EVENTS 落库白名单，
--- 管的是"要不要 SaveCurrentCharacter + RefreshOverview"；这里是会话级别的轻量采集，
--- 只改内存里的 SavedVariables 表，落盘交给客户端在退出时统一做，不进那套白名单。

local tracker = CreateFrame("Frame")
tracker:RegisterEvent("PLAYER_LOGIN")
tracker:RegisterEvent("PLAYER_LOGOUT")
tracker:RegisterEvent("PLAYER_MONEY")
tracker:RegisterEvent("PLAYER_LEVEL_UP")
tracker:RegisterEvent("BOSS_KILL")
tracker:RegisterEvent("ZONE_CHANGED_NEW_AREA")

--- BOSS_KILL 的参数随客户端版本变过（encounterID+name 与旧式的 boss 名顺序都出现过），
--- 与其猜下标，不如取第一个非空字符串。
local function FirstStringArg(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "string" and value ~= "" then return value end
    end
    return nil
end

local function NoteZone()
    local session = Session()
    if not session then return end
    local zone = GetZoneText()
    if type(zone) ~= "string" or zone == "" then return end
    session.zone = zone
    session.zoneSeen = type(session.zoneSeen) == "table" and session.zoneSeen or {}
    if not session.zoneSeen[zone] then
        session.zoneSeen[zone] = true
        session.zones = type(session.zones) == "table" and session.zones or {}
        session.zones[#session.zones + 1] = zone
    end
end

tracker:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        -- 先讲上一次，再开新的：顺序反了会被 StartSession 覆盖掉还没讲的会话。
        -- 延迟 1.5 秒是为了错开登录峰值，避免和主插件/其他插件的登录弹窗挤在一起。
        C_Timer.After(1.5, function()
            TellPreviousSession()
            StartSession()
        end)
    elseif event == "PLAYER_LOGOUT" then
        CloseSession()
    elseif event == "PLAYER_MONEY" then
        local session = Session()
        if session then session.moneyEnd = GetMoney() or session.moneyEnd end
    elseif event == "PLAYER_LEVEL_UP" then
        local session = Session()
        if session then session.levelEnd = UnitLevel("player") or session.levelEnd end
    elseif event == "BOSS_KILL" then
        local session = Session()
        if session then
            session.kills = (tonumber(session.kills) or 0) + 1
            local name = FirstStringArg(...)
            if name then
                session.bosses = type(session.bosses) == "table" and session.bosses or {}
                session.bosses[#session.bosses + 1] = name
            end
        end
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        NoteZone()
    end
end)

-- 心跳：崩溃和强退下 PLAYER_LOGOUT 不触发，靠它给会话封口。
C_Timer.NewTicker(HEARTBEAT_SECONDS, function()
    local session = Session()
    if session then session.lastSeen = NowSeconds() end
end)

--- 供 /jisho sz 调用
_G.TJ_JournalShow = function() ShowHistory(1) end

--- 供设置入口调用，同步启用状态 + 打印反馈
_G.TJ_JournalSetEnabled = function(enabled)
    SetEnabled(enabled)
    if enabled then
        print("|cff00BFFF冒险家手账|r：恢复登录时自动弹出。")
    else
        print("|cff00BFFF冒险家手账|r：登录时不再自动弹出，用 /journal 随时翻看。")
    end
end

tinsert(UISpecialFrames, "TJ_JournalFrame")
