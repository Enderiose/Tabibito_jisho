-- kana.lua
--- 五十音数据表。
--- 行优先组织，每行固定 5 格，对齐 a/i/u/e/o 五个元音；该行没有对应音的格位填 false，
--- 由 UI 侧决定画成空格还是占位，不要在这里补"看起来差不多"的假名。
--- 每个音节给三件套：h = 平假名，k = 片假名，r = 罗马音。
--- 罗马音同时是音频文件名：Media/sound/lang/<r>.mp3，改了罗马音就得重新生成音频。

local ROWS = {
    { key = "a", label = "あ行", cells = {
        { h = "あ", k = "ア", r = "a" },
        { h = "い", k = "イ", r = "i" },
        { h = "う", k = "ウ", r = "u" },
        { h = "え", k = "エ", r = "e" },
        { h = "お", k = "オ", r = "o" },
    } },
    { key = "ka", label = "か行", cells = {
        { h = "か", k = "カ", r = "ka" },
        { h = "き", k = "キ", r = "ki" },
        { h = "く", k = "ク", r = "ku" },
        { h = "け", k = "ケ", r = "ke" },
        { h = "こ", k = "コ", r = "ko" },
    } },
    { key = "sa", label = "さ行", cells = {
        { h = "さ", k = "サ", r = "sa" },
        { h = "し", k = "シ", r = "shi" },
        { h = "す", k = "ス", r = "su" },
        { h = "せ", k = "セ", r = "se" },
        { h = "そ", k = "ソ", r = "so" },
    } },
    { key = "ta", label = "た行", cells = {
        { h = "た", k = "タ", r = "ta" },
        { h = "ち", k = "チ", r = "chi" },
        { h = "つ", k = "ツ", r = "tsu" },
        { h = "て", k = "テ", r = "te" },
        { h = "と", k = "ト", r = "to" },
    } },
    { key = "na", label = "な行", cells = {
        { h = "な", k = "ナ", r = "na" },
        { h = "に", k = "ニ", r = "ni" },
        { h = "ぬ", k = "ヌ", r = "nu" },
        { h = "ね", k = "ネ", r = "ne" },
        { h = "の", k = "ノ", r = "no" },
    } },
    { key = "ha", label = "は行", cells = {
        { h = "は", k = "ハ", r = "ha" },
        { h = "ひ", k = "ヒ", r = "hi" },
        { h = "ふ", k = "フ", r = "fu" },
        { h = "へ", k = "ヘ", r = "he" },
        { h = "ほ", k = "ホ", r = "ho" },
    } },
    { key = "ma", label = "ま行", cells = {
        { h = "ま", k = "マ", r = "ma" },
        { h = "み", k = "ミ", r = "mi" },
        { h = "む", k = "ム", r = "mu" },
        { h = "め", k = "メ", r = "me" },
        { h = "も", k = "モ", r = "mo" },
    } },
    { key = "ya", label = "や行", cells = {
        { h = "や", k = "ヤ", r = "ya" },
        false,
        { h = "ゆ", k = "ユ", r = "yu" },
        false,
        { h = "よ", k = "ヨ", r = "yo" },
    } },
    { key = "ra", label = "ら行", cells = {
        { h = "ら", k = "ラ", r = "ra" },
        { h = "り", k = "リ", r = "ri" },
        { h = "る", k = "ル", r = "ru" },
        { h = "れ", k = "レ", r = "re" },
        { h = "ろ", k = "ロ", r = "ro" },
    } },
    { key = "wa", label = "わ行", cells = {
        { h = "わ", k = "ワ", r = "wa" },
        false,
        false,
        false,
        { h = "を", k = "ヲ", r = "wo" },
    } },
    { key = "n", label = "ん", cells = {
        { h = "ん", k = "ン", r = "n" },
        false,
        false,
        false,
        false,
    } },
}

-- 元音列头，跟每行的格位一一对应，UI 拿它画表头。
local VOWELS = { "a", "i", "u", "e", "o" }

--- 遍历所有音节，回调收到 (cell, 行key, 列index)。开发期脚本与 UI 共用这一个出口，
--- 免得两处各写一份遍历，加行时漏掉一边。
local function ForEachCell(callback)
    for rowIndex = 1, #ROWS do
        local row = ROWS[rowIndex]
        for colIndex = 1, 5 do
            local cell = row.cells[colIndex]
            if cell then callback(cell, row.key, colIndex) end
        end
    end
end

_G.TJ_Kana = {
    ROWS = ROWS,
    VOWELS = VOWELS,
    ForEachCell = ForEachCell,
}
