-- world_dump.lua : ONE big dump so the AutoFarm can be rebuilt on facts instead of guesses. Takes a few minutes.
-- Writes everything to  workspace/ScrdsxDump/  (the files are read from disk, nothing needs to be copied):
--   index.txt            summary + what was done
--   scripts_index.txt    every LocalScript / ModuleScript in the game
--   src/*.lua            decompiled client code of the scripts that matter (robberies, interactions, inventory, vehicles, combat...)
--   keyword_hits.txt     lines mentioning teleport / setback / kick / cheat / exploit ... in that code
--   tags.txt             every CollectionService tag with positions + attributes of the tagged objects
--   robberies.txt        Workspace.Robberies / Spawned / Interactables with positions
--   remotes.txt          every remote in ReplicatedStorage
--   player.txt           your attributes, inventory-looking UI text, gc tables that look like an inventory
-- Run it standing on foot in the open, then wait for "[dump] DONE".  Stop early:  getgenv().WorldDump.Stop()
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local lp = Players.LocalPlayer
local env = (getgenv and getgenv()) or _G
if env.WorldDump then pcall(env.WorldDump.Stop) end
local running = true
env.WorldDump = { Stop = function() running = false end }

local DIR = "ScrdsxDump"
pcall(function() if makefolder then makefolder(DIR); makefolder(DIR .. "/src") end end)
local NL = string.char(10)
local function save(name, text) pcall(function() writefile(DIR .. "/" .. name, text) end) end
local function full(i) local ok, r = pcall(game.GetFullName, i); return ok and r or tostring(i) end
local function v3(v) return ("(%.1f,%.1f,%.1f)"):format(v.X, v.Y, v.Z) end
local function posOf(i)
	if i:IsA("BasePart") then return i.Position end
	if i:IsA("Model") then local ok, cf = pcall(function() return i:GetPivot() end); if ok then return cf.Position end end
	if i:IsA("Attachment") then return i.WorldPosition end
end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. tostring(v):sub(1, 40) end
	table.sort(t)
	return #t > 0 and (" [" .. table.concat(t, ", ") .. "]") or ""
end
local index = {}
local function note(s) index[#index + 1] = s; print("[dump] " .. s) end
note("started " .. os.date("%H:%M:%S") .. "  place=" .. tostring(game.PlaceId) .. "  you=" .. lp.Name)

-- 1) scripts ----------------------------------------------------------------------------------------------------
local scripts, seen = {}, {}
local function addScript(s)
	if not seen[s] and (s:IsA("LocalScript") or s:IsA("ModuleScript")) then seen[s] = true; scripts[#scripts + 1] = s end
end
pcall(function() for _, s in ipairs(getscripts()) do addScript(s) end end)
pcall(function() for _, s in ipairs(getloadedmodules()) do addScript(s) end end)
for _, root in ipairs({ RS, lp, game:GetService("ReplicatedFirst"), workspace, game:GetService("StarterPlayer"), game:GetService("StarterGui") }) do
	pcall(function() for _, d in ipairs(root:GetDescendants()) do addScript(d) end end)
end
local lines = {}
for _, s in ipairs(scripts) do lines[#lines + 1] = s.ClassName .. "  " .. full(s) end
table.sort(lines)
save("scripts_index.txt", table.concat(lines, NL))
note(#scripts .. " scripts found")

-- 2) decompile the ones that matter ---------------------------------------------------------------------------
local KEYS = { "rob", "safe", "bomb", "dealer", "store", "shop", "item", "inventor", "interact", "vehicle", "seat", "wanted", "crime", "police",
	"punch", "combat", "melee", "damage", "health", "tool", "money", "cash", "gold", "drop", "collect", "door", "teleport", "speed", "anti", "kick",
	"move", "position", "delivery", "bus", "truck", "job", "shift", "radar", "taxi", "spawn", "network", "remote", "flamework", "controller", "service",
	"player", "character", "humanoid", "map", "gps", "navigation", "open", "close", "hour", "time" }
local ranked = {}
for _, s in ipairs(scripts) do
	local p = full(s):lower()
	if not p:find("rbxts_include", 1, true) and not p:find("react", 1, true) then
		local score = 0
		for _, k in ipairs(KEYS) do if p:find(k, 1, true) then score = score + 1 end end
		ranked[#ranked + 1] = { s = s, score = score, path = full(s) }
	end
end
table.sort(ranked, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.path < b.path end)
local MAX = 400
local hits, done, failed = {}, 0, 0
local HITWORDS = { "teleport", "setback", "rubberband", "lagback", "exploit", "cheat", "kick", "SetNetworkOwner", "magnitude >", "anticheat", "anti%-cheat" }
if decompile then
	local t0 = os.clock()
	for i = 1, math.min(#ranked, MAX) do
		if not running or os.clock() - t0 > 600 then break end
		local r = ranked[i]
		local src
		local finished = false
		task.spawn(function() local ok, res = pcall(decompile, r.s); if ok then src = res end; finished = true end)
		local w = os.clock()
		while not finished and os.clock() - w < 12 do task.wait(0.05) end
		if src and #src > 0 then
			done = done + 1
			local name = (("%03d_"):format(i) .. r.path:gsub("[^%w]", "_")):sub(1, 150) .. ".lua"
			save("src/" .. name, "-- " .. r.path .. NL .. src:sub(1, 400000))
			local ln = 0
			for line in (src .. NL):gmatch("(.-)" .. NL) do
				ln = ln + 1
				local low = line:lower()
				for _, w2 in ipairs(HITWORDS) do
					if low:find(w2:lower(), 1, true) or (w2:find("%%") and low:find(w2)) then
						if #hits < 600 then hits[#hits + 1] = ("%s:%d: %s"):format(r.path, ln, line:gsub("^%s+", ""):sub(1, 170)) end
						break
					end
				end
			end
		else
			failed = failed + 1
		end
		if i % 20 == 0 then print(("[dump] decompiled %d / %d"):format(i, math.min(#ranked, MAX))) end
	end
	note(("decompiled %d scripts (%d failed or empty)"):format(done, failed))
else
	note("this executor has no decompile(): script sources were NOT dumped")
end
save("keyword_hits.txt", table.concat(hits, NL))

-- 3) tags ------------------------------------------------------------------------------------------------------------
local out = {}
local ok, all = pcall(CS.GetAllTags, CS)
if ok then
	table.sort(all)
	for _, tag in ipairs(all) do
		local list = CS:GetTagged(tag)
		out[#out + 1] = ("== %s (%d)"):format(tag, #list)
		local cap = (#list > 60) and 25 or 200
		for i = 1, math.min(#list, cap) do
			local o = list[i]
			local p = posOf(o)
			out[#out + 1] = ("   %s  %s%s"):format(full(o), p and v3(p) or "", attrs(o))
		end
	end
end
save("tags.txt", table.concat(out, NL))
note("tags written")

-- 4) robberies / spawned / interactables ------------------------------------------------------------------------
out = {}
local function tree(inst, depth, maxDepth, indent)
	if depth > maxDepth then return end
	local groups, order = {}, {}
	for _, k in ipairs(inst:GetChildren()) do
		local key = k.Name .. "|" .. k.ClassName
		if not groups[key] then groups[key] = { n = 0, first = k }; order[#order + 1] = key end
		groups[key].n = groups[key].n + 1
	end
	for _, key in ipairs(order) do
		local g = groups[key]
		local k = g.first
		local p = posOf(k)
		local extra = ""
		if k:IsA("ProximityPrompt") then extra = (" PROMPT '%s'/'%s' hold=%s"):format(k.ObjectText, k.ActionText, tostring(k.HoldDuration)) end
		out[#out + 1] = indent .. k.Name .. " (" .. k.ClassName .. ")" .. (g.n > 1 and (" x" .. g.n) or "") .. (p and (" " .. v3(p)) or "") .. extra .. attrs(k)
		tree(k, depth + 1, maxDepth, indent .. "  ")
	end
end
for _, name in ipairs({ "Robberies", "Spawned", "Interactables", "Dealers", "DeliveryDestinations", "MapBarriers", "VehicleDeleteZones", "Gates", "SpeedZones", "SpeedCameras", "Smugglers", "Drops" }) do
	local f = workspace:FindFirstChild(name)
	out[#out + 1] = "######## Workspace." .. name .. (f and "" or "  (not loaded / missing)")
	if f then tree(f, 1, 4, "  ") end
end
out[#out + 1] = "######## ReplicatedStorage.DefaultNavigationTargets"
local nt = RS:FindFirstChild("DefaultNavigationTargets")
for _, c in ipairs(nt and nt:GetChildren() or {}) do
	local p = posOf(c)
	out[#out + 1] = "  " .. c.Name .. " " .. (p and v3(p) or "") .. attrs(c)
end
save("robberies.txt", table.concat(out, NL))
note("robberies / map written")

-- 5) remotes ------------------------------------------------------------------------------------------------------
out = {}
for _, d in ipairs(RS:GetDescendants()) do
	if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then out[#out + 1] = d.ClassName .. "  " .. full(d) .. attrs(d) end
end
save("remotes.txt", table.concat(out, NL))

-- 6) you + inventory --------------------------------------------------------------------------------------------
out = {}
out[#out + 1] = "player attrs:" .. attrs(lp)
local ls = lp:FindFirstChild("leaderstats")
for _, v in ipairs(ls and ls:GetChildren() or {}) do out[#out + 1] = "leaderstats." .. v.Name .. " = " .. tostring(v.Value) end
local c = lp.Character
if c then
	out[#out + 1] = "character attrs:" .. attrs(c)
	local hrp = c:FindFirstChild("HumanoidRootPart")
	if hrp then out[#out + 1] = "hrp at " .. v3(hrp.Position) .. attrs(hrp) end
end
out[#out + 1] = ("Lighting.ClockTime=%.2f  TimeOfDay=%s  workspace attrs%s"):format(Lighting.ClockTime, tostring(Lighting.TimeOfDay), attrs(workspace))
out[#out + 1] = "ReplicatedStorage attrs" .. attrs(RS)
out[#out + 1] = "---- PlayerGui screens ----"
for _, g in ipairs(lp.PlayerGui:GetChildren()) do out[#out + 1] = "  " .. g.Name .. " (" .. g.ClassName .. ", " .. #g:GetDescendants() .. " objects)" end
out[#out + 1] = "---- text on screen that mentions bomb / money / $ / inventory ----"
local shown = 0
for _, d in ipairs(lp.PlayerGui:GetDescendants()) do
	if d:IsA("TextLabel") and d.Text ~= "" and shown < 40 then
		local low = d.Text:lower()
		if low:find("bomb") or low:find("inventor") or low:find("%$") or low:find("€") then shown = shown + 1; out[#out + 1] = "  " .. full(d) .. " = '" .. d.Text:sub(1, 50) .. "'" end
	end
end
out[#out + 1] = "---- tables in memory that have a Bomb / Gold / Money key (inventory-looking) ----"
if getgc then
	local n, found = 0, 0
	for _, t in ipairs(getgc(true)) do
		n = n + 1
		if n % 4000 == 0 then task.wait() end
		if not running then break end
		if type(t) == "table" and found < 25 then
			local okk, hit = pcall(function() return rawget(t, "Bomb") ~= nil or rawget(t, "bomb") ~= nil or rawget(t, "Gold") ~= nil end)
			if okk and hit then
				found = found + 1
				local p, cnt = {}, 0
				for k, v in pairs(t) do
					cnt = cnt + 1
					if cnt > 10 then break end
					p[#p + 1] = tostring(k) .. "=" .. tostring(v):sub(1, 24)
				end
				out[#out + 1] = "  {" .. table.concat(p, ", ") .. "}"
			end
		end
	end
end
save("player.txt", table.concat(out, NL))

note("DONE " .. os.date("%H:%M:%S") .. "  -> workspace/" .. DIR .. "/")
save("index.txt", table.concat(index, NL))
pcall(function() setclipboard(table.concat(index, NL)) end)
print("[dump] DONE - files are in workspace/" .. DIR)
