// 单词数据生成脚本：word-source.json → modules/lang/words.lua + tools/tts-words.json
//
// 用法：仓库根执行
//   node tools/word-gen.js           生成 words.lua 和 tts-words.json
//   node tools/word-gen.js --check   只校验不写文件
//
// 校验：必填字段（id/kanji/reading/romaji/english/category）、id 去重、category 白名单。
const fs = require("fs");
const path = require("path");

const repoRoot = path.join(__dirname, "..");
const sourceFile = path.join(__dirname, "word-source.json");
const outLua = path.join(repoRoot, "modules", "lang", "words.lua");
const outManifest = path.join(__dirname, "tts-words.json");

const CATEGORIES = ["item", "spell", "zone", "general"];
const REQUIRED_FIELDS = ["id", "kanji", "reading", "romaji", "english", "category"];

const argv = process.argv.slice(2);
const checkOnly = argv.includes("--check");

function fail(msg) {
    console.log("FAIL " + msg);
    process.exitCode = 1;
}

// --- 读取并校验 ---
if (!fs.existsSync(sourceFile)) {
    fail("找不到 " + sourceFile);
    process.exit(1);
}

let entries;
try {
    entries = JSON.parse(fs.readFileSync(sourceFile, "utf8"));
} catch (e) {
    fail("JSON 解析失败：" + e.message);
    process.exit(1);
}

if (!Array.isArray(entries)) {
    fail("word-source.json 根节点必须是数组");
    process.exit(1);
}

const seenIds = new Set();
let errors = 0;

for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    const prefix = "entries[" + i + "]";

    for (const field of REQUIRED_FIELDS) {
        if (typeof entry[field] !== "string" || entry[field].trim() === "") {
            fail(prefix + " 缺少必填字段 " + field);
            errors++;
        }
    }

    if (typeof entry.id === "string") {
        if (seenIds.has(entry.id)) {
            fail(prefix + " id 重复：" + entry.id);
            errors++;
        }
        seenIds.add(entry.id);
    }

    if (typeof entry.category === "string" && CATEGORIES.indexOf(entry.category) === -1) {
        fail(prefix + " 非法 category：" + entry.category + "（允许：" + CATEGORIES.join(", ") + "）");
        errors++;
    }
}

if (errors > 0) {
    console.log("共 " + errors + " 个校验错误");
    process.exit(1);
}

// --- 排序：先 category、再 id ---
entries.sort(function (a, b) {
    if (a.category < b.category) return -1;
    if (a.category > b.category) return 1;
    if (a.id < b.id) return -1;
    if (a.id > b.id) return 1;
    return 0;
});

// --- 统计 ---
const catCounts = {};
for (const cat of CATEGORIES) catCounts[cat] = 0;
for (const e of entries) catCounts[e.category]++;

console.log("词条总数：" + entries.length);
for (const cat of CATEGORIES) {
    console.log("  " + cat + "：" + catCounts[cat]);
}

if (checkOnly) {
    console.log("\nOK 校验通过（--check 模式未写文件）");
    process.exit(0);
}

// --- 生成 words.lua ---
function escapeLua(s) {
    return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

let lua = '-- 本文件由 tools/word-gen.js 自动生成，请勿手工编辑。\n';
lua += 'local DATA = {\n';
for (const e of entries) {
    lua += '    { id = "' + escapeLua(e.id)
        + '", kanji = "' + escapeLua(e.kanji)
        + '", reading = "' + escapeLua(e.reading)
        + '", romaji = "' + escapeLua(e.romaji)
        + '", english = "' + escapeLua(e.english)
        + '", category = "' + escapeLua(e.category)
        + '" },\n';
}
lua += '}\n';
lua += '\n';
lua += 'local cached = nil\n';
lua += '\n';
lua += 'local function GetData()\n';
lua += '    if cached then return cached end\n';
lua += '    cached = DATA\n';
lua += '    return cached\n';
lua += 'end\n';
lua += '\n';
lua += 'local function GetByCategory(cat)\n';
lua += '    local result = {}\n';
lua += '    local data = GetData()\n';
lua += '    for i = 1, #data do\n';
lua += '        if data[i].category == cat then\n';
lua += '            result[#result + 1] = data[i]\n';
lua += '        end\n';
lua += '    end\n';
lua += '    return result\n';
lua += 'end\n';
lua += '\n';
lua += 'local function GetByID(id)\n';
lua += '    local data = GetData()\n';
lua += '    for i = 1, #data do\n';
lua += '        if data[i].id == id then return data[i] end\n';
lua += '    end\n';
lua += '    return nil\n';
lua += 'end\n';
lua += '\n';
lua += '_G.BGLAO_Lang_Words = {\n';
lua += '    GetData = GetData,\n';
lua += '    GetByCategory = GetByCategory,\n';
lua += '    GetByID = GetByID,\n';
lua += '}\n';

fs.writeFileSync(outLua, lua, "utf8");
console.log("\n已生成 " + path.relative(repoRoot, outLua));

// --- 生成 TTS manifest ---
const manifest = entries.map(function (e) {
    return { id: e.id, text: e.reading, out: "Media/sound/words/" + e.id + ".mp3" };
});
fs.writeFileSync(outManifest, JSON.stringify(manifest, null, 2), "utf8");
console.log("已生成 " + path.relative(repoRoot, outManifest) + "（" + manifest.length + " 条）");

console.log("\nOK 完成");
