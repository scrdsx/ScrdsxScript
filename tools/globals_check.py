"""Rough undefined-name check for the Luau modules: every identifier that is read somewhere but never declared as a local,
a parameter or a for-variable anywhere in the file, minus the known Roblox / executor globals. Catches typos and
missing locals (not scoping mistakes). Usage: python tools/globals_check.py src/esp.lua [more files]"""
import sys
from luaparser import ast, astnodes

KNOWN = set("""game workspace script Enum Instance Vector2 Vector3 CFrame Color3 UDim UDim2 TweenInfo NumberSequence NumberSequenceKeypoint
ColorSequence ColorSequenceKeypoint NumberRange Ray RaycastParams OverlapParams Rect Region3 BrickColor Font PhysicalProperties Axes Faces
math string table os task coroutine debug utf8 bit32 buffer print warn error assert pcall xpcall select type typeof tostring tonumber pairs ipairs
next rawget rawset rawequal rawlen setmetatable getmetatable unpack require tick time wait spawn delay settings UserSettings DateTime
getgenv getrenv getgc gethui syn writefile readfile isfile isfolder makefolder delfile listfiles appendfile setclipboard request http_request
hookfunction hookmetamethod getnamecallmethod newcclosure checkcaller getconnections firesignal identifyexecutor setfpscap getcustomasset
queue_on_teleport loadstring mousemoverel mouse1click mouse1press mouse1release Drawing cloneref getrawmetatable setreadonly isreadonly
__import _G _VERSION self vector shared""".split())


def names(tree):
    declared, used = set(), set()
    for node in ast.walk(tree):
        if isinstance(node, astnodes.LocalAssign):
            for t in node.targets:
                if isinstance(t, astnodes.Name):
                    declared.add(t.id)
        elif isinstance(node, (astnodes.LocalFunction,)):
            declared.add(node.name.id)
            for a in node.args:
                if isinstance(a, astnodes.Name):
                    declared.add(a.id)
        elif isinstance(node, (astnodes.Function, astnodes.Method, astnodes.AnonymousFunction)):
            for a in node.args:
                if isinstance(a, astnodes.Name):
                    declared.add(a.id)
        elif isinstance(node, astnodes.Fornum):
            declared.add(node.target.id)
        elif isinstance(node, astnodes.Forin):
            for t in node.targets:
                declared.add(t.id)
        elif isinstance(node, astnodes.Assign):
            for t in node.targets:
                if isinstance(t, astnodes.Name):
                    declared.add(t.id)  # global assignment counts as a declaration here
    skip = set()
    for node in ast.walk(tree):
        if isinstance(node, astnodes.Index) and node.notation == astnodes.IndexNotation.DOT:
            skip.add(id(node.idx))
        elif isinstance(node, astnodes.Invoke):
            skip.add(id(node.func))
        elif isinstance(node, astnodes.Method):
            skip.add(id(node.name))
        elif isinstance(node, astnodes.Field) and not getattr(node, "between_brackets", False):
            skip.add(id(node.key))
    for node in ast.walk(tree):
        if isinstance(node, astnodes.Name) and id(node) not in skip:
            used.add(node.id)
    return used - declared - KNOWN


for f in sys.argv[1:]:
    src = open(f, encoding="utf-8").read()
    try:
        tree = ast.parse(src)
    except Exception as e:
        print(f, "PARSE ERROR", e)
        continue
    bad = sorted(names(tree))
    print(f, "OK" if not bad else ("undeclared: " + ", ".join(bad)))
