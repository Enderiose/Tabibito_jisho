#!/usr/bin/env python3
"""edge-tts 批量合成器。

被 tools/kana-gen.js 调用，不单独面向用户：清单由 Node 侧从 modules/lang/kana.lua
现场解析后写进 JSON 传进来，这里只负责把文本念成 mp3 落盘。

WoW 插件沙箱里没有 TTS 也没有网络，所以"AI 发音"这件事只能发生在开发期：
游戏里播的永远是这里生成的现成文件。

清单格式（JSON 数组）：
    [{"romaji": "a", "text": "あ"}, ...]
romaji 决定输出文件名 <out>/<romaji>.mp3，text 是实际送进 TTS 的字符串——
必须是假名本身，喂罗马音给日语 TTS 会被当成英文字母拼读。

每行 stdout 输出一个 JSON 结果对象，Node 侧逐行解析汇总。
"""

import argparse
import asyncio
import json
import os
import sys

import edge_tts


async def synth_one(semaphore, item, out_dir, voice, rate, force):
    romaji = item["romaji"]
    text = item["text"]
    target = os.path.join(out_dir, romaji + ".mp3")

    if os.path.exists(target) and not force:
        return {"romaji": romaji, "status": "skip", "bytes": os.path.getsize(target)}

    async with semaphore:
        try:
            communicate = edge_tts.Communicate(text, voice, rate=rate)
            # 先写临时文件再改名，避免中途失败留下半截 mp3 被当成"已生成"而永久跳过。
            tmp_path = target + ".part"
            await communicate.save(tmp_path)
            os.replace(tmp_path, target)
            return {"romaji": romaji, "status": "ok", "bytes": os.path.getsize(target)}
        except Exception as err:  # noqa: BLE001 - 网络类异常种类太多，逐条报告比崩掉有用
            if os.path.exists(target + ".part"):
                os.remove(target + ".part")
            return {"romaji": romaji, "status": "fail", "error": str(err)}


async def run(manifest, out_dir, voice, rate, force, jobs):
    os.makedirs(out_dir, exist_ok=True)
    semaphore = asyncio.Semaphore(jobs)
    tasks = [synth_one(semaphore, item, out_dir, voice, rate, force) for item in manifest]
    for coro in asyncio.as_completed(tasks):
        print(json.dumps(await coro, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser(description="edge-tts 批量合成")
    parser.add_argument("--manifest", required=True, help="JSON 清单路径")
    parser.add_argument("--out", required=True, help="mp3 输出目录")
    parser.add_argument("--voice", default="ja-JP-NanamiNeural", help="音色")
    parser.add_argument("--rate", default="-20%", help="语速，学习用放慢")
    parser.add_argument("--force", action="store_true", help="忽略已存在的文件，重新生成")
    parser.add_argument("--jobs", type=int, default=4, help="并发数")
    args = parser.parse_args()

    with open(args.manifest, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)

    asyncio.run(run(manifest, args.out, args.voice, args.rate, args.force, args.jobs))


if __name__ == "__main__":
    sys.exit(main())
