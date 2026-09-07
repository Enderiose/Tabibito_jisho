-- ui_wordreview.lua
--- 单词闪卡复习 UI：中文名揭示读音/罗马音/英文，自评后走 SM-2。
--- 只用 TJ_* 系列导出，无外部依赖。

local ADDON_NAME = ...
local WordReview = _G.TJ_WordReview
local W = _G.TJ_Widgets

-- 布局常量
local PAD = 12
local TOOLBAR_H = 26
local STATS_H = 22
local BTN_W = 90
local BTN_H = 28
local CARD_GAP = 8

--- 单词音频路径。读不到文件时 PlaySoundFile 静默失败，不影响复习流程。
local function SoundPath(id)
    return "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\sound\\words\\" .. id .. ".mp3"
end

local function PlayWord(id)
    PlaySoundFile(SoundPath(id), "Master")
end

--- 播放按钮贴图图标，与假名复习同一套。
local function AttachPlayIcon(btn)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon\\play")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", btn, "LEFT", 8, 0)
    local text = btn:GetFontString()
    if text then
        text:ClearAllPoints()
        text:SetPoint("CENTER", btn, "CENTER", 7, 0)
    end
end

--- 创建单词复习面板。parent 是 Tab 容器的内容区 frame。
local function CreateWordReviewPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- 状态
    local state = "idle" -- idle | question | answer | summary
    local session = {}   -- { { id, card }, ... }
    local sessionIndex = 0
    local sessionCorrect = 0
    local sessionTotal = 0
    local currentEntry = nil

    -- 子帧引用（懒创建）
    local statsBar, contentArea
    local idleFrame, questionFrame, answerFrame, summaryFrame

    ----------------------------------------------------------------
    -- 统计条
    ----------------------------------------------------------------
    statsBar = CreateFrame("Frame", nil, panel)
    statsBar:SetHeight(STATS_H)
    statsBar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAD, PAD)
    statsBar:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)

    local statsText = statsBar:CreateFontString(nil, "OVERLAY")
    W.ApplyFont(statsText, 10)
    statsText:SetPoint("CENTER", statsBar, "CENTER")
    statsText:SetTextColor(.7, .7, .7)

    local function RefreshStats()
        local s = WordReview.GetStats()
        local streakText = string.format((L and L.wordReviewStreak or "连击 %d 天"), s.streak)
        local masteryText = string.format((L and L.wordReviewMastery or "掌握率 %d%%"), s.mastery)
        local dueText = string.format((L and L.wordReviewDueCount or "待复习 %d"), s.dueCount)
        local totalText = string.format((L and L.wordReviewTotalReviewed or "累计 %d"), s.totalReviewed)
        statsText:SetText(streakText .. "  |  " .. masteryText .. "  |  " .. dueText .. "  |  " .. totalText)
    end

    ----------------------------------------------------------------
    -- 内容区（各状态帧的父容器）
    ----------------------------------------------------------------
    -- 与 ui_review 的工具栏内容区保持相同顶部位置。
    contentArea = CreateFrame("Frame", nil, panel)
    contentArea:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(PAD + TOOLBAR_H + 4))
    contentArea:SetPoint("BOTTOMRIGHT", statsBar, "TOPRIGHT", 0, 4)

    local function HideAllStates()
        if idleFrame then idleFrame:Hide() end
        if questionFrame then questionFrame:Hide() end
        if answerFrame then answerFrame:Hide() end
        if summaryFrame then summaryFrame:Hide() end
    end

    -- forward declarations：闭包在声明之前就引用这几个函数。
    local ShowQuestion, ShowAnswer, ShowSummary

    local function StartSession()
        session = WordReview.BuildSession()
        sessionIndex = 0
        sessionCorrect = 0
        sessionTotal = #session
        if sessionTotal == 0 then
            ShowQuestion()
            return
        end
        ShowQuestion()
    end

    ----------------------------------------------------------------
    -- idle 状态：未启用 / 开始复习 / 全部掌握
    ----------------------------------------------------------------
    local function ShowIdle()
        state = "idle"
        HideAllStates()
        RefreshStats()

        if not idleFrame then
            idleFrame = CreateFrame("Frame", nil, contentArea)
            idleFrame:SetAllPoints()

            idleFrame.enableBtn = W.CreateButton(idleFrame)
            idleFrame.enableBtn:SetSize(160, BTN_H)
            idleFrame.enableBtn:SetPoint("CENTER", idleFrame, "CENTER", 0, 20)

            idleFrame.statusText = idleFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(idleFrame.statusText, 12)
            idleFrame.statusText:SetPoint("CENTER", idleFrame, "CENTER", 0, -20)
            idleFrame.statusText:SetTextColor(.7, .7, .7)
        end

        if not WordReview.IsEnabled() then
            idleFrame.enableBtn:SetText(L and L.wordReviewEnable or "开启单词复习")
            idleFrame.enableBtn:SetEnabled(true)
            idleFrame.enableBtn:SetScript("OnClick", function()
                WordReview.SetEnabled(true)
                WordReview.InitCards()
                ShowIdle()
            end)
            idleFrame.statusText:SetText("")
        elseif not WordReview.HasWork() then
            idleFrame.enableBtn:SetText(L and L.wordReviewStart or "开始复习")
            idleFrame.enableBtn:SetEnabled(false)
            idleFrame.statusText:SetText(L and L.wordReviewAllMastered or "全部掌握！")
        else
            idleFrame.enableBtn:SetText(L and L.wordReviewStart or "开始复习")
            idleFrame.enableBtn:SetEnabled(true)
            idleFrame.enableBtn:SetScript("OnClick", StartSession)
            idleFrame.statusText:SetText("")
        end

        idleFrame:Show()
    end

    ----------------------------------------------------------------
    -- question 状态：正面只给中文名
    ----------------------------------------------------------------
    ShowQuestion = function()
        state = "question"
        sessionIndex = sessionIndex + 1
        if sessionIndex > sessionTotal then
            ShowSummary()
            return
        end

        local item = session[sessionIndex]
        currentEntry = WordReview.FindEntry(item.id)
        if not currentEntry then
            -- 词库数据异常就跳过，不让单条脏数据卡死整轮。
            ShowQuestion()
            return
        end

        HideAllStates()
        if not questionFrame then
            questionFrame = CreateFrame("Frame", nil, contentArea)
            questionFrame:SetAllPoints()

            questionFrame.progressText = questionFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(questionFrame.progressText, 10)
            questionFrame.progressText:SetPoint("TOP", questionFrame, "TOP", 0, -4)
            questionFrame.progressText:SetTextColor(.6, .6, .6)

            questionFrame.wordText = questionFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(questionFrame.wordText, 38)
            questionFrame.wordText:SetPoint("CENTER", questionFrame, "CENTER", 0, 16)
            questionFrame.wordText:SetTextColor(1, .82, 0)

            questionFrame.revealBtn = W.CreateButton(questionFrame)
            questionFrame.revealBtn:SetSize(BTN_W, BTN_H)
            questionFrame.revealBtn:SetPoint("CENTER", questionFrame, "CENTER", 0, -36)
        end

        questionFrame.progressText:SetText(sessionIndex .. " / " .. sessionTotal)
        questionFrame.wordText:SetText(currentEntry.kanji)
        questionFrame.revealBtn:SetText(L and L.wordReviewReveal or "揭示")
        questionFrame.revealBtn:SetScript("OnClick", function()
            ShowAnswer()
        end)

        questionFrame:Show()
    end

    ----------------------------------------------------------------
    -- answer 状态：读音 + 罗马音 + 英文 + 自评
    ----------------------------------------------------------------
    ShowAnswer = function()
        state = "answer"
        HideAllStates()

        if not answerFrame then
            answerFrame = CreateFrame("Frame", nil, contentArea)
            answerFrame:SetAllPoints()

            answerFrame.wordText = answerFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(answerFrame.wordText, 28)
            answerFrame.wordText:SetPoint("CENTER", answerFrame, "CENTER", 0, 96)
            answerFrame.wordText:SetTextColor(1, .82, 0)

            answerFrame.readingText = answerFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(answerFrame.readingText, 20)
            answerFrame.readingText:SetPoint("TOP", answerFrame.wordText, "BOTTOM", 0, -6)
            answerFrame.readingText:SetTextColor(1, 1, 1)

            answerFrame.romajiText = answerFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(answerFrame.romajiText, 12)
            answerFrame.romajiText:SetPoint("TOP", answerFrame.readingText, "BOTTOM", 0, -4)
            answerFrame.romajiText:SetTextColor(.75, .75, .75)

            answerFrame.englishText = answerFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(answerFrame.englishText, 13)
            answerFrame.englishText:SetPoint("TOP", answerFrame.romajiText, "BOTTOM", 0, -6)
            answerFrame.englishText:SetTextColor(1, 1, 1)

            answerFrame.audioBtn = W.CreateButton(answerFrame)
            answerFrame.audioBtn:SetSize(80, 22)
            answerFrame.audioBtn:SetPoint("CENTER", answerFrame, "CENTER", 0, -36)
            answerFrame.audioBtn:SetText(L and L.wordReviewPlayAudio or "播放")
            AttachPlayIcon(answerFrame.audioBtn)

            local ratingLabels = {
                { q = 5, key = "wordReviewKnow", fallback = "知道" },
                { q = 3, key = "wordReviewFuzzy", fallback = "模糊" },
                { q = 1, key = "wordReviewForgot", fallback = "不知道" },
            }
            answerFrame.ratingBtns = {}
            for i, info in ipairs(ratingLabels) do
                local btn = W.CreateButton(answerFrame)
                btn:SetSize(BTN_W, BTN_H)
                btn:SetText(L and L[info.key] or info.fallback)
                btn.__quality = info.q
                answerFrame.ratingBtns[i] = btn
            end
            answerFrame.ratingBtns[1]:SetPoint("BOTTOM", answerFrame, "BOTTOM", -BTN_W - CARD_GAP, 40)
            answerFrame.ratingBtns[2]:SetPoint("BOTTOM", answerFrame, "BOTTOM", 0, 40)
            answerFrame.ratingBtns[3]:SetPoint("BOTTOM", answerFrame, "BOTTOM", BTN_W + CARD_GAP, 40)
        end

        answerFrame.wordText:SetText(currentEntry.kanji)
        answerFrame.readingText:SetText(currentEntry.reading)
        answerFrame.romajiText:SetText(currentEntry.romaji)
        answerFrame.englishText:SetText(currentEntry.english)

        if WordReview.GetAudioAutoPlay() then
            PlayWord(currentEntry.id)
        end

        answerFrame.audioBtn:SetScript("OnClick", function()
            PlayWord(currentEntry.id)
        end)

        for i = 1, #answerFrame.ratingBtns do
            local btn = answerFrame.ratingBtns[i]
            btn:SetScript("OnClick", function()
                WordReview.ReviewCard(currentEntry.id, btn.__quality)
                if btn.__quality >= 3 then
                    sessionCorrect = sessionCorrect + 1
                end
                ShowQuestion()
            end)
        end

        answerFrame:Show()
    end

    ----------------------------------------------------------------
    -- summary 状态：本轮统计
    ----------------------------------------------------------------
    ShowSummary = function()
        state = "summary"
        HideAllStates()
        WordReview.MarkReviewed()
        RefreshStats()

        if not summaryFrame then
            summaryFrame = CreateFrame("Frame", nil, contentArea)
            summaryFrame:SetAllPoints()

            summaryFrame.titleText = summaryFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(summaryFrame.titleText, 16)
            summaryFrame.titleText:SetPoint("CENTER", summaryFrame, "CENTER", 0, 30)
            summaryFrame.titleText:SetTextColor(1, .82, 0)

            summaryFrame.detailText = summaryFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(summaryFrame.detailText, 12)
            summaryFrame.detailText:SetPoint("TOP", summaryFrame.titleText, "BOTTOM", 0, -10)
            summaryFrame.detailText:SetTextColor(.75, .75, .75)

            summaryFrame.againBtn = W.CreateButton(summaryFrame)
            summaryFrame.againBtn:SetSize(140, BTN_H)
            summaryFrame.againBtn:SetPoint("TOP", summaryFrame.detailText, "BOTTOM", 0, -16)
        end

        summaryFrame.titleText:SetText(L and L.wordReviewSessionDone or "本轮完成")

        local pct = sessionTotal > 0 and math.floor(sessionCorrect / sessionTotal * 100 + 0.5) or 0
        local s = WordReview.GetStats()
        summaryFrame.detailText:SetText(
            string.format((L and L.wordReviewSessionSummary or "复习 %d 张，正确率 %d%%"), sessionTotal, pct)
            .. "  |  " .. string.format((L and L.wordReviewStreak or "连击 %d 天"), s.streak)
        )

        if WordReview.HasWork() then
            summaryFrame.againBtn:SetText(L and L.wordReviewAgain or "再来一轮")
            summaryFrame.againBtn:Show()
            summaryFrame.againBtn:SetEnabled(true)
            summaryFrame.againBtn:SetScript("OnClick", StartSession)
        else
            summaryFrame.againBtn:Hide()
        end

        summaryFrame:Show()
    end

    ----------------------------------------------------------------
    -- 公开接口
    ----------------------------------------------------------------

    --- 面板显示时刷新状态（Tab 切换过来时调用）。
    function panel:OnShow()
        WordReview.InitCards()
        RefreshStats()
        if state == "idle" or state == "summary" then
            ShowIdle()
        end
    end

    panel:SetScript("OnShow", panel.OnShow)

    -- 初始显示 idle
    ShowIdle()

    return panel
end

_G.TJ_WordReviewUI = {
    CreateWordReviewPanel = CreateWordReviewPanel,
}
