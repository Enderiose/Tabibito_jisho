// 发布打包闸门：发布包内容改成"白名单式"生成——根目录 .toc + .toc 加载清单 + 运行期资源目录，
// 排除逻辑不再依赖仓库外（或不入库的 txt 里）那串靠记忆的 -xr!，新增开发期目录不会被静默打进包。
// 用法：仓库根执行
//   node tools/pack.js                打包 ..\BGLite_AccountOverview.zip，打包后回读校验
//   node tools/pack.js --check        只体检并打印清单，不写盘（不碰 7z）
//   node tools/pack.js --out <路径>   换输出 zip；自测请指到项目内 tmp\，见 AGENTS.md 红线
//   node tools/pack.js --7z <路径>    指定 7z 可执行文件（默认找 PATH，再退 C:\Program Files\7-Zip）
// 判据：.toc 缺文件、core\locales 出现 .toc 未加载的 .lua、回读结果与清单不一致，都是 FAIL（退出码非 0）。
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = path.join(__dirname, "..");
const addonsDir = path.join(repoRoot, "..");
const repoDirName = path.basename(repoRoot);
const ownToc = path.join(repoRoot, repoDirName + ".toc");
const defaultOut = path.join(addonsDir, repoDirName + ".zip");

// 整目录进包的运行期目录：.toc 只逐条列加载文件，Libs 的 xml、Media 的贴图靠这里进包。
const RUNTIME_DIRS = ["Libs", "Media"];
// 逐文件按 .toc 加载清单进包的源码目录：里面有 .lua 而 .toc 没列 = 漏加加载行或该删的残留，报警。
// modules/ 已随 Tabibito_jisho 拆分迁走，2026-09-08 从白名单移除。
const SOURCE_DIRS = ["core", "locales", "modules"];
// 已登记的开发期条目：只在体检报告里归类用，不参与"进不进包"的判定（白名单已经把它们挡在外面）。
const DEV_ENTRIES = [".agents", ".codex", ".dev", ".editorconfig", ".git", ".gitattributes", ".gitignore",
    ".github", "AGENTS.md", "README.md", "docs", "prompt", "tmp", "tools", "zip.txt"];

const problems = [];
const notices = [];

function readLines(file) {
    return fs.readFileSync(file, "utf8").split(/\r?\n/);
}

// 包内键一律用正斜杠，跟 7z 回读的行分隔符无关。
function repoKey(absolute) {
    return path.relative(repoRoot, absolute).split(path.sep).join("/");
}

function walkFiles(dir) {
    const collected = [];
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            collected.push(...walkFiles(fullPath));
        } else {
            collected.push(fullPath);
        }
    }
    return collected;
}

function tocLoadList() {
    const entries = [];
    for (const line of readLines(ownToc)) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith("#")) continue;
        entries.push(trimmed);
    }
    return entries;
}

// ---- 1. 生成发布清单 ----
function buildReleaseList() {
    if (!fs.existsSync(ownToc)) {
        problems.push(`找不到 ${repoDirName}.toc，无法确定发布内容`);
        return [];
    }
    const release = new Set();

    for (const tocFile of fs.readdirSync(repoRoot)) {
        if (/\.toc$/i.test(tocFile) && fs.statSync(path.join(repoRoot, tocFile)).isFile()) {
            release.add(tocFile);
        }
    }

    const tocEntries = tocLoadList();
    for (const entry of tocEntries) {
        const resolved = path.join(repoRoot, entry.split("\\").join(path.sep));
        if (fs.existsSync(resolved)) {
            release.add(repoKey(resolved));
        } else {
            problems.push(`.toc 列了 ${entry}，但文件不存在`);
        }
    }

    for (const dir of SOURCE_DIRS) {
        const absolute = path.join(repoRoot, dir);
        if (!fs.existsSync(absolute)) continue;
        const listed = new Set(tocEntries.map((entry) => entry.split("\\").join("/").toLowerCase()));
        for (const file of walkFiles(absolute)) {
            const key = repoKey(file);
            if (!/\.lua$/i.test(key) || listed.has(key.toLowerCase())) continue;
            problems.push(`${key} 没有被 .toc 加载，却躺在源码目录里：补加载行还是删掉它`);
        }
    }

    for (const dir of RUNTIME_DIRS) {
        const absolute = path.join(repoRoot, dir);
        if (fs.existsSync(absolute)) {
            for (const file of walkFiles(absolute)) release.add(repoKey(file));
        } else {
            notices.push(`运行期目录 ${dir}/ 不存在，本包不含该目录`);
        }
    }

    return [...release].sort();
}

// ---- 2. 体检：仓库根条目归类，未登记的抖出来问一句 ----
function checkRootEntries(releaseList) {
    const dev = new Set(DEV_ENTRIES.map((entry) => entry.toLowerCase()));
    const known = new Set([...RUNTIME_DIRS, ...SOURCE_DIRS].map((entry) => entry.toLowerCase()));
    for (const key of releaseList) known.add(key.split("/")[0].toLowerCase());
    for (const entry of fs.readdirSync(repoRoot)) {
        const lower = entry.toLowerCase();
        if (/\.toc$/i.test(entry) || dev.has(lower) || known.has(lower)) continue;
        notices.push(`仓库根条目 ${entry} 未登记：既不在发布清单里，也不在开发期条目清单里，确认它该归哪一类（要发布就加进 RUNTIME_DIRS）`);
    }
}

// ---- 3. 7z 调用 ----
function findSevenZip(explicit) {
    const candidates = explicit ? [explicit] : ["7z.exe", "7z", "C:\\Program Files\\7-Zip\\7z.exe"];
    for (const candidate of candidates) {
        if (candidate.includes(path.sep) && !fs.existsSync(candidate)) continue;
        const probe = spawnSync(candidate, ["i"], { encoding: "utf8" });
        if (!probe.error && probe.status === 0) return candidate;
    }
    return null;
}

function runSevenZip(sevenZip, args) {
    const result = spawnSync(sevenZip, args, { cwd: addonsDir, encoding: "utf8" });
    if (result.error) {
        problems.push(`7z 调用失败：${result.error.message}`);
        return null;
    }
    if (result.status > 1) {
        problems.push(`7z 退出码 ${result.status}\n${result.stdout || ""}${result.stderr || ""}`);
        return null;
    }
    return result;
}

// 回读包内容：-ba -slt 每个条目一段，条目之间只隔空行（没有分隔线），逐行扫 Path/Folder 配对。
function listArchive(sevenZip, archive) {
    const result = runSevenZip(sevenZip, ["l", "-slt", "-ba", archive]);
    if (!result) return null;
    const entries = new Set();
    let pending = null;
    const flush = (isDirectory) => {
        if (pending && !isDirectory) entries.add(pending);
        pending = null;
    };
    for (const line of result.stdout.split(/\r?\n/)) {
        const pathMatch = line.match(/^\s*Path\s*=\s*(.+)$/);
        if (pathMatch) {
            flush(false);
            const key = pathMatch[1].trim().split("\\").join("/");
            // 没带 -ba 或旧版 7z 会把压缩包自身也列成第一段。
            pending = key.toLowerCase().endsWith(".zip") ? null : repoRelative(key);
            continue;
        }
        if (/^\s*Folder\s*=\s*\+/.test(line)) flush(true);
    }
    flush(false);
    return entries;
}

// 包内路径一律带 <插件目录名>/ 前缀，比对时剥掉，跟发布清单同口径。
function repoRelative(archivePath) {
    const prefix = repoDirName.toLowerCase() + "/";
    return archivePath.toLowerCase().startsWith(prefix)
        ? archivePath.slice(prefix.length)
        : archivePath;
}

// 文件清单走 @file，避免文件多时超过 Windows 命令行长度限制。
function packSevenZip(sevenZip, archive, releaseList) {
    const listFile = path.join(repoRoot, "tmp", "pack-7z-files.list");
    fs.mkdirSync(path.dirname(listFile), { recursive: true });
    try {
        const lines = releaseList.map((key) => repoDirName + "\\" + key.split("/").join(path.sep));
        fs.writeFileSync(listFile, lines.join("\r\n"), "utf8");
        const args = ["a", "-tzip", "-y", "-scsUTF-8", archive, "@" + listFile];
        return Boolean(runSevenZip(sevenZip, args));
    } finally {
        fs.rmSync(listFile, { force: true });
    }
}

// ---- 4. 主流程 ----
const argv = process.argv.slice(2);

function optionValue(flag) {
    const index = argv.indexOf(flag);
    return index >= 0 ? argv[index + 1] : undefined;
}

const checkOnly = argv.includes("--check");
const outFile = path.resolve(optionValue("--out") || defaultOut);
const releaseList = buildReleaseList();
checkRootEntries(releaseList);

console.log(`发布清单（${releaseList.length} 个文件，前缀 ${repoDirName}/）`);
for (const key of releaseList) console.log("  " + key);
console.log("---");
console.log(`打包方式：白名单（根 *.toc + .toc 加载清单 + ${RUNTIME_DIRS.join("/ ")} 整目录），不是排除清单`);

if (notices.length) {
    console.log("\n== 提示 ==");
    for (const notice of notices) console.log("  WARN " + notice);
}

if (checkOnly) {
    console.log("\n--check：未写盘。打包请去掉 --check（输出 " + path.relative(addonsDir, outFile) + "）");
} else if (problems.length === 0) {
    const sevenZip = findSevenZip(optionValue("--7z"));
    if (!sevenZip) {
        problems.push("找不到可用的 7z：装 7-Zip 或用 --7z <路径> 指路");
    } else {
        // 先删旧包：7z a 对已存在的 zip 是追加，留着会把上一版的文件混进来。
        fs.rmSync(outFile, { force: true });
        if (!packSevenZip(sevenZip, outFile, releaseList)) {
            problems.push("打包未完成");
        } else {
            const packed = listArchive(sevenZip, outFile);
            if (!packed) {
                problems.push("打包后读不回清单，无法确认包内容");
            } else {
                const expected = new Set(releaseList);
                const missing = [...expected].filter((key) => !packed.has(key));
                const extra = [...packed].filter((key) => !expected.has(key));
                for (const key of missing) problems.push("包内缺少 " + repoDirName + "/" + key);
                for (const key of extra) problems.push("包内多出 " + repoDirName + "/" + key);
                console.log("\n回读校验：包内 " + packed.size + " 个文件，发布清单 " + expected.size + " 个");
            }
            const size = fs.existsSync(outFile) ? fs.statSync(outFile).size : 0;
            console.log("输出：" + outFile + "（" + (size / 1024).toFixed(1) + " KB）");
        }
    }
}

console.log("---");
if (problems.length) {
    for (const problem of problems) console.log("FAIL " + problem);
    process.exitCode = 1;
} else {
    console.log(checkOnly ? "OK 发布清单一致（体检模式，未打包）" : "OK 发布包内容与清单一致");
}
