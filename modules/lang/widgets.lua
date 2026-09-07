-- widgets.lua
--- 模块自带控件工厂。
--- 控件工厂与皮肤探测全部插件内自带，不引用任何外部插件符号；
--- 或上游 BG.* 的引用都是拆分时要一根根剪的线，所以皮肤和字体探测在这里自带一份。
--- 皮肤数值与 core/widgets.lua 保持一致，改了那边记得同步这里。

local BACKDROP_TEMPLATE = BackdropTemplateMixin and "BackdropTemplate" or nil

local BORDER_TEXTURE = "Interface\\ChatFrame\\ChatFrameBackground"
local FILL_TEXTURE = "Interface\\Buttons\\WHITE8x8"
local BORDER_ALPHA = 1
local FONT_SIZE = 15

local PALETTES = {
    normal = {
        bottom = { 0, 0, 0, .7 },
        top = { .3, .3, .3, .7 },
        border = { 0, 0, 0, BORDER_ALPHA },
        text = { 1, .82, 0 },
    },
    disabled = {
        bottom = { 0, 0, 0, .3 },
        top = { .5, .5, .5, .7 },
        border = { 0, 0, 0, BORDER_ALPHA },
        text = { .5, .5, .5 },
    },
    -- Tab / 筛选按钮的选中态：视觉上仍是金色，但由调用方显式持有。
    selected = {
        bottom = { 0, 0, 0, .7 },
        top = { .3, .3, .3, .7 },
        border = { 1, .82, 0, BORDER_ALPHA },
        text = { 1, .82, 0 },
    },
    -- 非选中态：保持灰字，离开悬停后也恢复灰色。
    muted = {
        bottom = { 0, 0, 0, .7 },
        top = { .3, .3, .3, .7 },
        border = { 0, 0, 0, BORDER_ALPHA },
        text = { .6, .6, .6 },
    },
    -- 正在发音的格子。用绿色而不是金色：金色是常态文字色，压不出"这一格刚响过"的区分度。
    active = {
        bottom = { 0, .3, .12, .85 },
        top = { .25, .85, .45, .85 },
        border = { .4, 1, .6, 1 },
        text = { 1, 1, 1 },
    },
}

local function HoverPalette()
    local palette = PALETTES.hover
    if palette then return palette end

    local r, g, b = 0, 0, 0
    local _, class = UnitClass("player")
    if class and GetClassColor then
        local cr, cg, cb = GetClassColor(class)
        if cr then r, g, b = cr, cg, cb end
    end

    palette = {
        bottom = { r, g, b, .1 },
        top = { r, g, b, .7 },
        border = { r, g, b, BORDER_ALPHA },
        text = { 1, 1, 1 },
    }
    PALETTES.hover = palette
    return palette
end

-- 假名显示得出来不出来，全看字体有没有覆盖 U+3040–30FF。客户端标准字体在部分版本是
-- 纯西文的 FRIZQT__，假名会整片变成方块，所以这里逐个实测候选，取第一个 SetFont 成功的。
-- SetFont 在文件不存在时返回 false；个别客户端会直接 error，两种都得接住。
local FONT_CANDIDATES = {
    "Fonts\\ARKai_T.ttf",
    "Fonts\\ARHei.ttf",
    "Fonts\\bKAI00M.TTF",
    "Fonts\\bHEI00M.TTF",
    STANDARD_TEXT_FONT,
}

local resolvedFont

--- 探测并缓存可用的 CJK 字体。返回解析结果，UI 拿它决定要不要提示"字体可能不支持假名"。
local function ResolveFont()
    if resolvedFont then return resolvedFont end

    local probe = UIParent:CreateFontString()
    for index = 1, #FONT_CANDIDATES do
        local font = FONT_CANDIDATES[index]
        if font then
            local ok, loaded = pcall(probe.SetFont, probe, font, FONT_SIZE, "OUTLINE")
            if ok and loaded then
                resolvedFont = font
                break
            end
        end
    end
    probe:Hide()

    if not resolvedFont then resolvedFont = STANDARD_TEXT_FONT end
    return resolvedFont
end

--- 把解析好的字体套到文字对象上。size 不传用默认字号。
local function ApplyFont(text, size)
    text:SetFont(ResolveFont(), size or FONT_SIZE, "OUTLINE")
end

local function PaintBackground(bt, palette)
    local bg = bt.bg
    if not bg then return end

    local bottom, top = palette.bottom, palette.top
    if CreateColor and bg.SetGradient then
        bg:SetGradient("VERTICAL",
            CreateColor(bottom[1], bottom[2], bottom[3], bottom[4]),
            CreateColor(top[1], top[2], top[3], top[4]))
    else
        bg:SetColorTexture(top[1], top[2], top[3], top[4])
    end
end

local function ApplyPalette(bt, state)
    local palette = state == "hover" and HoverPalette() or PALETTES[state]
    if not palette then return end

    PaintBackground(bt, palette)
    bt:SetBackdropBorderColor(unpack(palette.border))
    local text = bt:GetFontString()
    if text then text:SetTextColor(unpack(palette.text)) end
end

--- 同皮肤按钮工厂。悬停与禁用态靠叠钩子实现，站点照旧写自己的 OnEnter/OnLeave。
local function CreateButton(parent)
    local bt = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    bt:SetBackdrop({ edgeFile = BORDER_TEXTURE, edgeSize = 1 })
    bt:SetBackdropBorderColor(unpack(PALETTES.normal.border))

    bt.bg = bt:CreateTexture(nil, "BACKGROUND")
    bt.bg:SetAllPoints()
    bt.bg:SetTexture(FILL_TEXTURE)

    local text = bt:CreateFontString()
    text:SetAllPoints()
    ApplyFont(text)
    text:SetTextColor(unpack(PALETTES.normal.text))
    bt:SetFontString(text)

    function bt:ApplyVisualState()
    if self.__TJEnabled == false then
            ApplyPalette(self, "disabled")
    elseif self.__TJVisualState then
        ApplyPalette(self, self.__TJVisualState)
        else
            ApplyPalette(self, "normal")
        end
    end

    --- Tab / 筛选按钮的外观不属于 normal 三态，由站点显式声明并在 OnLeave 后保留。
    function bt:SetVisualState(state)
        if state == "selected" or state == "muted" then
    self.__TJVisualState = state
        else
    self.__TJVisualState = nil
        end
        self:ApplyVisualState()
    end

    hooksecurefunc(bt, "SetScript", function(frame, scriptName)
        if scriptName == "OnEnter" then
            frame:HookScript("OnEnter", function() ApplyPalette(frame, "hover") end)
        elseif scriptName == "OnLeave" then
            frame:HookScript("OnLeave", function()
                frame:ApplyVisualState()
                GameTooltip:Hide()
            end)
        end
    end)
    hooksecurefunc(bt, "SetEnabled", function(frame, enabled)
        if enabled == true then
    frame.__TJEnabled = true
            frame:ApplyVisualState()
        elseif enabled == false then
    frame.__TJEnabled = false
            ApplyPalette(frame, "disabled")
        end
    end)

    function bt:Disable() self:SetEnabled(false) end
    function bt:Enable() self:SetEnabled(true) end

    bt.__TJEnabled = true
    ApplyPalette(bt, "normal")
    bt:SetScript("OnEnter", nil)
    bt:SetScript("OnLeave", nil)
    return bt
end

--- 切格子三态。active 是"正在发音"，UI 侧在播放时置上、播完后摘掉。
--- 格子不走 SetFontString（它有两个文字对象），所以颜色在这里自己管。
local function SetTileState(bt, state)
    local palette = state == "hover" and HoverPalette() or PALETTES[state]
    if not palette then return end

    PaintBackground(bt, palette)
    bt:SetBackdropBorderColor(unpack(palette.border))
    if bt.kana then bt.kana:SetTextColor(unpack(palette.text)) end
    -- 罗马音常态压暗，跟着假名一起提亮会把两行糊成一片，只有 active 态才提上来。
    if bt.romaji then
        if state == "active" then
            bt.romaji:SetTextColor(.85, 1, .9)
        else
            bt.romaji:SetTextColor(.65, .65, .65)
        end
    end
end

--- 五十音格子：上大半是假名，下沿一行小罗马音。
--- 罗马音不是装饰，是降级手段：万一客户端字体没覆盖假名区（U+3040–30FF），假名会整片
--- 变成方块，至少还能从罗马音看出这一格念什么。
local function CreateTile(parent)
    local bt = CreateFrame("Button", nil, parent, BACKDROP_TEMPLATE)
    bt:SetBackdrop({ edgeFile = BORDER_TEXTURE, edgeSize = 1 })
    bt:SetBackdropBorderColor(unpack(PALETTES.normal.border))

    bt.bg = bt:CreateTexture(nil, "BACKGROUND")
    bt.bg:SetAllPoints()
    bt.bg:SetTexture(FILL_TEXTURE)

    local kana = bt:CreateFontString(nil, "OVERLAY")
    ApplyFont(kana, 22)
    kana:SetPoint("CENTER", bt, "CENTER", 0, 3)
    bt.kana = kana

    local romaji = bt:CreateFontString(nil, "OVERLAY")
    ApplyFont(romaji, 9)
    romaji:SetPoint("BOTTOM", bt, "BOTTOM", 0, 3)
    bt.romaji = romaji

    bt.SetTileState = SetTileState

    hooksecurefunc(bt, "SetScript", function(frame, scriptName)
        if scriptName == "OnEnter" then
            frame:HookScript("OnEnter", function()
                if frame.__TJActive then return end
                SetTileState(frame, "hover")
            end)
        elseif scriptName == "OnLeave" then
            frame:HookScript("OnLeave", function()
                SetTileState(frame, frame.__TJActive and "active" or "normal")
                GameTooltip:Hide()
            end)
        end
    end)

    bt.__TJEnabled = true
    bt.__TJActive = false
    SetTileState(bt, "normal")
    bt:SetScript("OnEnter", nil)
    bt:SetScript("OnLeave", nil)
    return bt
end

--- 带标题栏与边框的面板，模块的窗口壳用它。沿用上游设置页的做法：
--- UI-Tooltip-Border 配 edgeSize 16 才是原生的圆角，ChatFrameBackground 只能画出 1px 直角线。
--- frameName 传了才会挂全局名，只有需要 Esc 关闭（进 UISpecialFrames）的窗口才传。
local function CreatePanel(parent, titleText, frameName)
    local panel = CreateFrame("Frame", frameName, parent, BACKDROP_TEMPLATE)
    panel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:SetBackdropColor(0, 0, 0, .9)
    panel:SetBackdropBorderColor(.6, .6, .6, .9)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)

    if titleText then
        local title = panel:CreateFontString(nil, "OVERLAY")
        ApplyFont(title, 14)
        title:SetPoint("TOP", panel, "TOP", 0, -10)
        title:SetTextColor(1, .82, 0)
        title:SetText(titleText)
        panel.title = title
    end

    return panel
end

_G.TJ_Widgets = {
    CreateButton = CreateButton,
    CreateTile = CreateTile,
    CreatePanel = CreatePanel,
    SetTileState = SetTileState,
    ApplyFont = ApplyFont,
    ResolveFont = ResolveFont,
}
