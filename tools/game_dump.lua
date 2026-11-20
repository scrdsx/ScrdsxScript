-- Game dump: a snapshot of how any Roblox game is built, for the owner of the game to read. Run it once in the game.
-- A small bar at the top of the screen shows a countdown while it works. During that time the remote calls YOU make are recorded too, so go and do the things you
-- care about. When it is done the bar says "Saved" and disappears.
-- Output (executor workspace):  scrdsx_dump_<placeid>.txt          (overview, remotes, tags, teams, interface, script list, recorded remote calls)
--                               scrdsx_dump_scripts_<placeid>.txt  (decompiled client scripts, capped)
-- Optional, set BEFORE running:  getgenv().DumpSpy = 40      seconds to record (default 40, 0 = no recording, the bar still shows progress)
--                                getgenv().DumpScripts = 40  how many scripts to decompile (default 40, 0 = skip)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local MPS = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")
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

-- progress bar ----------------------------------------------------------------------------------------------------------------
local gui, pill, pillText, dot
local function guiParent()
	local okh, h = pcall(function() return gethui and gethui() end)
	if okh and h then return h end
	okh, h = pcall(function() return game:GetService("CoreGui") end)
	if okh and h then return h end
	return lp:WaitForChild("PlayerGui")
end
if not env.DumpQuiet then pcall(function()
	gui = Instance.new("ScreenGui")
	gui.Name = tostring(math.random(1e6, 9e6)); gui.ResetOnSpawn = false; gui.IgnoreGuiInset = true; gui.DisplayOrder = 1000; gui.Parent = guiParent()
	pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(.5, 0); pill.Position = UDim2.new(.5, 0, 0, 16); pill.Size = UDim2.fromOffset(0, 34); pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = Color3.fromRGB(21, 21, 24); pill.BackgroundTransparency = 0.05; pill.BorderSizePixel = 0; pill.Parent = gui
	Instance.new("UICorner", pill).CornerRadius = UDim.new(1, 0)
	local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(52, 52, 58); st.Parent = pill
	local pd = Instance.new("UIPadding"); pd.PaddingLeft = UDim.new(0, 14); pd.PaddingRight = UDim.new(0, 18); pd.Parent = pill
	dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0, .5); dot.Position = UDim2.new(0, 0, .5, 0); dot.Size = UDim2.fromOffset(9, 9); dot.BorderSizePixel = 0; dot.BackgroundColor3 = Color3.fromRGB(240, 180, 60); dot.Parent = pill
	Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	pillText = Instance.new("TextLabel")
	pillText.BackgroundTransparency = 1; pillText.Position = UDim2.fromOffset(18, 0); pillText.Size = UDim2.fromOffset(0, 34); pillText.AutomaticSize = Enum.AutomaticSize.X
	pillText.Font = Enum.Font.BuilderSansBold; pillText.TextSize = 14; pillText.TextColor3 = Color3.fromRGB(240, 240, 245); pillText.Text = "Dump starting..."; pillText.Parent = pill
end) end
local function status(txt, color)
	if pillText then pillText.Text = txt end
	if dot and color then dot.BackgroundColor3 = color end
end

-- remote-call recording: starts right away and runs while the rest of the dump is working --------------------------------------
local spySeconds = env.DumpSpy
if spySeconds == nil then spySeconds = 40 end
spySeconds = tonumber(spySeconds) or 0
local spyEnd = os.clock() + spySeconds
local spyLines, spySeen, spyCount = {}, {}, 0
local oldFS, oldIS
if spySeconds > 0 and type(hookfunction) == "function" then
	local function rec(kind, remote, ...)
		local a = { ... }
		local parts = {}
		for i = 1, math.min(#a, 6) do parts[#parts + 1] = short(a[i]) end
		local sig = remote:GetFullName() .. "|" .. table.concat(parts, ",")
		if not spySeen[sig] and spyCount < 300 then
			spySeen[sig] = true; spyCount = spyCount + 1
			spyLines[#spyLines + 1] = ("%s  %s  (%s)"):format(kind, remote:GetFullName(), table.concat(parts, ", "))
		end
	end
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
end
local finished = false
task.spawn(function()
	while not finished do
		local left = math.max(0, math.ceil(spyEnd - os.clock()))
		if spySeconds > 0 and left > 0 then status(("Dumping + recording   %d s left   (go do your stuff)"):format(left), Color3.fromRGB(240, 180, 60))
		else status("Finishing the dump...", Color3.fromRGB(240, 180, 60)) end
		task.wait(0.25)
	end
end)

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
	log("lighting: ClockTime=" .. tostring(Lighting.ClockTime))
	save()

	-- 2) teams ---------------------------------------------------------------------------------------------------
	log("\n== TEAMS ==")
	for _, t in ipairs(game:GetService("Teams"):GetChildren()) do
		local n = 0
		for _, p in ipairs(Players:GetPlayers()) do if p.Team == t then n = n + 1 end end
		log(("%s  color=%s  players=%d"):format(t.Name, tostring(t:IsA("Team") and t.TeamColor), n))
	end

	-- 3) remotes -------------------------------------------------------------------------------------------------
	log("\n== REMOTES (RemoteEvent / RemoteFunction) ==")
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
		-- game scripts first (ReplicatedStorage / PlayerScripts / PlayerGui), the rest after
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
end)
if not ok then log("\nDUMP ERROR: " .. tostring(err)); warn("[dump] error: " .. tostring(err)) end

-- let the recording window run out (the dump is usually done before it), then stop it and add what was recorded
while spySeconds > 0 and os.clock() < spyEnd do task.wait(0.25) end
pcall(function() if oldFS then hookfunction(Instance.new("RemoteEvent").FireServer, oldFS) end end)
if spySeconds > 0 then
	log("\n== REMOTE CALLS RECORDED FOR " .. spySeconds .. " s (kind  remote  (argument types)) ==")
	for _, l in ipairs(spyLines) do log(l) end
	log("recorded " .. spyCount .. " distinct calls")
end
save()
finished = true
if ok then status("Saved  -  " .. MAIN, Color3.fromRGB(70, 200, 120)) else status("Dump hit an error, see the console", Color3.fromRGB(240, 90, 80)) end
print("[dump] finished: " .. MAIN .. (#sout > 0 and (" and " .. SCRIPTS) or ""))
task.wait(4)
if pill then
	pcall(function()
		TweenService:Create(pill, TweenInfo.new(.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(pillText, TweenInfo.new(.4), { TextTransparency = 1 }):Play()
		TweenService:Create(dot, TweenInfo.new(.4), { BackgroundTransparency = 1 }):Play()
	end)
	task.wait(.5)
end
pcall(function() if gui then gui:Destroy() end end)
