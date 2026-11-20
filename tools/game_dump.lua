-- Game dump: a snapshot of how any Roblox game is built, for the owner of the game to read. Run it once in the game, wait for the "finished" line.
-- Output (executor workspace):  scrdsx_dump_<placeid>.txt  (overview, remotes, tags, teams, interface, scripts list)
--                               scrdsx_dump_scripts_<placeid>.txt  (decompiled client scripts, capped)
-- Optional, set BEFORE running:  getgenv().DumpSpy = 25  records the remote calls you make for that many seconds (do the actions you care about while it records)
--                                getgenv().DumpScripts = 40  how many scripts to decompile (default 40, 0 = skip)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local MPS = game:GetService("MarketplaceService")
local lp = Players.LocalPlayer
local env = getgenv and getgenv() or _G
local PID = tostring(game.PlaceId)
local MAIN, SCRIPTS = "scrdsx_dump_" .. PID .. ".txt", "scrdsx_dump_scripts_" .. PID .. ".txt"
local out, sout = {}, {}
local function log(s) out[#out + 1] = tostring(s) end
local function slog(s) sout[#sout + 1] = tostring(s) end
local function save()
	if type(writefile) ~= "function" then print(table.concat(out, "\n")); return end
	pcall(function() writefile(MAIN, table.concat(out, "\n")) end)
	if #sout > 0 then pcall(function() writefile(SCRIPTS, table.concat(sout, "\n")) end) end
end
local function attrs(inst)
	local t = {}
	local ok, a = pcall(function() return inst:GetAttributes() end)
	if ok then for k, v in pairs(a) do t[#t + 1] = k .. "=" .. tostring(v) end end
	table.sort(t)
	return table.concat(t, ", ")
end
local function short(v)
	local tv = typeof(v)
	if tv == "Instance" then return "Instance<" .. v.ClassName .. ">" .. v:GetFullName():sub(-60) end
	if tv == "string" then return ('"%s"'):format(v:sub(1, 40)) end
	if tv == "table" then
		local n = 0
		for _ in pairs(v) do n = n + 1 end
		return "table(" .. n .. ")"
	end
	return tv .. ":" .. tostring(v):sub(1, 40)
end

local ok, err = pcall(function()
	-- 1) overview ------------------------------------------------------------------------------------------------
	log("== OVERVIEW ==")
	local name = "?"
	pcall(function() name = MPS:GetProductInfo(game.PlaceId).Name end)
	log(("game: %s  placeId=%s  universeId=%s  placeVersion=%s  creator=%s/%s"):format(name, PID, tostring(game.GameId), tostring(game.PlaceVersion), tostring(game.CreatorType), tostring(game.CreatorId)))
	local ex = "unknown"
	pcall(function() ex = table.concat({ identifyexecutor() }, " ") end)
	log("executor: " .. ex)
	local fns = {}
	for _, n in ipairs({ "hookfunction", "hookmetamethod", "getgc", "getscripts", "getloadedmodules", "decompile", "getconnections", "getrawmetatable", "newcclosure", "checkcaller", "firesignal", "fireproximityprompt", "firetouchinterest", "setclipboard", "request", "writefile", "getcustomasset", "gethui", "getnilinstances", "isexecutorclosure", "debug.getconstants", "debug.getupvalues" }) do
		local okf, v = pcall(function() return loadstring("return " .. n)() end)
		fns[#fns + 1] = n .. "=" .. tostring(okf and v ~= nil)
	end
	log("functions: " .. table.concat(fns, " "))
	log(("streaming=%s  players=%d  localplayer=%s (%d)  team=%s"):format(tostring(workspace.StreamingEnabled), #Players:GetPlayers(), lp.Name, lp.UserId, tostring(lp.Team and lp.Team.Name)))
	log("player attributes: " .. attrs(lp))
	if lp.Character then log("character attributes: " .. attrs(lp.Character)) end
	local ls = lp:FindFirstChild("leaderstats")
	if ls then
		local t = {}
		for _, c in ipairs(ls:GetChildren()) do t[#t + 1] = c.Name .. "=" .. tostring(c:IsA("ValueBase") and c.Value) end
		log("leaderstats: " .. table.concat(t, ", "))
	end
	log("workspace attributes: " .. attrs(workspace))
	log("replicatedstorage attributes: " .. attrs(RS))
	log("lighting: ClockTime=" .. tostring(Lighting.ClockTime) .. " Technology=" .. tostring(pcall(function() return Lighting.Technology end) and Lighting.Technology or "?"))
	save()

	-- 2) teams ---------------------------------------------------------------------------------------------------
	log("\n== TEAMS ==")
	for _, t in ipairs(game:GetService("Teams"):GetChildren()) do
		local n = 0
		for _, p in ipairs(Players:GetPlayers()) do if p.Team == t then n = n + 1 end end
		log(("%s  color=%s  players=%d"):format(t.Name, tostring(t:IsA("Team") and t.TeamColor), n))
	end

	-- 3) remotes -------------------------------------------------------------------------------------------------
	log("\n== REMOTES (RemoteEvent / RemoteFunction / BindableEvent) ==")
	local rcount, roots = 0, { RS, game:GetService("ReplicatedFirst"), workspace, game:GetService("StarterGui"), game:GetService("StarterPack") }
	for _, root in ipairs(roots) do
		for i, d in ipairs(root:GetDescendants()) do
			if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
				rcount = rcount + 1
				if rcount <= 600 then log(("%s  %s"):format(d.ClassName, d:GetFullName())) end
			end
			if i % 800 == 0 then task.wait() end
		end
	end
	log("remote count: " .. rcount)
	save()

	-- 4) collision tags -----------------------------------------------------------------------------------------
	log("\n== TAGS (count, example, attributes of the example) ==")
	local tags = CS:GetAllTags()
	table.sort(tags)
	for _, tg in ipairs(tags) do
		local list = CS:GetTagged(tg)
		local s = list[1]
		log(("%s  x%d  e.g. %s  [%s]"):format(tg, #list, s and s:GetFullName():sub(-90) or "-", s and attrs(s) or ""))
	end
	save()

	-- 5) world structure ----------------------------------------------------------------------------------------
	log("\n== WORKSPACE (top level: name, class, descendants) ==")
	for _, c in ipairs(workspace:GetChildren()) do
		local n = 0
		pcall(function() n = #c:GetDescendants() end)
		log(("%s  %s  %d  [%s]"):format(c.Name, c.ClassName, n, attrs(c)))
	end
	log("\n== REPLICATEDSTORAGE (top level) ==")
	for _, c in ipairs(RS:GetChildren()) do
		local n = 0
		pcall(function() n = #c:GetDescendants() end)
		log(("%s  %s  %d"):format(c.Name, c.ClassName, n))
	end
	save()

	-- 6) interface -----------------------------------------------------------------------------------------------
	log("\n== INTERFACE (your PlayerGui, 2 levels) ==")
	local pg = lp:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, sg in ipairs(pg:GetChildren()) do
			if not tostring(sg.Name):match("^%d+$") then -- skip our own windows (numeric names)
				log(("%s  %s  enabled=%s  children=%d"):format(sg.Name, sg.ClassName, tostring(sg:IsA("ScreenGui") and sg.Enabled), #sg:GetChildren()))
				for _, c in ipairs(sg:GetChildren()) do
					local txt = ""
					if c:IsA("TextLabel") or c:IsA("TextButton") then txt = ' text="' .. c.Text:sub(1, 30) .. '"' end
					log(("    %s  %s%s"):format(c.Name, c.ClassName, txt))
				end
			end
		end
	end
	save()

	-- 7) scripts: list + decompile -----------------------------------------------------------------------------
	log("\n== CLIENT SCRIPTS AND MODULES (names) ==")
	local list, seen = {}, {}
	local function add(s)
		if s and not seen[s] then seen[s] = true; list[#list + 1] = s end
	end
	if getscripts then for _, s in ipairs(getscripts()) do add(s) end end
	if getloadedmodules then for _, s in ipairs(getloadedmodules()) do add(s) end end
	local rows = {}
	for _, s in ipairs(list) do
		local full = "?"
		pcall(function() full = s:GetFullName() end)
		if not full:find("CoreGui", 1, true) and not full:find("RobloxGui", 1, true) and not full:match("PlayerModule") then rows[#rows + 1] = { s, full } end
	end
	table.sort(rows, function(a, b) return a[2] < b[2] end)
	log("count: " .. #rows)
	for i, r in ipairs(rows) do if i <= 700 then log(r[2] .. "  (" .. r[1].ClassName .. ")") end end
	save()

	local want = tonumber(env.DumpScripts)
	if want == nil then want = 40 end
	if want > 0 and decompile then
		-- game scripts first (ReplicatedStorage / PlayerScripts / PlayerGui / StarterPlayer), the rest after
		local function prio(full) return (full:find("ReplicatedStorage", 1, true) and 1) or (full:find("PlayerScripts", 1, true) and 1) or (full:find("PlayerGui", 1, true) and 2) or 3 end
		table.sort(rows, function(a, b)
			local pa, pb = prio(a[2]), prio(b[2])
			if pa ~= pb then return pa < pb end
			return a[2] < b[2]
		end)
		local t0, done = os.clock(), 0
		for _, r in ipairs(rows) do
			if done >= want or os.clock() - t0 > 55 then break end
			local okd, src = pcall(decompile, r[1])
			if okd and type(src) == "string" and #src > 0 then
				done = done + 1
				slog(("\n----- %s (%d chars) -----"):format(r[2], #src))
				slog(#src > 14000 and (src:sub(1, 14000) .. "\n-- [cut]") or src)
			end
			if done % 5 == 0 then save() end
			task.wait()
		end
		log(("decompiled %d scripts into %s"):format(done, SCRIPTS))
	end
	save()

	-- 8) optional: record the remote calls you make ---------------------------------------------------------------
	local spy = tonumber(env.DumpSpy) or 0
	if spy > 0 and type(hookfunction) == "function" then
		log("\n== REMOTE CALLS RECORDED FOR " .. spy .. " s (name | argument types) ==")
		print("[dump] recording remote calls for " .. spy .. " s: do the actions you care about now")
		local seenSig, count = {}, 0
		local function rec(kind, remote, ...)
			local a = { ... }
			local parts = {}
			for i = 1, math.min(#a, 6) do parts[#parts + 1] = short(a[i]) end
			local sig = remote:GetFullName() .. "|" .. table.concat(parts, ",")
			if not seenSig[sig] and count < 300 then
				seenSig[sig] = true; count = count + 1
				log(("%s  %s  (%s)"):format(kind, remote:GetFullName(), table.concat(parts, ", ")))
			end
		end
		local oldFS, oldIS
		pcall(function()
			oldFS = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
				if typeof(self) == "Instance" then pcall(rec, "FireServer", self, ...) end
				return oldFS(self, ...)
			end)
			oldIS = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
				if typeof(self) == "Instance" then pcall(rec, "InvokeServer", self, ...) end
				return oldIS(self, ...)
			end)
		end)
		task.wait(spy)
		pcall(function() if oldFS then hookfunction(Instance.new("RemoteEvent").FireServer, oldFS) end end)
		log("recorded " .. count .. " distinct calls")
		save()
	end
end)
if not ok then log("\nDUMP ERROR: " .. tostring(err)); warn("[dump] error: " .. tostring(err)) end
save()
print("[dump] finished: " .. MAIN .. (#sout > 0 and (" and " .. SCRIPTS) or ""))
