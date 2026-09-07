-- lang.lua
--- 模块入口：初始化存档、注册斜杠命令、把窗口挂进 Esc 链。
--- 加载顺序最后一环，前面 widgets/kana/store/ui_kana 都已把全局对象挂好。

local ADDON_NAME = ...
local MODULE = _G.TJ_Store
local KanaUI = _G.TJ_Panel
local Review = _G.TJ_Review
local WordReview = _G.TJ_WordReview

local FRAME_NAME = "TJ_MainFrame"

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(_, event, addonName)
    if event ~= "ADDON_LOADED" or addonName ~= ADDON_NAME then return end
    MODULE.Init()
    -- 登录提醒：3 秒后检查有待复习卡片时在聊天栏打印。
    C_Timer.After(3, function()
        if not Review or not Review.IsEnabled() then return end
        if not Review.HasWork() then return end
        local stats = Review.GetStats()
        local L = _G.TJ_L
        if L then
            print(L("reviewLoginReminder", stats.dueCount or 0))
        else
            print(string.format("|cff00BFFF旅人辞典|r 待复习 %d 张假名闪卡，/jisho 打开复习。", stats.dueCount or 0))
        end

        if WordReview and WordReview.IsEnabled() and WordReview.HasWork() then
            local stats = WordReview.GetStats()
            local L = _G.TJ_L
            if L then
                print(L("wordReviewLoginReminder", stats.dueCount or 0))
            else
                print(string.format("|cff00BFFF旅人辞典|r 待复习 %d 张单词闪卡，/jisho 打开复习。", stats.dueCount or 0))
            end
        end
    end)
    loader:UnregisterEvent("ADDON_LOADED")
end)

SLASH_TABIBITOJISHO1 = "/jisho"
SlashCmdList["TABIBITOJISHO"] = function(message)
    local argument = (message or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if argument == "sz" then
        if _G.TJ_JournalShow then _G.TJ_JournalShow() end
    else
        KanaUI.Toggle()
    end
end

-- Esc 关窗：按帧名登记，窗口本身是懒创建的，这里不用先建出来。
tinsert(UISpecialFrames, FRAME_NAME)
