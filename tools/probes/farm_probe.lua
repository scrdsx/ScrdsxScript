-- farm_probe.lua : static dump for the AutoFarm tab (robberies). Run it anywhere, ~10-20s. Report -> clipboard + workspace/farm_report.txt
-- Dumps: Workspace.Robberies trees (state attributes, cashiers, safes, prompts), Interactables (dealers/shops), game modules that
-- mention robbery/bomb/safe/dealer (prices, requirements, cooldowns), bomb-ish items, your inventory + money, tags.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local lp = Players.LocalPlayer
print("[farm] started - wait for 'done'")

local out = {}
local function log(s) out[#out + 1] = s end
local function v3(v) return ("(%.0f, %.0f, %.0f)"):format(v.X, v.Y, v.Z) end
local function full(i) local ok, r = pcall(game.GetFullName, i); return ok and r or tostring(i) end
local function attrs(i)
	local t = {}
	for k, v in pairs(i:GetAttributes()) do t[#t + 1] = k .. "=" .. tostring(v):sub(1, 40) end
	table.sort(t)
	return #t > 0 and (" [" .. table.concat(t, ", ") .. "]") or ""
end
local function tagsOf(i)
	local ok, t = pcall(CS.GetTags, CS, i)
	return (ok and type(t) == "table" and #t > 0) and (" {tags: " .. table.concat(t, ",") .. "}") or ""
end
local function where(inst)
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Model") then
		local ok, cf = pcall(function() return inst:GetBoundingBox() end)
		if ok then return cf.Position end
	end
	local sum, n = Vector3.zero, 0
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then sum = sum + d.Position; n = n + 1 end
	end
	if n > 0 then return sum / n end
end

local KEY = { "rob", "bomb", "safe", "cashier", "dealer", "vault", "heist", "explos", "dynamite", "c4", "thermite", "drill", "register", "teller",
	"blackmarket", "black market", "gold", "loot", "crack", "lockpick", "crowbar", "cash" }
local function match(n)
	n = n:lower()
	for _, k in ipairs(KEY) do if n:find(k, 1, true) then return true end end
	return false
end

-- tree of an instance, identical siblings collapsed ("x12"), capped
local function tree(root, maxDepth, maxLines)
	local lines = 0
	local function rec(inst, depth, indent)
		local groups, order = {}, {}
		for _, k in ipairs(inst:GetChildren()) do
			local key = k.Name .. "|" .. k.ClassName
			if not groups[key] then groups[key] = { n = 0, first = k }; order[#order + 1] = key end
			groups[key].n = groups[key].n + 1
		end
		for _, key in ipairs(order) do
			if lines >= maxLines then log(indent .. "..."); return end
			local g = groups[key]
			local k = g.first
			local extra = ""
			if k:IsA("BasePart") then extra = " @" .. v3(k.Position) .. " size " .. v3(k.Size) end
			if k:IsA("ProximityPrompt") then
				extra = (" PROMPT '%s'/'%s' hold=%s dist=%s enabled=%s"):format(k.ObjectText, k.ActionText, tostring(k.HoldDuration), tostring(k.MaxActivationDistance), tostring(k.Enabled))
			end
			if k:IsA("ClickDetector") then extra = " CLICKDETECTOR dist=" .. tostring(k.MaxActivationDistance) end
			if k:IsA("ValueBase") then extra = " = " .. tostring(k.Value):sub(1, 60) end
			if k:IsA("Humanoid") then extra = (" HUMANOID hp=%d"):format(k.Health) end
			log(indent .. k.Name .. " (" .. k.ClassName .. ")" .. (g.n > 1 and (" x" .. g.n) or "") .. extra .. attrs(k) .. tagsOf(k))
			lines = lines + 1
			if depth < maxDepth then rec(k, depth + 1, indent .. "  ") end
		end
	end
	rec(root, 1, "    ")
end

local function dump(v, depth, indent, budget)
	local t = typeof(v)
	if t == "table" then
		if depth > 3 then log(indent .. "{...}"); return end
		local keys = {}
		for k in pairs(v) do keys[#keys + 1] = k end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for i, k in ipairs(keys) do
			if budget.n <= 0 then return end
			if i > 30 then log(indent .. "... (" .. #keys .. " keys)"); return end
			local x = v[k]
			budget.n = budget.n - 1
			if typeof(x) == "table" then
				log(indent .. tostring(k) .. " = {")
				dump(x, depth + 1, indent .. "  ", budget)
				log(indent .. "}")
			else
				log(indent .. tostring(k) .. " = " .. (typeof(x) == "Instance" and ("<" .. full(x) .. ">") or tostring(x):sub(1, 80)) .. (typeof(x) == "function" and "" or ""))
			end
		end
	end
end

local function tryRequire(m)
	local done, ok, res = false, false, nil
	task.spawn(function() ok, res = pcall(require, m); done = true end)
	local t = os.clock()
	while not done and os.clock() - t < 3 do task.wait(0.05) end
	return done and ok, res
end

-- 1) robberies ---------------------------------------------------------------------------------------------
log("== Workspace top-level ==")
local names = {}
for _, c in ipairs(workspace:GetChildren()) do names[#names + 1] = c.Name end
log("  " .. table.concat(names, ", "):sub(1, 1200))

log("== Workspace.Robberies ==")
local rob = workspace:FindFirstChild("Robberies")
if rob then
	for _, c in ipairs(rob:GetChildren()) do
		local p = where(c)
		log(("-- %s (%s) at %s%s%s"):format(c.Name, c.ClassName, p and v3(p) or "?", attrs(c), tagsOf(c)))
		tree(c, 4, 90)
	end
else
	log("  (no Robberies folder - robbery objects may live elsewhere, see the keyword search below)")
end

-- 2) interactables ---------------------------------------------------------------------------------------------
log("== Workspace.Interactables (grouped) ==")
local inter = workspace:FindFirstChild("Interactables")
if inter then
	for _, folder in ipairs(inter:GetChildren()) do
		local kids = folder:GetChildren()
		log(("-- %s (%s) children=%d%s"):format(folder.Name, folder.ClassName, #kids, attrs(folder)))
		for i = 1, math.min(#kids, 4) do
			local k = kids[i]
			local p = where(k)
			log(("     %s (%s) %s%s%s"):format(k.Name, k.ClassName, p and v3(p) or "", attrs(k), tagsOf(k)))
			for _, d in ipairs(k:GetDescendants()) do
				if d:IsA("ProximityPrompt") then
					log(("       PROMPT '%s'/'%s' hold=%s on %s"):format(d.ObjectText, d.ActionText, tostring(d.HoldDuration), d.Parent and d.Parent.Name or "?"))
					break
				end
			end
		end
	end
else
	log("  (no Interactables folder)")
end

-- 3) keyword search in the whole workspace ----------------------------------------------------------------
log("== workspace objects whose name looks robbery / bomb / dealer related ==")
local hits, scanned = 0, 0
for _, d in ipairs(workspace:GetDescendants()) do
	scanned = scanned + 1
	if scanned % 4000 == 0 then task.wait() end
	if match(d.Name) and not d:IsDescendantOf(workspace.CurrentCamera) and (d:IsA("Model") or d:IsA("BasePart") or d:IsA("Folder") or d:IsA("ProximityPrompt")) then
		local fp = full(d)
		if not fp:find("Workspace.Robberies", 1, true) and not fp:find("Workspace.Vehicles", 1, true) and not fp:find("Workspace." .. lp.Name, 1, true) then
			hits = hits + 1
			if hits <= 70 then
				local p = where(d)
				log(("  %s (%s) %s%s"):format(fp, d.ClassName, p and v3(p) or "", attrs(d)))
			end
		end
	end
end
log(("  (%d hits)"):format(hits))

-- 4) game modules / items ------------------------------------------------------------------------------------------
log("== ReplicatedStorage items / modules that look related ==")
local mods = {}
for _, d in ipairs(RS:GetDescendants()) do
	if match(d.Name) or (d:IsA("ModuleScript") and match(full(d))) then
		log("  " .. full(d) .. " (" .. d.ClassName .. ")" .. attrs(d))
		if d:IsA("ModuleScript") and #mods < 25 then mods[#mods + 1] = d end
	end
end
for _, m in ipairs(mods) do
	local ok, res = tryRequire(m)
	log("-- require " .. full(m) .. " : " .. (ok and typeof(res) or "failed/timeout"))
	if ok and typeof(res) == "table" then dump(res, 1, "    ", { n = 45 }) end
end

-- 5) you ------------------------------------------------------------------------------------------------------
log("== you ==")
local function listTools(holder, label)
	if not holder then return end
	local t = {}
	for _, c in ipairs(holder:GetChildren()) do t[#t + 1] = c.Name .. "(" .. c.ClassName .. ")" .. attrs(c) end
	log("  " .. label .. ": " .. (#t > 0 and table.concat(t, ", ") or "(empty)"))
end
listTools(lp:FindFirstChild("Backpack"), "Backpack")
listTools(lp.Character, "Character children")
log("  player attributes:" .. attrs(lp))
local ls = lp:FindFirstChild("leaderstats")
if ls then for _, v in ipairs(ls:GetChildren()) do log("  leaderstats." .. v.Name .. " = " .. tostring(v.Value)) end end
local shown = 0
for _, d in ipairs(lp.PlayerGui:GetDescendants()) do
	if d:IsA("TextLabel") and d.Text:find("%$") and shown < 6 then
		shown = shown + 1
		log("  money-looking label: " .. full(d) .. " = '" .. d.Text:sub(1, 40) .. "'")
	end
end
local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
if hrp then log("  you are at " .. v3(hrp.Position)) end

-- 6) tags ---------------------------------------------------------------------------------------------------------
log("== CollectionService tags ==")
local ok, all = pcall(CS.GetAllTags, CS)
if ok and type(all) == "table" then
	table.sort(all)
	local t = {}
	for _, tg in ipairs(all) do
		local okc, n = pcall(function() return #CS:GetTagged(tg) end)
		t[#t + 1] = tg .. "(" .. (okc and n or "?") .. ")"
	end
	log("  " .. table.concat(t, ", "):sub(1, 2500))
else
	log("  (GetAllTags not available)")
end

local txt = table.concat(out, "\n")
local okc = pcall(function() setclipboard(txt) end)
pcall(function() writefile("farm_report.txt", txt) end)
print("[farm] done - " .. #out .. " lines " .. (okc and "copied to clipboard" or "(clipboard failed) - see workspace/farm_report.txt"))
