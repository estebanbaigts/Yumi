#!/usr/bin/env python3
"""Extrait Yumi (dessin SVG, humeurs, liserés, corps souple, poses, scènes, regard) de la
maquette de référence vers le prototype de la refonte, sans le redessiner.

Source : design/maquette/reference.html (celle dont le Swift a été porté).
Sortie : design/refonte-ile/yumi.css et design/refonte-ile/yumi.js.
Usage : python3 design/refonte-ile/outils/extraire-yumi.py
"""
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parents[3]
src = (root / "design/maquette/reference.html").read_text(encoding="utf-8")
out = root / "design/refonte-ile"

def between(text, start, end):
    i = text.index(start)
    j = text.index(end, i)
    return text[i:j]

# CSS: every rule about .yumi, and the keyframes they use.
style = between(src, "<style>", "</style>")
lines = style.splitlines()
css = [l for l in lines if l.lstrip().startswith(".yumi") or l.lstrip().startswith("#actor:hover .eyes")]
names = set()
for l in css:
    names.update(re.findall(r"animation:\s*([\w-]+)", l))
keyframes = [l for l in lines if l.lstrip().startswith("@keyframes") and l.split()[1] in names]
header = "/* Extrait de design/maquette/reference.html par outils/extraire-yumi.py. Ne pas modifier à la main. */\n"
(out / "yumi.css").write_text(header + ":root { --spring: cubic-bezier(.32,1.22,.42,1) }\n" + "\n".join(css + keyframes) + "\n", encoding="utf-8")

# JS: from the Yumi engine to playPose, then the gaze that follows the pointer.
engine = between(src, "/* ---------- Yumi:", "/* ---------- Sound")
gaze = between(src, "/* Gaze follows the pointer */", "/* Scale the stage")
js = header.replace("/*", "//").replace(" */", "") + engine + "\n" + gaze
(out / "yumi.js").write_text(js, encoding="utf-8")
print(f"yumi.css : {len(css)} règles, {len(keyframes)} animations ; yumi.js : {js.count(chr(10))} lignes")
