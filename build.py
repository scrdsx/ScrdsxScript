"""Build step. Every .lua file under src/ is a module named by its path (src/visuals/esp.lua -> "visuals/esp"); src/main.lua runs last.
  1. writes the module list into loader.lua (so a new file is picked up without editing any list by hand)
  2. bundles everything into dist/ScrdsxScript.lua (one pasteable / loadstring-able file)
Modules load lazily through __import, so the order in either list does not matter."""
from pathlib import Path
import re

root = Path(__file__).parent
src = root / "src"
names = sorted(p.relative_to(src).with_suffix("").as_posix() for p in src.rglob("*.lua"))
names.remove("main")
names.append("main")

# 1) loader module list
loader = root / "loader.lua"
text = loader.read_text(encoding="utf8")
line = "local MODULES = { " + ", ".join(f'"{n}"' for n in names) + " } -- written by build.py (every file in src/); main last"
text, n = re.subn(r"^local MODULES = \{.*$", line, text, count=1, flags=re.M)
assert n == 1, "MODULES line not found in loader.lua"
loader.write_text(text, encoding="utf8")

# 2) bundle
out = ["local __mods, __cache = {}, {}",
       "local function __import(n)",
       "\tif __cache[n] == nil then __cache[n] = __mods[n]() end",
       "\treturn __cache[n]",
       "end", ""]
for name in names[:-1]:
    body = (src / f"{name}.lua").read_text(encoding="utf8")
    out.append(f'__mods["{name}"] = function()\n{body}\nend\n')
out.append("-- main")
out.append((src / "main.lua").read_text(encoding="utf8"))

dist = root / "dist"
dist.mkdir(exist_ok=True)
(dist / "ScrdsxScript.lua").write_text("\n".join(out), encoding="utf8")
print(f"built {dist / 'ScrdsxScript.lua'} ({len(names)} modules)")
