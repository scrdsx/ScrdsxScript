-- Shop position probe: finds world coordinates for shops that are not streamed in near you (Tool Shop, Clothing Store,
-- Farm Shop, Osso / Ares fuel stations ...). It checks streaming settings, then searches the game's own data
-- (modules + heap tables) for those names next to Vector3 / CFrame values. Run it anywhere. Report -> clipboard.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local lp = Players.LocalPlayer
local out, seen = {}, {}
local function log(s) out[#out + 1] = s end
local function fmt(v)
	local t = typeof(v)
	if t == "Vector3" then return ("V3(%.0f, %.0f, %.0f)"):format(v.X, v.Y, v.Z) end
	if t == "CFrame" then local p = v.Position return ("CF(%.0f, %.0f, %.0f)"):format(p.X, p.Y, p.Z) end
	if t == "Vector2" then return ("V2(%.0f, %.0f)"):format(v.X, v.Y) end
	if t == "table" then return "table" end
	local s = tostring(v)
	return #s > 50 and s:sub(1, 50) .. "..." or s
end
local NAMES = { "tool shop", "clothing", "farm shop", "osso", "ares", "vending", "club", "jewel", "bank", "gas-n-go", "fuel station", "pawn", "gun shop", "supermarket" }
local function hasName(s)
	if type(s) ~= "string" then return false end
	s = s:lower()
	for _, n in ipairs(NAMES) do if s:find(n, 1, true) then return true end end
	return false
end
local function isPos(v) local t = typeof(v) return t == "Vector3" or t == "CFrame" end
print("[shops] started")

log("== streaming ==")
log(("StreamingEnabled=%s MinRadius=%s TargetRadius=%s"):format(tostring(workspace.StreamingEnabled), tostring(workspace.StreamingMinRadius), tostring(workspace.StreamingTargetRadius)))
local pr = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
log("you are at " .. (pr and fmt(pr.Position) or "?"))

log("== Workspace.Robberies descendant counts ==")
local rob = workspace:FindFirstChild("Robberies")
for _, c in ipairs(rob and rob:GetChildren() or {}) do log(("  %s: %d descendants"):format(c.Name, #c:GetDescendants())) end

local function dumpTable(t, depth, prefix, budget)
	if seen[t] or depth > 3 or budget.n <= 0 then return end
	seen[t] = true
	for k, v in pairs(t) do
		if budget.n <= 0 then return end
		if isPos(v) or (type(v) ~= "table" and type(v) ~= "function" and (hasName(k) or hasName(v))) then
			budget.n = budget.n - 1
			log(("%s%s = %s"):format(prefix, fmt(k), fmt(v)))
		elseif type(v) == "table" then
			dumpTable(v, depth + 1, prefix .. fmt(k) .. ".", budget)
		end
	end
end

-- modules that might hold location data
log("== modules with location-ish names ==")
local function requireTimeout(inst)
	local done, ok, mod = false, false, nil
	task.spawn(function() ok, mod = pcall(require, inst); done = true end)
	local t = os.clock()
	while not done and os.clock() - t < 3 do task.wait(0.1) end
	return done and ok, mod
end
local KEYS = { "rob", "heist", "location", "poi", "waypoint", "marker", "region", "navigation", "shop", "store", "spawn", "map" }
for _, root in ipairs({ RS, lp:FindFirstChild("PlayerScripts") }) do
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d:IsA("ModuleScript") then
			local l = d.Name:lower()
			for _, k in ipairs(KEYS) do
				if l:find(k, 1, true) then
					local ok, mod = requireTimeout(d)
					if ok and type(mod) == "table" then
						local lines = #out
						log("MODULE " .. d:GetFullName())
						dumpTable(mod, 0, "  ", { n = 40 })
						if #out == lines + 1 then out[#out] = nil end -- nothing useful in it
					end
					break
				end
			end
		end
	end
end

-- heap tables that mention a shop name
log("== heap tables mentioning shop names ==")
local found, iter = 0, 0
local okgc, heap = pcall(getgc, true)
for _, t in ipairs(okgc and heap or {}) do
	iter = iter + 1
	if iter % 3000 == 0 then task.wait() end
	if type(t) == "table" and found < 40 and not seen[t] then
		local n, mention, pos = 0, false, false
		for k, v in pairs(t) do
			n = n + 1
			if n > 60 then mention = false break end
			if hasName(v) or hasName(k) then mention = true end
			if isPos(v) then pos = true end
			if type(v) == "table" then
				for _, x in pairs(v) do if isPos(x) then pos = true break end end
			end
		end
		if mention and pos then
			found = found + 1
			seen[t] = true
			log("table #" .. found .. ":")
			for k, v in pairs(t) do
				if type(v) == "table" then
					local parts = {}
					for kk, vv in pairs(v) do if #parts < 6 then parts[#parts + 1] = fmt(kk) .. "=" .. fmt(vv) end end
					log(("    %s = {%s}"):format(fmt(k), table.concat(parts, ", ")))
				else
					log(("    %s = %s"):format(fmt(k), fmt(v)))
				end
			end
		end
	end
end

log("== BuildingRegions / Buildings (names + positions where loaded) ==")
for _, folderName in ipairs({ "BuildingRegions", "Buildings", "Dealers", "Smugglers" }) do
	local f = workspace:FindFirstChild(folderName)
	log(folderName .. ": " .. (f and (#f:GetChildren() .. " children") or "missing"))
	local n = 0
	for _, c in ipairs(f and f:GetChildren() or {}) do
		if n < 60 then
			n = n + 1
			local pos
			if c:IsA("BasePart") then pos = c.Position
			elseif c:IsA("Model") then pos = c:GetPivot().Position end
			log(("  %s (%s) %s"):format(c.Name, c.ClassName, pos and fmt(pos) or ""))
		end
	end
end

local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[shops] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))
