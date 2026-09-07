-- ui_kana.lua
--- 旅人辞典面板：Tab 容器（五十音 | 复习），五十音盘网格 + SM-2 闪卡复习。

local ADDON_NAME = ...
local Kana = _G.TJ_Kana
local W = _G.TJ_Widgets
local Store = _G.TJ_Store
local ReviewUI = _G.TJ_ReviewUI
local DictUI = _G.TJ_DictUI
local WordReviewUI = _G.TJ_WordReviewUI

local FRAME_NAME = "TJ_MainFrame"

local COLS = 5
local TILE_W = 54
local TILE_H = 48
local GAP = 2
local PAD = 14
local TITLE_H = 30
local TOOLBAR_H = 26
local HEADER_H = 18
local TAB_BTN_W = 52
-- 发音高亮保持多久。音频是 -20% 语速念的单音节，实测 0.6~0.9 秒，留 1 秒足够盖住。
local ACTIVE_SECONDS = 1.0

local panel = nil
local tiles = {} -- { tile = 按钮, cell = 数据表条目, row = 所在行 }
local activeTile = nil
local activeToken = 0
local showKatakana = false
local activeTab = "kana" -- "kana" | "review" | "dict" | "word"
local kanaContent = nil
local reviewContent = nil
local dictContent = nil
local wordContent = nil
local tabButtons = {}
local modeButtonRef = nil

--- 音频路径。用 ADDON_NAME 拼而不是写死插件目录名：将来拆分改名，这里不用跟着改。
local function SoundPath(romaji)
    return "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\sound\\lang\\" .. romaji .. ".mp3"
end

local function ClearActive()
    if not activeTile then return end
    activeTile.__TJActive = false
    activeTile:SetTileState("normal")
    activeTile = nil
end

--- 念一个音节。连点时后一次会盖掉前一次的高亮：靠 activeToken 比对，
--- 不做定时器取消——C_Timer.After 在老客户端上拿不到可 Cancel 的句柄，token 方案兼容性更好。
local function Play(cell, tile)
    ClearActive()
    PlaySoundFile(SoundPath(cell.r), "Master")

    activeTile = tile
    tile.__TJActive = true
    tile:SetTileState("active")

    activeToken = activeToken + 1
    local token = activeToken
    C_Timer.After(ACTIVE_SECONDS, function()
        if token ~= activeToken then return end
        ClearActive()
    end)
end

local function RefreshTiles()
    for index = 1, #tiles do
        local entry = tiles[index]
        entry.tile.kana:SetText(showKatakana and entry.cell.k or entry.cell.h)
    end
end

local function RestorePosition(frame)
    local saved = Store.DB().kana and Store.DB().kana.point
    frame:ClearAllPoints()
    if type(saved) == "table" and saved.point then
        frame:SetPoint(saved.point, UIParent, saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER")
    end
end

--- 更新 Tab 按钮外观。
local function RefreshTabButtons()
    for key, btn in pairs(tabButtons) do
        btn:SetVisualState(key == activeTab and "selected" or "muted")
    end
end

--- 切换 Tab。
local function SwitchTab(tab)
    if activeTab == tab then return end
    activeTab = tab
    if kanaContent then kanaContent:SetShown(tab == "kana") end
    if reviewContent then reviewContent:SetShown(tab == "review") end
    if dictContent then dictContent:SetShown(tab == "dict") end
    if wordContent then wordContent:SetShown(tab == "word") end
    if modeButtonRef then modeButtonRef:SetShown(tab == "kana") end
    RefreshTabButtons()
    -- 复习 tab 显示时刷新
    if tab == "review" and reviewContent and reviewContent.OnShow then
        reviewContent:OnShow()
    end
    if tab == "dict" and dictContent and dictContent.OnShow then
        dictContent:OnShow()
    end
    if tab == "word" and wordContent and wordContent.OnShow then
        wordContent:OnShow()
    end
end

local function BuildPanel()
    local rows = #Kana.ROWS
    local baseGridW = COLS * TILE_W + (COLS - 1) * GAP
    local gridH = rows * TILE_H + (rows - 1) * GAP

    -- 四个标签 + 右侧关闭/假名模式按钮同排，窗口宽度取网格与工具条的较大值。
    local rightClusterW = 78 + 6 + 22
    local tabRowW = 4 * TAB_BTN_W + 3 * 4
    local frameW = math.max(baseGridW + PAD * 2, PAD + tabRowW + 10 + rightClusterW + PAD)
    -- 四个标签之间用 3 个等距间隔铺开，右侧仍保留 10px 与按钮簇的缓冲。
    local tabGap = math.max(4, math.floor((frameW - PAD * 2 - rightClusterW - 10 - 4 * TAB_BTN_W) / 3))
    local gridContentH = TOOLBAR_H + HEADER_H + gridH
    local reviewContentH = 320
    local frameH = TITLE_H + math.max(gridContentH, reviewContentH) + PAD * 2
    -- 窗口宽度以工具条为准时，假名列位也按剩余宽度均分，而不是固定 54px 贴左。
    local tileW = math.floor((frameW - PAD * 2 - (COLS - 1) * GAP) / COLS)
    local kanaGridW = COLS * tileW + (COLS - 1) * GAP
    local gridOffsetX = math.floor((frameW - kanaGridW) / 2)

    local frame = W.CreatePanel(UIParent, "旅人辞典 · Tabibito Jisho", FRAME_NAME)
    frame:SetSize(frameW, frameH)
    RestorePosition(frame)

    frame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    frame:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        if point then
            Store.DB().kana.point = { point = point, x = x, y = y }
        end
    end)

    -- 工具条左侧：Tab 按钮
    local tabKanaBtn = W.CreateButton(frame)
    tabKanaBtn:SetSize(TAB_BTN_W, 22)
    tabKanaBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TITLE_H - 4))
    tabKanaBtn:SetText("五十音")
    tabKanaBtn:SetScript("OnClick", function() SwitchTab("kana") end)
    tabButtons.kana = tabKanaBtn

    local tabReviewBtn = W.CreateButton(frame)
    tabReviewBtn:SetSize(TAB_BTN_W, 22)
    tabReviewBtn:SetPoint("LEFT", tabKanaBtn, "RIGHT", tabGap, 0)
    tabReviewBtn:SetText("复习")
    tabReviewBtn:SetScript("OnClick", function() SwitchTab("review") end)
    tabButtons.review = tabReviewBtn

    local tabDictBtn = W.CreateButton(frame)
    tabDictBtn:SetSize(TAB_BTN_W, 22)
    tabDictBtn:SetPoint("LEFT", tabReviewBtn, "RIGHT", tabGap, 0)
    tabDictBtn:SetText("词典")
    tabDictBtn:SetScript("OnClick", function() SwitchTab("dict") end)
    tabButtons.dict = tabDictBtn

    local tabWordBtn = W.CreateButton(frame)
    tabWordBtn:SetSize(TAB_BTN_W, 22)
    tabWordBtn:SetPoint("LEFT", tabDictBtn, "RIGHT", tabGap, 0)
    tabWordBtn:SetText("单词")
    tabWordBtn:SetScript("OnClick", function() SwitchTab("word") end)
    tabButtons.word = tabWordBtn

    -- 工具条右侧：假名模式切换（仅五十音 tab 可见） + 关闭
    local closeButton = W.CreateButton(frame)
    closeButton:SetSize(22, 22)
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -(TITLE_H - 4))
    closeButton:SetText("×")
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    modeButtonRef = W.CreateButton(frame)
    modeButtonRef:SetSize(78, 22)
    modeButtonRef:SetPoint("TOPRIGHT", closeButton, "TOPLEFT", -6, 0)
    modeButtonRef:SetText(showKatakana and "片假名" or "平假名")
    modeButtonRef:SetScript("OnClick", function(self)
        showKatakana = not showKatakana
        Store.DB().kana.katakana = showKatakana
        RefreshTiles()
        self:SetText(showKatakana and "片假名" or "平假名")
    end)

    -- 默认选中五十音 tab
    RefreshTabButtons()

    ----------------------------------------------------------------
    -- 五十音内容区
    ----------------------------------------------------------------
    kanaContent = CreateFrame("Frame", nil, frame)
    kanaContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(TITLE_H + TOOLBAR_H))
    kanaContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

    -- 元音表头，跟每行格位一一对齐。
    local headerTop = 0
    for colIndex = 1, COLS do
        local label = kanaContent:CreateFontString(nil, "OVERLAY")
        W.ApplyFont(label, 11)
        label:SetSize(tileW, HEADER_H)
        label:SetPoint("TOPLEFT", kanaContent, "TOPLEFT",
            gridOffsetX + (colIndex - 1) * (tileW + GAP), headerTop)
        label:SetTextColor(.7, .7, .7)
        label:SetText(Kana.VOWELS[colIndex] or "")
    end

    local gridTop = headerTop - HEADER_H
    for rowIndex = 1, rows do
        local row = Kana.ROWS[rowIndex]
        for colIndex = 1, COLS do
            local cell = row.cells[colIndex]
            if cell then
                local tile = W.CreateTile(kanaContent)
                tile:SetSize(tileW, TILE_H)
                tile:SetPoint("TOPLEFT", kanaContent, "TOPLEFT",
                    gridOffsetX + (colIndex - 1) * (tileW + GAP),
                    gridTop - (rowIndex - 1) * (TILE_H + GAP))
                tile.kana:SetText(showKatakana and cell.k or cell.h)
                tile.romaji:SetText(cell.r)
                tile:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(cell.h .. "  /  " .. cell.k, 1, .82, 0)
                    GameTooltip:AddLine(row.label .. "   .   " .. cell.r, .75, .75, .75)
                    GameTooltip:Show()
                end)
                tile:SetScript("OnClick", function() Play(cell, tile) end)
                tiles[#tiles + 1] = { tile = tile, cell = cell, row = row }
            end
        end
    end

    ----------------------------------------------------------------
    -- 复习内容区
    ----------------------------------------------------------------
    reviewContent = CreateFrame("Frame", nil, frame)
    reviewContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(TITLE_H + TOOLBAR_H))
    reviewContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    reviewContent:Hide()

    if ReviewUI and ReviewUI.CreateReviewPanel then
        ReviewUI.CreateReviewPanel(reviewContent)
    end

    ----------------------------------------------------------------
    -- 词典内容区
    ----------------------------------------------------------------
    dictContent = CreateFrame("Frame", nil, frame)
    dictContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(TITLE_H + TOOLBAR_H))
    dictContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    dictContent:Hide()

    if DictUI and DictUI.CreateDictPanel then
        DictUI.CreateDictPanel(dictContent)
    end

    ----------------------------------------------------------------
    -- 单词复习内容区
    ----------------------------------------------------------------
    wordContent = CreateFrame("Frame", nil, frame)
    wordContent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(TITLE_H + TOOLBAR_H))
    wordContent:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    wordContent:Hide()

    if WordReviewUI and WordReviewUI.CreateWordReviewPanel then
        WordReviewUI.CreateWordReviewPanel(wordContent)
    end

    frame:Hide()
    return frame
end

local function Toggle()
    if not panel then panel = BuildPanel() end
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end

_G.TJ_Panel = {
    Toggle = Toggle,
}
