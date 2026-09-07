-- ui_dict.lua
--- 单词词典 Tab：搜索 + 分类筛选 + 分页列表 + 展开详情（含播放）。
--- 只用 TJ_* 系列导出，无外部依赖。

local ADDON_NAME = ...
local Words = _G.TJ_Words
local W = _G.TJ_Widgets

-- 布局常量
local PAD = 12
local ROW_H = 24
local MIN_ROWS = 6
local SEARCH_H = 24
local FILTER_H = 22
local DETAIL_H = 48
local NAV_H = 20
local BTN_GAP = 4

-- 分类
local CATEGORIES = {
    { key = "all",     label = "全部" },
    { key = "item",    label = "物品" },
    { key = "spell",   label = "法术" },
    { key = "zone",    label = "区域" },
    { key = "general", label = "通用" },
}

local CATEGORY_LABELS = {
    item    = "物品",
    spell   = "法术",
    zone    = "区域",
    general = "通用",
}

--- 单词音频路径（S4 生成后自动可用，当前无文件则静默失败）。
local function WordSoundPath(id)
    return "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\sound\\words\\" .. id .. ".mp3"
end

--- 创建词典面板。parent 是 Tab 容器的内容区 frame。
local function CreateDictPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- 状态
    local searchText = ""
    local activeCategory = "all"
    local page = 1
    local selectedId = nil
    local pageRows = MIN_ROWS

    -- 筛选后的结果缓存
    local filtered = {}

    -- forward declarations：闭包在声明之前就引用了这三个刷新函数，没有这组声明
    -- 就会拿到全局 nil，点击时直接报 attempt to call nil。
    local RefreshFilterButtons, RefreshDict, RefreshDetail

    -- 子帧引用
    local searchBox
    local catButtons = {}
    local rowButtons = {}
    local pageLabel
    local prevBtn, nextBtn
    local detailFrame
    local detailKanji, detailSub, detailEnglish, detailCat
    local playBtn
    local emptyText

    ----------------------------------------------------------------
    -- 搜索框
    ----------------------------------------------------------------
    local searchRow = CreateFrame("Frame", nil, panel)
    searchRow:SetHeight(SEARCH_H)
    searchRow:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
    searchRow:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)

    searchBox = CreateFrame("EditBox", nil, searchRow, BackdropTemplateMixin and "BackdropTemplate" or nil)
    searchBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    searchBox:SetBackdropColor(0, 0, 0, .5)
    searchBox:SetBackdropBorderColor(.3, .3, .3, 1)
    searchBox:SetHeight(SEARCH_H)
    searchBox:SetPoint("LEFT", searchRow, "LEFT", 0, 0)
    searchBox:SetPoint("RIGHT", searchRow, "RIGHT", -70, 0)
    searchBox:SetFontObject(GameFontHighlightSmall)
    searchBox:SetTextInsets(6, 6, 0, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(self)
        searchText = self:GetText()
        page = 1
        RefreshDict()
    end)

    local searchLabel = searchRow:CreateFontString(nil, "OVERLAY")
    W.ApplyFont(searchLabel, 10)
    searchLabel:SetPoint("RIGHT", searchRow, "RIGHT", 0, 0)
    searchLabel:SetText("搜索")
    searchLabel:SetTextColor(.6, .6, .6)

    ----------------------------------------------------------------
    -- 分类筛选按钮
    ----------------------------------------------------------------
    local filterRow = CreateFrame("Frame", nil, panel)
    filterRow:SetHeight(FILTER_H)
    filterRow:SetPoint("TOPLEFT", searchRow, "BOTTOMLEFT", 0, -2)
    filterRow:SetPoint("TOPRIGHT", searchRow, "BOTTOMRIGHT", 0, -2)

    local btnX = 0
    for i = 1, #CATEGORIES do
        local info = CATEGORIES[i]
        local btn = W.CreateButton(filterRow)
        btn:SetSize(46, FILTER_H - 2)
        btn:SetPoint("LEFT", filterRow, "LEFT", btnX, 0)
        btn:SetText(info.label)
        btn.__catKey = info.key
        btn:SetScript("OnClick", function(self)
            activeCategory = self.__catKey
            page = 1
            RefreshFilterButtons()
            RefreshDict()
        end)
        catButtons[i] = btn
        btnX = btnX + 46 + BTN_GAP
    end

    RefreshFilterButtons = function()
        for i = 1, #catButtons do
            local btn = catButtons[i]
            btn:SetVisualState(btn.__catKey == activeCategory and "selected" or "muted")
        end
    end

    ----------------------------------------------------------------
    -- 列表区
    ----------------------------------------------------------------
    local listTop = PAD + SEARCH_H + 2 + FILTER_H + 2
    local panelHeight = panel:GetHeight()
    if panelHeight > 0 then
        local bottomChrome = PAD + DETAIL_H + BTN_GAP + NAV_H + BTN_GAP
        local availableHeight = panelHeight - listTop - bottomChrome
        pageRows = math.max(MIN_ROWS, math.floor((availableHeight + BTN_GAP) / (ROW_H + BTN_GAP)))
    end

    local listArea = CreateFrame("Frame", nil, panel)
    listArea:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -listTop)
    listArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -listTop)
    listArea:SetHeight(pageRows * (ROW_H + BTN_GAP) - BTN_GAP)

    -- 懒创建列表行
    for i = 1, pageRows do
        local row = W.CreateButton(listArea)
        row:SetSize(1, ROW_H)
        row.__entry = nil
        rowButtons[i] = row

        -- 左侧主文字（kanji + reading）
        local mainText = row:CreateFontString(nil, "OVERLAY")
        W.ApplyFont(mainText, 11)
        mainText:SetPoint("LEFT", row, "LEFT", 6, 0)
        mainText:SetJustifyH("LEFT")
        row.mainText = mainText

        -- 右侧分类标签
        local catText = row:CreateFontString(nil, "OVERLAY")
        W.ApplyFont(catText, 9)
        catText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        catText:SetTextColor(.5, .5, .5)
        row.catText = catText

        row:SetScript("OnClick", function(self)
            if self.__entry then
                selectedId = self.__entry.id
                RefreshDetail()
            end
        end)
    end

    -- 空结果提示
    emptyText = listArea:CreateFontString(nil, "OVERLAY")
    W.ApplyFont(emptyText, 11)
    emptyText:SetPoint("CENTER", listArea, "CENTER")
    emptyText:SetText("未找到匹配词条")
    emptyText:SetTextColor(.5, .5, .5)
    emptyText:Hide()

    ----------------------------------------------------------------
    -- 分页
    ----------------------------------------------------------------
    local navRow = CreateFrame("Frame", nil, panel)
    navRow:SetHeight(20)
    navRow:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD + DETAIL_H + 4)
    navRow:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD + DETAIL_H + 4)

    prevBtn = W.CreateButton(navRow)
    prevBtn:SetSize(22, 18)
    prevBtn:SetPoint("LEFT", navRow, "LEFT", 0, 0)
    prevBtn:SetText("<")
    prevBtn:SetScript("OnClick", function()
        if page > 1 then
            page = page - 1
            RefreshDict()
        end
    end)

    pageLabel = navRow:CreateFontString(nil, "OVERLAY")
    W.ApplyFont(pageLabel, 10)
    pageLabel:SetPoint("CENTER", navRow, "CENTER")
    pageLabel:SetTextColor(.7, .7, .7)

    nextBtn = W.CreateButton(navRow)
    nextBtn:SetSize(22, 18)
    nextBtn:SetPoint("RIGHT", navRow, "RIGHT", 0, 0)
    nextBtn:SetText(">")
    nextBtn:SetScript("OnClick", function()
        local totalPages = math.max(1, math.ceil(#filtered / pageRows))
        if page < totalPages then
            page = page + 1
            RefreshDict()
        end
    end)

    ----------------------------------------------------------------
    -- 详情面板（懒创建）
    ----------------------------------------------------------------
    local function EnsureDetailFrame()
        if detailFrame then return end
        detailFrame = CreateFrame("Frame", nil, panel, BackdropTemplateMixin and "BackdropTemplate" or nil)
        detailFrame:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 },
        })
        detailFrame:SetBackdropColor(.08, .08, .08, .8)
        detailFrame:SetBackdropBorderColor(.3, .3, .3, .8)
        detailFrame:SetHeight(DETAIL_H)
        detailFrame:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD)
        detailFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)

        detailKanji = detailFrame:CreateFontString(nil, "OVERLAY")
        W.ApplyFont(detailKanji, 14)
        detailKanji:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 8, -6)
        detailKanji:SetTextColor(1, .82, 0)

        detailSub = detailFrame:CreateFontString(nil, "OVERLAY")
        W.ApplyFont(detailSub, 10)
        detailSub:SetPoint("TOPLEFT", detailKanji, "BOTTOMLEFT", 0, -2)
        detailSub:SetTextColor(.65, .65, .65)

        detailEnglish = detailFrame:CreateFontString(nil, "OVERLAY")
        W.ApplyFont(detailEnglish, 11)
        detailEnglish:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -52, -6)
        detailEnglish:SetTextColor(1, 1, 1)

        detailCat = detailFrame:CreateFontString(nil, "OVERLAY")
        W.ApplyFont(detailCat, 9)
        detailCat:SetPoint("TOPRIGHT", detailEnglish, "BOTTOMRIGHT", 0, -2)
        detailCat:SetTextColor(.5, .5, .5)

        playBtn = W.CreateButton(detailFrame)
        playBtn:SetSize(20, 20)
        playBtn:SetPoint("BOTTOMRIGHT", detailFrame, "BOTTOMRIGHT", -6, 4)
        local playIcon = playBtn:CreateTexture(nil, "ARTWORK")
        playIcon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon\\play")
        playIcon:SetSize(12, 12)
        playIcon:SetPoint("CENTER", playBtn, "CENTER")
        playBtn:SetScript("OnClick", function()
            if selectedId then
                PlaySoundFile(WordSoundPath(selectedId), "Master")
            end
        end)
    end

    RefreshDetail = function()
        if not selectedId then
            if detailFrame then detailFrame:Hide() end
            return
        end
        local entry = Words.GetByID(selectedId)
        if not entry then
            if detailFrame then detailFrame:Hide() end
            return
        end
        EnsureDetailFrame()
        detailKanji:SetText(entry.kanji .. "  " .. entry.reading)
        detailSub:SetText(entry.romaji)
        detailEnglish:SetText(entry.english)
        detailCat:SetText(CATEGORY_LABELS[entry.category] or entry.category)
        detailFrame:Show()
    end

    ----------------------------------------------------------------
    -- 筛选 + 渲染
    ----------------------------------------------------------------
    local function ApplyFilter()
        filtered = {}
        local data = Words.GetData()
        local q = string.lower(searchText)
        for i = 1, #data do
            local w = data[i]
            -- 分类
            if activeCategory == "all" or w.category == activeCategory then
                -- 搜索
                if q == "" then
                    filtered[#filtered + 1] = w
                else
                    if string.find(string.lower(w.kanji), q, 1, true)
                        or string.find(string.lower(w.reading), q, 1, true)
                        or string.find(string.lower(w.romaji), q, 1, true)
                        or string.find(string.lower(w.english), q, 1, true) then
                        filtered[#filtered + 1] = w
                    end
                end
            end
        end
    end

    RefreshDict = function()
        ApplyFilter()
        local total = #filtered
        local totalPages = math.max(1, math.ceil(total / pageRows))
        if page > totalPages then page = totalPages end

        -- 列表行渲染
        local offset = (page - 1) * pageRows
        local hasResults = total > 0
        local listWidth = math.max(1, panel:GetWidth() - PAD * 2)

        for i = 1, pageRows do
            local row = rowButtons[i]
            local dataIndex = offset + i
            local entry = hasResults and filtered[dataIndex] or nil

            if entry then
                row.__entry = entry
                row:SetSize(listWidth, ROW_H)
                row:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, -(i - 1) * (ROW_H + BTN_GAP))
                row.mainText:SetText(entry.kanji .. "  " .. entry.reading .. "  " .. entry.english)
                row.catText:SetText(CATEGORY_LABELS[entry.category] or entry.category)
                row:Show()
            else
                row.__entry = nil
                row:Hide()
            end
        end

        -- 空结果
        emptyText:SetShown(not hasResults)

        -- 分页
        pageLabel:SetText(page .. " / " .. totalPages)
        prevBtn:SetEnabled(page > 1)
        nextBtn:SetEnabled(page < totalPages)

        -- 详情
        if selectedId then
            local found = false
            for i = 1, total do
                if filtered[i].id == selectedId then
                    found = true
                    break
                end
            end
            if not found then selectedId = nil end
        end
        RefreshDetail()
    end

    -- 面板初始状态
    RefreshFilterButtons()
    RefreshDict()

    --- Tab 切过来时刷新。
    function panel:OnShow()
        RefreshFilterButtons()
        RefreshDict()
    end

    panel:SetScript("OnShow", panel.OnShow)

    return panel
end

_G.TJ_DictUI = {
    CreateDictPanel = CreateDictPanel,
}
