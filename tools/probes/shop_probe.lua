-- Shop probe: how the game knows a shop/robbery is open, closed, on cooldown or risky. Output: scrdsx_shop_probe.txt in the executor workspace.
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local lp = Players.LocalPlayer
local out = {}
local function log(s) out[#out + 1] = tostring(s) end
local function save()
	if type(writefile) ~= "function" then print(table.concat(out, "\n")); return end
	pcall(function() writefile("scrdsx_shop_probe.txt", table.concat(out, "\n")) end)
end
local function attrs(i)
	local p = {}
	local ok, at = pcall(i.GetAttributes, i)
	if ok then for k, v in pairs(at) do p[#p + 1] = k .. "=" .. tostring(v) end end
	table.sort(p)
	return table.concat(p, ", ")
end
local function tree(inst, depth, maxDepth, budget)
	if depth > maxDepth or budget.n <= 0 then return end
	for _, c in ipairs(inst:GetChildren()) do
		if budget.n <= 0 then return end
		budget.n = budget.n - 1
		local a = attrs(c)
		local tags = {}
		pcall(function() for _, t in ipairs(CS:GetTags(c)) do tags[#tags + 1] = t end end)
		local extra = ""
		if c:IsA("ValueBase") then extra = " value=" .. tostring(c.Value) end
		log(("%s%s [%s]%s%s%s"):format(("  "):rep(depth), c.Name, c.ClassName, extra, a ~= "" and ("  {" .. a .. "}") or "", #tags > 0 and ("  tags: " .. table.concat(tags, "|")) or ""))
		tree(c, depth + 1, maxDepth, budget)
	end
end

local ok, err = pcall(function()
	log("-- police players online: " .. (function() local n = 0 for _, p in ipairs(Players:GetPlayers()) do if p.Team and p.Team.Name == "Police" then n = n + 1 end end return n end)() .. " of " .. #Players:GetPlayers())
	log("-- teams: " .. (function() local t = {} for _, x in ipairs(Teams:GetChildren()) do t[#t + 1] = x.Name .. "(" .. #x:GetPlayers() .. ")" end return table.concat(t, ", ") end)())
	log("-- ClockTime " .. tostring(game:GetService("Lighting").ClockTime) .. "  server time " .. tostring(workspace:GetServerTimeNow()))
	log("-- workspace attributes: " .. attrs(workspace))
	log("-- ReplicatedStorage attributes: " .. attrs(RS))

	log("\n===== Workspace.Robberies (3 levels) =====")
	local r = workspace:FindFirstChild("Robberies")
	if r then tree(r, 0, 3, { n = 260 }) else log("no Workspace.Robberies") end
	save()

	log("\n===== workspace top-level folders =====")
	for _, c in ipairs(workspace:GetChildren()) do
		if not c:IsA("Terrain") and c.ClassName ~= "Camera" and not Players:GetPlayerFromCharacter(c) then log(c.Name .. " [" .. c.ClassName .. "] {" .. attrs(c) .. "} children=" .. #c:GetChildren()) end
	end

	log("\n===== tags that look like shops / robberies / stores (count + first sample with attributes) =====")
	for _, tg in ipairs(CS:GetAllTags()) do
		local l = tg:lower()
		if l:find("rob") or l:find("store") or l:find("shop") or l:find("bank") or l:find("jewel") or l:find("safe") or l:find("register") or l:find("alarm") or l:find("vault") then
			local list = CS:GetTagged(tg)
			log(("%s x%d"):format(tg, #list))
			for i = 1, math.min(#list, 3) do log("   " .. list[i]:GetFullName() .. "  {" .. attrs(list[i]) .. "}") end
		end
	end
	save()

	log("\n===== shop / store models in Workspace.Buildings (name + attributes, first 40) =====")
	local b = workspace:FindFirstChild("Buildings")
	local n = 0
	for _, m in ipairs(b and b:GetChildren() or {}) do
		n = n + 1
		if n <= 40 then log(m.Name .. " [" .. m.ClassName .. "] {" .. attrs(m) .. "}  children: " .. (function() local t = {} for i, c in ipairs(m:GetChildren()) do if i <= 12 then t[#t + 1] = c.Name end end return table.concat(t, ", ") end)()) end
	end

	log("\n===== robbery / store / opening-hours scripts =====")
	local roots = {}
	if getscripts then for _, s in ipairs(getscripts()) do roots[#roots + 1] = s end end
	if getloadedmodules then for _, s in ipairs(getloadedmodules()) do roots[#roots + 1] = s end end
	local WANT = { "robbery", "robberies", "storelifecycle", "storeconfig", "openinghours", "storehours", "jewellery", "lifecycle", "robbable" }
	local t0, found, seen = os.clock(), 0, {}
	for i, s in ipairs(roots) do
		if os.clock() - t0 > 45 or found >= 8 then break end
		if not seen[s] then
			seen[s] = true
			local l = s.Name:lower()
			local hit = false
			for _, w in ipairs(WANT) do if l:find(w, 1, true) then hit = true break end end
			if hit and decompile then
				local okd, src = pcall(decompile, s)
				if okd and type(src) == "string" then
					found = found + 1
					log("\n----- " .. s:GetFullName() .. " (" .. #src .. " chars) -----")
					log(#src > 30000 and src:sub(1, 30000) or src)
				end
			end
		end
		if i % 40 == 0 then task.wait() end
	end
	log("\nscripts matched: " .. found)
end)
if not ok then log("\nPROBE ERROR: " .. tostring(err)); warn("[shop probe] error: " .. tostring(err)) end
save()
print("[shop probe] finished, saved scrdsx_shop_probe.txt")
