-- weapon_keys_probe.lua : finds which key fires a vehicle's weapons by READING the game's own scripts (no need to sit in it or press anything).
-- Default target: the Su-27 jet. Another vehicle?  getgenv().KeyHunt = "Ka52"  (part of the script / folder name) before running.
-- It decompiles every script whose path contains the target name, pulls out every line that mentions a key / mouse button / bind,
-- plus the lines about missiles, firing, launching, flares, bombs and guns, and copies that summary to the clipboard.
-- Full decompiled sources -> workspace/weaponkeys/<script>.lua
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
local target = tostring(env.KeyHunt or "Su27"):lower()

local out = {}
local function log(s) out[#out + 1] = s end
log(("=== WEAPON KEYS  target \"%s\"  place %s"):format(target, tostring(game.PlaceId)))
if type(decompile) ~= "function" then log("!! your executor has no decompile(): cannot read the scripts") end
pcall(function() if makefolder then makefolder("weaponkeys") end end)

-- every script whose full path mentions the target
local found, seen = {}, {}
local function consider(s)
	if seen[s] or not (s:IsA("LocalScript") or s:IsA("ModuleScript") or s:IsA("Script")) then return end
	seen[s] = true
	local ok, p = pcall(game.GetFullName, s)
	if ok and p:lower():find(target, 1, true) then found[#found + 1] = { s = s, p = p } end
end
for _, root in ipairs({ RS, lp, game:GetService("StarterPlayer"), game:GetService("StarterGui"), workspace }) do
	local ok, ds = pcall(function() return root:GetDescendants() end)
	for _, d in ipairs(ok and ds or {}) do consider(d) end
end
pcall(function() for _, s in ipairs(getscripts()) do consider(s) end end)
pcall(function() for _, s in ipairs(getloadedmodules()) do consider(s) end end)
pcall(function() for _, s in ipairs(getnilinstances()) do if typeof(s) == "Instance" then consider(s) end end end)
table.sort(found, function(a, b) return a.p < b.p end)
log(#found .. " scripts match:")
for _, f in ipairs(found) do log("  " .. f.p .. "  [" .. f.s.ClassName .. "]") end

-- what to pull out of the code
local KEYPAT = { "KeyCode", "UserInputType", "MouseButton", "BindAction", "InputBegan", "InputEnded", "IsKeyDown", "IsMouseButtonPressed", "ContextAction", "Button1Down", "Activated" }
local WEAPON = { "missile", "rocket", "fire", "launch", "shoot", "flare", "chaff", "bomb", "gun", "cannon", "weapon", "lock", "target", "trigger", "salvo", "pylon", "r73", "r27", "r-73", "r-27", "kh" }
local function has(l, list) for _, w in ipairs(list) do if l:find(w, 1, true) then return true end end return false end

log("")
for _, f in ipairs(found) do
	local ok, src = pcall(decompile, f.s)
	if ok and type(src) == "string" and #src > 0 then
		pcall(function() writefile("weaponkeys/" .. f.p:gsub("[^%w%.%-_]", "_") .. ".lua", src) end)
		local hits, n = {}, 0
		local ln = 0
		for line in (src .. "\n"):gmatch("(.-)\r?\n") do
			ln = ln + 1
			local low = line:lower()
			local key = has(line, KEYPAT)
			local weap = has(low, WEAPON)
			if key or (weap and (low:find("enum", 1, true) or low:find("bind", 1, true) or low:find("input", 1, true) or low:find("key", 1, true) or low:find("fireserver", 1, true))) then
				n = n + 1
				if n <= 80 then hits[#hits + 1] = ("  %5d  %s"):format(ln, line:gsub("^%s+", ""):sub(1, 180)) end
			end
		end
		log(("--- %s  (%d lines, %d hits)"):format(f.p, ln, n))
		for _, h in ipairs(hits) do log(h) end
		if n > 80 then log("  ... " .. (n - 80) .. " more (see the full file)") end
	else
		log("--- " .. f.p .. "  (could not decompile: " .. tostring(src) .. ")")
	end
	task.wait()
end

local txt = table.concat(out, "\n")
pcall(function() writefile("weaponkeys_report.txt", txt) end)
local okc = pcall(function() setclipboard(txt) end)
print(("[weapon keys] %d scripts read%s -> workspace/weaponkeys_report.txt"):format(#found, okc and ", report copied to clipboard" or ""))
