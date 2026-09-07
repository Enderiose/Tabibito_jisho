const fs = require("fs");
const path = require("path");
const luaparse = require("D:/node/lua/node_modules/luaparse");

const root = process.cwd();
const files = [];

// tmp/ 是红线规定的唯一合法落盘位置，里面放的是上游发布包基线（带 BOM 的第三方 .lua 不在我们管辖内），
// 所以常规扫描不进队；要校验基线本身，由 upstream-sync 流程切进该目录单独跑本脚本。
const SKIP_DIRS = { [".git"]: true, node_modules: true, tmp: true };

(function walk(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        if (SKIP_DIRS[entry.name]) continue;
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            walk(fullPath);
        } else if (entry.name.endsWith(".lua")) {
            files.push(fullPath);
        }
    }
})(root);

files.sort();

let passed = 0;
let failed = 0;

for (const file of files) {
    const relative = path.relative(root, file);
    try {
        const source = fs.readFileSync(file, "utf8");
        luaparse.parse(source, { luaVersion: "5.1" });
        passed = passed + 1;
        console.log("OK   " + relative);
    } catch (err) {
        failed = failed + 1;
        console.log("FAIL " + relative + " :: " + err.message);
    }
}

console.log("---");
console.log("total: " + files.length + "  passed: " + passed + "  failed: " + failed);
process.exitCode = failed > 0 ? 1 : 0;
