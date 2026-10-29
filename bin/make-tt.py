#!/usr/bin/env python3
"""気象庁の走時表 JMA2001（tjma2001）を、配信画面で使う tt.json に変換する。

使い方: make-tt.py <tjma2001.zip または tjma2001 テキスト> <出力 tt.json>
各行から数値を4つ取り出し、P波走時(秒)・S波走時(秒)・深さ(km)・震央距離(km) として読む。
"""
import io
import json
import re
import sys
import zipfile

NUM = re.compile(r"-?\d+(?:\.\d+)?")


def read_text(path):
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if not n.endswith("/")]
            # 一番大きいファイルを走時表とみなす
            name = max(names, key=lambda n: z.getinfo(n).file_size)
            return z.read(name).decode("ascii", "ignore")
    with open(path, "rb") as f:
        return f.read().decode("ascii", "ignore")


def main(src, out):
    rows = {}
    for line in io.StringIO(read_text(src)):
        nums = NUM.findall(line)
        if len(nums) != 4:
            continue
        p, s, dep, dist = float(nums[0]), float(nums[1]), int(round(float(nums[2]))), int(round(float(nums[3])))
        rows[(dep, dist)] = (p, s)
    depths = sorted({d for d, _ in rows})
    dists = sorted({x for _, x in rows})
    # 形式の確認：深さ0〜700km、距離0〜2000km、P波はS波より速い
    if not depths or depths[0] != 0 or depths[-1] < 500 or not dists or dists[0] != 0 or dists[-1] < 1500:
        sys.exit(f"走時表の形式が想定と違います（深さ {depths[:3]}…, 距離 {dists[:3]}…）")
    P, S = [], []
    for d in depths:
        pr, sr = [], []
        for x in dists:
            v = rows.get((d, x))
            if v is None:
                sys.exit(f"走時表に欠けている値があります（深さ{d}km 距離{x}km）")
            if v[0] > v[1]:
                sys.exit("走時表の形式が想定と違います（P波がS波より遅い）")
            pr.append(round(v[0], 2))
            sr.append(round(v[1], 2))
        P.append(pr)
        S.append(sr)
    with open(out, "w") as f:
        json.dump({"source": "JMA2001 (気象庁)", "depth": depths, "dist": dists, "p": P, "s": S}, f, separators=(",", ":"))
    print(f"走時表を変換しました: 深さ{len(depths)}段 × 距離{len(dists)}段 → {out}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
