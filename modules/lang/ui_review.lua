-- ui_review.lua
--- 闪卡复习 UI：认读 / 听音辨字双模式，两段揭示 + 自评。
--- 只用 TJ_* 系列导出，无外部依赖。

local ADDON_NAME = ...
local Review = _G.TJ_Review
local Store = _G.TJ_Store
local Kana = _G.TJ_Kana
local W = _G.TJ_Widgets

-- 布局常量
local PAD = 12
local TOOLBAR_H = 26
local STATS_H = 22
local BTN_W = 90
local BTN_H = 28
local OPTION_W = 80
local OPTION_H = 36
local CARD_GAP = 8

--- 音频路径，与 ui_kana 格式一致。
local function SoundPath(romaji)
    return "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\sound\\lang\\" .. romaji .. ".mp3"
end

--- 播放假名音频。
local function PlayKana(romaji)
    PlaySoundFile(SoundPath(romaji), "Master")
end

--- 播放按钮贴图图标，替代字体缺字形的 ▷。
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

--- 从 romaji 列表中随机选 n 个（不含 exclude）。
local function PickDistractors(allRomaji, exclude, n)
    local pool = {}
    for i = 1, #allRomaji do
        if allRomaji[i] ~= exclude then
            pool[#pool + 1] = allRomaji[i]
        end
    end
    -- Fisher-Yates 部分洗牌取前 n 个
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local result = {}
    for i = 1, math.min(n, #pool) do
        result[i] = pool[i]
    end
    return result
end

--- 创建复习面板。parent 是 Tab 容器的内容区 frame。
local function CreateReviewPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()

    -- 状态
    local state = "idle" -- idle | question | answer | summary
    local session = {}   -- { { romaji, card }, ... }
    local sessionIndex = 0
    local sessionCorrect = 0
    local sessionTotal = 0
    local currentRomaji = nil
    local currentCell = nil

    -- 子帧引用（懒创建）
    local toolbar, statsBar, contentArea
    local idleFrame, questionFrame, answerFrame, summaryFrame

    ----------------------------------------------------------------
    -- 工具栏：模式切换
    ----------------------------------------------------------------
    toolbar = CreateFrame("Frame", nil, panel)
    toolbar:SetHeight(TOOLBAR_H)
    toolbar:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -PAD)
    toolbar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD)

    local modeButton = W.CreateButton(toolbar)
    modeButton:SetSize(78, 22)
    modeButton:SetPoint("LEFT", toolbar, "LEFT", 0, 0)

    local function RefreshModeButton()
        local mode = Review.GetMode()
        modeButton:SetText(mode == "listen" and (L and L.reviewModeListen or "听音辨字") or (L and L.reviewModeRecognize or "认读"))
    end
    modeButton:SetScript("OnClick", function()
        if state ~= "idle" and state ~= "summary" then return end -- 复习中不许切
        local mode = Review.GetMode()
        Review.SetMode(mode == "listen" and "recognize" or "listen")
        RefreshModeButton()
    end)

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
        local s = Review.GetStats()
        local streakText = string.format((L and L.reviewStreak or "连击 %d 天"), s.streak)
        local masteryText = string.format((L and L.reviewMastery or "掌握率 %d%%"), s.mastery)
        local dueText = string.format((L and L.reviewDueCount or "待复习 %d"), s.dueCount)
        local totalText = string.format((L and L.reviewTotalReviewed or "累计 %d"), s.totalReviewed)
        statsText:SetText(streakText .. "  |  " .. masteryText .. "  |  " .. dueText .. "  |  " .. totalText)
    end

    ----------------------------------------------------------------
    -- 内容区（各状态帧的父容器）
    ----------------------------------------------------------------
    contentArea = CreateFrame("Frame", nil, panel)
    contentArea:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -4)
    contentArea:SetPoint("BOTTOMRIGHT", statsBar, "TOPRIGHT", 0, 4)

    ----------------------------------------------------------------
    -- 辅助：隐藏所有状态帧
    ----------------------------------------------------------------
    local function HideAllStates()
        if idleFrame then idleFrame:Hide() end
        if questionFrame then questionFrame:Hide() end
        if answerFrame then answerFrame:Hide() end
        if summaryFrame then summaryFrame:Hide() end
    end


    -- forward declarations: closures in ShowIdle reference these
    local ShowQuestion, ShowAnswer, ShowSummary
    ----------------------------------------------------------------
    -- idle 状态：未启用 / 开始复习 / 全部掌握
    ----------------------------------------------------------------
    local function ShowIdle()
        state = "idle"
        HideAllStates()
        RefreshStats()
        RefreshModeButton()

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

        if not Review.IsEnabled() then
            idleFrame.enableBtn:SetText(L and L.reviewEnable or "开启假名复习")
            idleFrame.enableBtn:SetScript("OnClick", function()
                Review.SetEnabled(true)
                Review.InitCards()
                ShowIdle()
            end)
            idleFrame.statusText:SetText("")
        elseif not Review.HasWork() then
            idleFrame.enableBtn:SetText(L and L.reviewStart or "开始复习")
            idleFrame.enableBtn:SetEnabled(false)
            idleFrame.statusText:SetText(L and L.reviewAllMastered or "全部掌握！")
        else
            idleFrame.enableBtn:SetText(L and L.reviewStart or "开始复习")
            idleFrame.enableBtn:SetEnabled(true)
            idleFrame.enableBtn:SetScript("OnClick", function()
                session = Review.BuildSession()
                sessionIndex = 0
                sessionCorrect = 0
                sessionTotal = #session
                if sessionTotal == 0 then
                    ShowIdle()
                    return
                end
                ShowQuestion()
            end)
            idleFrame.statusText:SetText("")
        end

        idleFrame:Show()
    end

    ----------------------------------------------------------------
    -- question 状态：认读 或 听音辨字
    ----------------------------------------------------------------
    ShowQuestion = function()
        state = "question"
        sessionIndex = sessionIndex + 1
        if sessionIndex > sessionTotal then
            ShowSummary()
            return
        end

        local entry = session[sessionIndex]
        currentRomaji = entry.romaji
        currentCell = Review.FindCell(currentRomaji)
        if not currentCell then
            -- 数据异常，跳过
            ShowQuestion()
            return
        end

        HideAllStates()
        if not questionFrame then
            questionFrame = CreateFrame("Frame", nil, contentArea)
            questionFrame:SetAllPoints()

            -- 进度文本
            questionFrame.progressText = questionFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(questionFrame.progressText, 10)
            questionFrame.progressText:SetPoint("TOP", questionFrame, "TOP", 0, -4)
            questionFrame.progressText:SetTextColor(.6, .6, .6)

            -- 认读模式：大假名 + 揭示按钮
            questionFrame.recognizeFrame = CreateFrame("Frame", nil, questionFrame)
            questionFrame.recognizeFrame:SetAllPoints()

            questionFrame.kanaText = questionFrame.recognizeFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(questionFrame.kanaText, 48)
            questionFrame.kanaText:SetPoint("CENTER", questionFrame.recognizeFrame, "CENTER", 0, 16)
            questionFrame.kanaText:SetTextColor(1, .82, 0)

            questionFrame.revealBtn = W.CreateButton(questionFrame.recognizeFrame)
            questionFrame.revealBtn:SetSize(BTN_W, BTN_H)
            questionFrame.revealBtn:SetPoint("CENTER", questionFrame.recognizeFrame, "CENTER", 0, -36)
            questionFrame.revealBtn:SetText(L and L.reviewReveal or "揭示")

            -- 听音辨字模式：播放按钮 + 4 选项
            questionFrame.listenFrame = CreateFrame("Frame", nil, questionFrame)
            questionFrame.listenFrame:SetAllPoints()

            questionFrame.playBtn = W.CreateButton(questionFrame.listenFrame)
            questionFrame.playBtn:SetSize(100, BTN_H)
            questionFrame.playBtn:SetPoint("CENTER", questionFrame.listenFrame, "CENTER", 0, 40)
            questionFrame.playBtn:SetText(L and L.reviewPlayAudio or "播放")
            AttachPlayIcon(questionFrame.playBtn)

            questionFrame.optionBtns = {}
            for i = 1, 4 do
                local btn = W.CreateButton(questionFrame.listenFrame)
                btn:SetSize(OPTION_W, OPTION_H)
                questionFrame.optionBtns[i] = btn
            end
            -- 2x2 布局
            questionFrame.optionBtns[1]:SetPoint("CENTER", questionFrame.listenFrame, "CENTER", -OPTION_W/2 - CARD_GAP/2, -20)
            questionFrame.optionBtns[2]:SetPoint("CENTER", questionFrame.listenFrame, "CENTER", OPTION_W/2 + CARD_GAP/2, -20)
            questionFrame.optionBtns[3]:SetPoint("CENTER", questionFrame.listenFrame, "CENTER", -OPTION_W/2 - CARD_GAP/2, -20 - OPTION_H - CARD_GAP)
            questionFrame.optionBtns[4]:SetPoint("CENTER", questionFrame.listenFrame, "CENTER", OPTION_W/2 + CARD_GAP/2, -20 - OPTION_H - CARD_GAP)
        end

        questionFrame.progressText:SetText(sessionIndex .. " / " .. sessionTotal)

        local mode = Review.GetMode()
        local katakana = Store.DB().kana and Store.DB().kana.katakana
        local displayKana = katakana and currentCell.k or currentCell.h

        if mode == "recognize" then
            -- 认读：显示假名，等揭示
            questionFrame.recognizeFrame:Show()
            questionFrame.listenFrame:Hide()
            questionFrame.kanaText:SetText(displayKana)
            questionFrame.revealBtn:SetScript("OnClick", function()
                ShowAnswer()
            end)
        else
            -- 听音辨字：播放音频 + 4 选 1
            questionFrame.recognizeFrame:Hide()
            questionFrame.listenFrame:Show()

            PlayKana(currentRomaji)

            questionFrame.playBtn:SetScript("OnClick", function()
                PlayKana(currentRomaji)
            end)

            -- 生成 4 个选项（1 正确 + 3 干扰）
            local allRomaji = Review.GetAllRomaji()
            local distractors = PickDistractors(allRomaji, currentRomaji, 3)
            local options = { currentRomaji }
            for i = 1, #distractors do options[#options + 1] = distractors[i] end
            -- 打乱选项顺序
            for i = #options, 2, -1 do
                local j = math.random(i)
                options[i], options[j] = options[j], options[i]
            end

            for i = 1, 4 do
                local btn = questionFrame.optionBtns[i]
                local optRomaji = options[i]
                if optRomaji then
                    local optCell = Review.FindCell(optRomaji)
                    local optKana = optCell and (katakana and optCell.k or optCell.h) or "?"
                    btn:SetText(optKana)
                    btn:Show()
                    btn:SetScript("OnClick", function()
                        -- 选中后揭示
                        ShowAnswer()
                    end)
                else
                    btn:Hide()
                end
            end
        end

        questionFrame:Show()
    end

    ----------------------------------------------------------------
    -- answer 状态：揭示答案 + 自评
    ----------------------------------------------------------------
    ShowAnswer = function()
        state = "answer"
        HideAllStates()

        if not answerFrame then
            answerFrame = CreateFrame("Frame", nil, contentArea)
            answerFrame:SetAllPoints()

            answerFrame.kanaText = answerFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(answerFrame.kanaText, 48)
            answerFrame.kanaText:SetPoint("CENTER", answerFrame, "CENTER", 0, 30)
            answerFrame.kanaText:SetTextColor(1, .82, 0)

            answerFrame.romajiText = answerFrame:CreateFontString(nil, "OVERLAY")
            W.ApplyFont(answerFrame.romajiText, 16)
            answerFrame.romajiText:SetPoint("TOP", answerFrame.kanaText, "BOTTOM", 0, -6)
            answerFrame.romajiText:SetTextColor(.75, .75, .75)

            answerFrame.audioBtn = W.CreateButton(answerFrame)
            answerFrame.audioBtn:SetSize(80, 22)
            answerFrame.audioBtn:SetPoint("TOP", answerFrame.romajiText, "BOTTOM", 0, -8)
            answerFrame.audioBtn:SetText(L and L.reviewPlayAudio or "播放")
            AttachPlayIcon(answerFrame.audioBtn)

            -- 自评按钮
            local ratingLabels = {
                { q = 5, key = "reviewKnow", fallback = "知道", color = { .2, .8, .3 } },
                { q = 3, key = "reviewFuzzy", fallback = "模糊", color = { 1, .82, 0 } },
                { q = 1, key = "reviewForgot", fallback = "不知道", color = { .8, .2, .2 } },
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

        local katakana = Store.DB().kana and Store.DB().kana.katakana
        local displayKana = katakana and currentCell.k or currentCell.h
        answerFrame.kanaText:SetText(displayKana)
        answerFrame.romajiText:SetText(currentRomaji)

        -- 自动播放音频
        if Review.GetAudioAutoPlay() then
            PlayKana(currentRomaji)
        end

        answerFrame.audioBtn:SetScript("OnClick", function()
            PlayKana(currentRomaji)
        end)

        for i = 1, #answerFrame.ratingBtns do
            local btn = answerFrame.ratingBtns[i]
            btn:SetScript("OnClick", function()
                Review.ReviewCard(currentRomaji, btn.__quality)
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
        Review.MarkReviewed()
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

        summaryFrame.titleText:SetText(L and L.reviewSessionDone or "本轮完成")

        local pct = sessionTotal > 0 and math.floor(sessionCorrect / sessionTotal * 100 + 0.5) or 0
        local s = Review.GetStats()
        summaryFrame.detailText:SetText(
            string.format((L and L.reviewSessionSummary or "复习 %d 张，正确率 %d%%"), sessionTotal, pct)
            .. "  |  " .. string.format((L and L.reviewStreak or "连击 %d 天"), s.streak)
        )

        if Review.HasWork() then
            summaryFrame.againBtn:SetText(L and L.reviewAgain or "再来一轮")
            summaryFrame.againBtn:Show()
            summaryFrame.againBtn:SetEnabled(true)
            summaryFrame.againBtn:SetScript("OnClick", function()
                session = Review.BuildSession()
                sessionIndex = 0
                sessionCorrect = 0
                sessionTotal = #session
                if sessionTotal == 0 then
                    ShowIdle()
                    return
                end
                ShowQuestion()
            end)
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
        Review.InitCards()
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

_G.TJ_ReviewUI = {
    CreateReviewPanel = CreateReviewPanel,
}
