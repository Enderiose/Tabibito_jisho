// 单词音频生成闸门：从 tools/tts-words.json 现场读清单（word-gen.js 生成物），
// 调 tools/tts_synth.py 合成 Media/sound/words/*.mp3。
//
// 用法：仓库根执行
//   node tools/word-gen-audio.js                 补齐缺失的音频（已存在的跳过）
//   node tools/word-gen-audio.js --check         只体检不生成，缺文件或有残留都报出来
//   node tools/word-gen-audio.js --force         无视已存在，全部重生成
//   node tools/word-gen-audio.js --voice <音色>   换音色，默认 ja-JP-NanamiNeural
//   node tools/word-gen-audio.js --rate -20%     换语速，默认 -20%（学习用放慢）
//   node tools/word-gen-audio.js --python <路径>  指定装了 edge-tts 的 python
// 判据：清单缺音频、目录里出现清单没有的残留 mp3，都是 FAIL（退出码非 0）。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = path.join(__dirname, "..");
const manifestFile = path.join(__dirname, "tts-words.json");
const outDir = path.join(repoRoot, "Media", "sound", "words");
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

function readManifest() {
    const entries = JSON.parse(fs.readFileSync(manifestFile, "utf8"));
    if (!Array.isArray(entries)) throw new Error("tts-words.json 根节点必须是数组");

    const seen = new Set();
    const result = [];
    for (const entry of entries) {
        if (typeof entry.id !== "string" || entry.id.trim() === "") throw new Error("清单条目缺 id");
        if (typeof entry.text !== "string" || entry.text.trim() === "") throw new Error(`条目 ${entry.id} 缺 text`);
        if (typeof entry.out !== "string" || entry.out.trim() === "") throw new Error(`条目 ${entry.id} 缺 out`);
        const expectedPrefix = "Media/sound/words/";
        if (!entry.out.startsWith(expectedPrefix) || !entry.out.toLowerCase().endsWith(".mp3")) {
            throw new Error(`条目 ${entry.id} 的 out 不在 Media/sound/words/：${entry.out}`);
        }
        if (seen.has(entry.id)) throw new Error(`清单 id 重复：${entry.id}`);
        seen.add(entry.id);
        result.push(entry);
    }
    return result;
}

function audioFiles() {
    if (!fs.existsSync(outDir)) return [];
    return fs.readdirSync(outDir)
        .filter((name) => /\.mp3$/i.test(name))
        .map((name) => name.replace(/\.mp3$/i, ""));
}

const entries = readManifest();
if (entries.length === 0) {
    console.log("FAIL tts-words.json 里没有任何条目");
    process.exitCode = 1;
} else {
    const present = new Set(audioFiles());
    const expected = new Set(entries.map((entry) => entry.id));
    const missing = entries.filter((entry) => !present.has(entry.id));
    const orphan = audioFiles().filter((name) => !expected.has(name));

    const totalBytes = audioFiles().reduce((sum, name) => sum + fs.statSync(path.join(outDir, name + ".mp3")).size, 0);
    console.log(`单词清单：tts-words.json ${entries.length} 条，已生成 ${present.size} 个，缺失 ${missing.length} 个`);
    console.log(`音频体积：${(totalBytes / 1024).toFixed(1)} KB`);
    console.log(`音色：${voice}  语速：${rate}`);

    if (orphan.length) {
        console.log(`\nFAIL 残留文件（清单里没有对应词条）：${orphan.join(", ")}`);
        console.log("     清单删了词条就手工删掉对应 mp3，别让它躺进发布包");
        process.exitCode = 1;
    }

    if (checkOnly) {
        if (missing.length) {
            console.log(`\nFAIL 缺音频：${missing.map((entry) => entry.id).join(", ")}`);
            process.exitCode = 1;
        } else {
            console.log("\nOK 单词音频齐全");
        }
    } else if (missing.length === 0 && !forced) {
        console.log("\nOK 无缺失，未调用 TTS（要重生成加 --force）");
    } else {
        const queue = forced ? entries : missing;
        fs.mkdirSync(tmpDir, { recursive: true });
        const manifest = path.join(tmpDir, "word-audio-manifest.json");
        fs.writeFileSync(
            manifest,
            JSON.stringify(queue.map((entry) => ({ romaji: entry.id, text: entry.text })), null, 0),
            "utf8",
        );

        console.log(`\n调 edge-tts 合成 ${queue.length} 个单词...`);
        const result = spawnSync(pythonBin, [
            synthScript,
            "--manifest", manifest,
            "--out", outDir,
            "--voice", voice,
            // 值以 - 开头（语速 -20%）时必须写成 --rate= 内联形式。
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
            else console.log("OK 全部落盘，--check 可复核");
        }
    }
}
