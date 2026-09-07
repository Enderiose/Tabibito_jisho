// 五十音音频生成闸门：把"AI 发音"这件事锁在开发期。
// WoW 插件沙箱既没有 TTS 也没有网络，游戏里能做的只有 PlaySoundFile 播现成文件，
// 所以音节清单从 modules/lang/kana.lua 现场解析（脚本内不存副本，改了数据表即改了判据），
// 交给 edge-tts 念成 mp3，落进 Media/sound/lang/——该目录已在 pack.js 的 RUNTIME_DIRS 里，
// 生成完不用动打包配置。
//
// 用法：仓库根执行
//   node tools/kana-gen.js                 补齐缺失的音频（已存在的跳过）
//   node tools/kana-gen.js --check         只体检不生成，缺文件或有残留都报出来
//   node tools/kana-gen.js --force         无视已存在，全部重生成
//   node tools/kana-gen.js --voice <音色>   换音色，默认 ja-JP-NanamiNeural
//   node tools/kana-gen.js --rate -20%     换语速，默认 -20%（学习用放慢）
//   node tools/kana-gen.js --python <路径>  指定装了 edge-tts 的 python
// 判据：数据表里的音节缺音频、Media/sound/lang 里出现数据表没有的残留文件，都是 FAIL（退出码非 0）。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = path.join(__dirname, "..");
const kanaLua = path.join(repoRoot, "modules", "lang", "kana.lua");
const outDir = path.join(repoRoot, "Media", "sound", "lang");
const tmpDir = path.join(repoRoot, "tmp");

const DEFAULT_PYTHON = "C:\\Users\\Administrator\\.workbuddy-ai\\binaries\\python\\envs\\default\\Scripts\\python.exe";
const synthScript = path.join(__dirname, "tts_synth.py");

const argv = process.argv.slice(2);

function optionValue(flag) {
    const index = argv.indexOf(flag);
    return index >= 0 ? argv[index + 1] : undefined;
}

const checkOnly = argv.includes("--check");
const forced = argv.includes("--force");
const voice = optionValue("--voice") || "ja-JP-NanamiNeural";
const rate = optionValue("--rate") || "-20%";
const pythonBin = optionValue("--python") || process.env.BGLAO_TTS_PYTHON || DEFAULT_PYTHON;

// 从 kana.lua 现场解析音节：只认 `{ h = "...", k = "...", r = "..." }` 这一个写法，
// 剥掉 -- 注释后再匹配，免得注释里的举例被当成真条目。
function parseCells() {
    const source = fs.readFileSync(kanaLua, "utf8");
    const stripped = source
        .split(/\r?\n/)
        .map((line) => line.replace(/--.*$/, ""))
        .join("\n");

    const pattern = /\{\s*h\s*=\s*"([^"]+)"\s*,\s*k\s*=\s*"([^"]+)"\s*,\s*r\s*=\s*"([^"]+)"\s*\}/g;
    const cells = [];
    const seen = new Set();
    let match;
    while ((match = pattern.exec(stripped)) !== null) {
        const romaji = match[3];
        if (seen.has(romaji)) continue;
        seen.add(romaji);
        // 送进 TTS 的必须是假名本身：喂罗马音给日语 TTS 会被当成英文字母拼读。
        cells.push({ romaji: romaji, text: match[1], katakana: match[2] });
    }
    return cells;
}

function audioFiles() {
    if (!fs.existsSync(outDir)) return [];
    return fs.readdirSync(outDir)
        .filter((name) => /\.mp3$/i.test(name))
        .map((name) => name.replace(/\.mp3$/i, ""));
}

const cells = parseCells();
if (cells.length === 0) {
    console.log("FAIL 从 modules/lang/kana.lua 解析不出任何音节，检查数据表写法");
    process.exitCode = 1;
} else {
    const present = new Set(audioFiles());
    const expected = new Set(cells.map((cell) => cell.romaji));
    const missing = cells.filter((cell) => !present.has(cell.romaji));
    const orphan = audioFiles().filter((name) => !expected.has(name));

    const totalBytes = (fs.existsSync(outDir) ? fs.readdirSync(outDir) : [])
        .filter((name) => /\.mp3$/i.test(name))
        .reduce((sum, name) => sum + fs.statSync(path.join(outDir, name)).size, 0);

    console.log(`音节清单：kana.lua ${cells.length} 个，已生成 ${present.size} 个，缺失 ${missing.length} 个`);
    console.log(`音频体积：${(totalBytes / 1024).toFixed(1)} KB`);
    console.log(`音色：${voice}  语速：${rate}`);

    if (orphan.length) {
        console.log(`\nFAIL 残留文件（数据表里没有对应音节）：${orphan.join(", ")}`);
        console.log("     数据表删了音节就手工删掉对应 mp3，别让它躺进发布包");
        process.exitCode = 1;
    }

    if (checkOnly) {
        if (missing.length) {
            console.log(`\nFAIL 缺音频：${missing.map((cell) => cell.romaji).join(", ")}`);
            process.exitCode = 1;
        } else {
            console.log("\nOK 五十音音频齐全");
        }
    } else if (missing.length === 0 && !forced) {
        console.log("\nOK 无缺失，未调用 TTS（要重生成加 --force）");
    } else {
        const queue = forced ? cells : missing;
        const manifest = path.join(tmpDir, "kana-manifest.json");
        fs.mkdirSync(tmpDir, { recursive: true });
        fs.writeFileSync(manifest, JSON.stringify(queue, null, 0), "utf8");

        console.log(`\n调 edge-tts 合成 ${queue.length} 个音节...`);
        const result = spawnSync(pythonBin, [
            synthScript,
            "--manifest", manifest,
            "--out", outDir,
            "--voice", voice,
            // 值以 - 开头（语速 -20%）时必须写成 --rate= 内联形式：
            // 分成两段传，argparse 会把 -20% 当成选项标志，报 "expected one argument"。
            "--rate=" + rate,
            ...(forced ? ["--force"] : []),
        ], { encoding: "utf8", env: { ...process.env, PYTHONIOENCODING: "utf-8" } });

        if (result.error) {
            console.log("FAIL 调不到 python：" + result.error.message);
            console.log("     用 --python <路径> 指定装了 edge-tts 的解释器");
            process.exitCode = 1;
        } else if (result.status !== 0) {
            console.log("FAIL 合成进程退出码 " + result.status);
            console.log((result.stderr || "").trim());
            process.exitCode = 1;
        } else {
            let ok = 0;
            let failed = 0;
            for (const line of (result.stdout || "").split(/\r?\n/)) {
                if (!line.trim()) continue;
                let record;
                try {
                    record = JSON.parse(line);
                } catch {
                    continue;
                }
                if (record.status === "fail") {
                    failed = failed + 1;
                    console.log(`  FAIL ${record.romaji} :: ${record.error}`);
                } else {
                    ok = ok + 1;
                }
            }
            console.log(`\n合成结果：成功 ${ok}　失败 ${failed}`);
            if (failed > 0) process.exitCode = 1;
            else console.log("OK 全部落盘，去掉 --check 重跑可复核");
        }
    }
}
