const fs = require("fs");
const path = require("path");

// 编码扫描：检查 .lua 文件是否有 BOM 或 CRLF
// 用法：node tools/encoding-check.js [--fix]
// --fix 会自动去除 BOM 并将 CRLF 转为 LF（仅限仓库自有文件，跳过 Libs/ tmp/）

const root = process.cwd();
const SKIP_DIRS = { ".git": true, node_modules: true, tmp: true, Libs: true };
const shouldFix = process.argv.includes("--fix");

let bomCount = 0;
let crlfCount = 0;
let fixed = 0;
const issues = [];

function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (SKIP_DIRS[entry.name]) continue;
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            walk(fullPath);
        } else if (entry.name.endsWith(".lua")) {
            check(fullPath);
        }
    }
}

function check(file) {
    const rel = path.relative(root, file);
    const bytes = fs.readFileSync(file);

    // BOM check (EF BB BF)
    const hasBOM = bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF;
    if (hasBOM) {
        bomCount++;
        issues.push({ file: rel, type: "BOM" });
        if (shouldFix) {
            fs.writeFileSync(file, bytes.slice(3));
            fixed++;
        }
    }

    // CRLF check (0D 0A)
    let hasCRLF = false;
    const data = hasBOM && shouldFix ? bytes.slice(3) : bytes;
    for (let i = 0; i < data.length - 1; i++) {
        if (data[i] === 0x0D && data[i + 1] === 0x0A) {
            hasCRLF = true;
            break;
        }
    }
    if (hasCRLF) {
        crlfCount++;
        issues.push({ file: rel, type: "CRLF" });
        if (shouldFix) {
            const content = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
            const clean = Buffer.from(content, "utf8");
            fs.writeFileSync(file, clean);
            fixed++;
        }
    }
}

walk(root);

for (const issue of issues) {
    console.log(issue.type + "  " + issue.file);
}

console.log("---");
console.log("scanned .lua files (excl Libs/tmp)");
if (bomCount + crlfCount === 0) {
    console.log("ALL CLEAN — no BOM, no CRLF");
} else {
    console.log("BOM: " + bomCount + "  CRLF: " + crlfCount + (shouldFix ? "  fixed: " + fixed : "  (run with --fix to auto-repair)"));
}

process.exitCode = bomCount + crlfCount > 0 ? 1 : 0;
