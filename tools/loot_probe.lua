-- Loot probe: finds how the game does pickups now. Run it once, then tell Claude "done". Output: scrdsx_loot_probe.txt in the executor workspace.
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function save()
	if type(writefile) ~= "function" then print(table.concat(out, "
")); return end pcall(function() writefile("scrdsx_loot_probe.txt", table.concat(out, "\n")) end) end

local ok, err = pcall(function()
log("-- executor functions --")
for _, n in ipairs({ "hookfunction", "hookmetamethod", "getgc", "getscripts", "getloadedmodules", "decompile", "getnilinstances", "getconnections", "getrawmetatable", "newcclosure", "checkcaller", "firesignal", "fireproximityprompt" }) do
	log(n .. " = " .. tostring(type(getgenv()[n]) == "function"))
end

log("\n-- tags with Collect/Interact in the name (count, sample) --")
for _, tg in ipairs(CS:GetAllTags()) do
	local l = tg:lower()
	if l:find("collect") or l:find("interact") or l:find("loot") or l:find("pickup") then
		local list = CS:GetTagged(tg)
		local s = list[1]
		local attrs = {}
		if s then for k, v in pairs(s:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. tostring(v) end end
		log(("%s  x%d  e.g. %s  [%s]"):format(tg, #list, s and s:GetFullName() or "-", table.concat(attrs, ", ")))
	end
end

log("\n-- remotes in ReplicatedStorage (class, path) --")
local n = 0
for _, d in ipairs(RS:GetDescendants()) do
	if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
		n = n + 1
		if n <= 400 then log(d.ClassName .. "  " .. d:GetFullName()) end
	end
end
log("total remotes: " .. n)

log("\n-- scripts whose source mentions interaction / collecting --")
local function try(fn, ...) local ok, r = pcall(fn, ...); return ok and r or nil end
local found = 0
local roots = {}
if getscripts then for _, s in ipairs(getscripts()) do roots[#roots + 1] = s end end
if getloadedmodules then for _, s in ipairs(getloadedmodules()) do roots[#roots + 1] = s end end
if #roots == 0 then
	for _, svc in ipairs({ RS, lp:FindFirstChild("PlayerScripts"), lp:FindFirstChild("PlayerGui") }) do
		if svc then for _, d in ipairs(svc:GetDescendants()) do if d:IsA("LuaSourceContainer") then roots[#roots + 1] = d end end end
	end
end
local seen = {}
for _, s in ipairs(roots) do
	if not seen[s] and found < 6 then
		seen[s] = true
		local src = decompile and try(decompile, s)
		if type(src) == "string" and (src:find("Collect Interactable", 1, true) or src:find("Interactable", 1, true) and src:find("FireServer", 1, true)) then
			found = found + 1
			log("\n===== " .. s:GetFullName() .. " (" .. #src .. " chars) =====")
			log(#src > 60000 and src:sub(1, 60000) or src)
		end
	end
	if _ % 40 == 0 then task.wait() end
end
log("\nscripts matched: " .. found .. " of " .. #roots)


end)
if not ok then log("
PROBE ERROR: " .. tostring(err)); warn("[loot probe] error: " .. tostring(err)) end
save()
print("[loot probe] finished, saved scrdsx_loot_probe.txt (writefile exists: " .. tostring(type(writefile) == "function") .. ")")
