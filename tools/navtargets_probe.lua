-- Prints the game's own navigation targets (the GPS list: Tool Shop, Clothing Store, Farm Shop ...) in full, every field,
-- so we can see how each place says where it is. Run anywhere. Report -> clipboard.
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local out, seen = {}, {}
local function log(s) out[#out + 1] = s end
local function fmt(v)
	local t = typeof(v)
	if t == "Vector3" then return ("V3(%.1f, %.1f, %.1f)"):format(v.X, v.Y, v.Z) end
	if t == "CFrame" then local p = v.Position return ("CF(%.1f, %.1f, %.1f)"):format(p.X, p.Y, p.Z) end
	if t == "Instance" then return "Instance:" .. v:GetFullName() end
	if t == "function" then return "function" end
	if t == "table" then return "table" end
	local s = tostring(v)
	return t .. ":" .. (#s > 80 and s:sub(1, 80) .. "..." or s)
end
local count = 0
local function dump(t, depth, prefix)
	if seen[t] or depth > 4 or count > 500 then return end
	seen[t] = true
	local keys = {}
	for k in pairs(t) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for _, k in ipairs(keys) do
		local v = t[k]
		count = count + 1
		if count > 500 then log(prefix .. "... (truncated)") return end
		log(("%s%s = %s"):format(prefix, tostring(k), fmt(v)))
		if type(v) == "table" then dump(v, depth + 1, prefix .. tostring(k) .. ".") end
	end
end
print("[nav] started")

local function req(path)
	local inst = RS
	for part in path:gmatch("[^%.]+") do inst = inst and inst:FindFirstChild(part) end
	if not inst then log("MISSING " .. path) return end
	local done, ok, mod = false, false, nil
	task.spawn(function() ok, mod = pcall(require, inst); done = true end)
	local t = os.clock()
	while not done and os.clock() - t < 4 do task.wait(0.1) end
	log("== " .. path .. " (require " .. tostring(done and ok) .. ") ==")
	if done and ok and type(mod) == "table" then dump(mod, 0, "  ") else log("  " .. fmt(mod)) end
end
req("Code.assets.defaultNavigationTargets")
req("Code.components.navigationTarget")

-- other modules/controllers that resolve navigation targets
log("== scripts named like navigation ==")
for _, root in ipairs({ RS, lp:FindFirstChild("PlayerScripts") }) do
	for _, d in ipairs(root and root:GetDescendants() or {}) do
		if d:IsA("ModuleScript") and (d.Name:lower():find("navigation") or d.Name:lower():find("gps") or d.Name:lower():find("waypoint")) then
			log("  " .. d:GetFullName())
		end
	end
end

local report = table.concat(out, "\n")
if setclipboard then setclipboard(report) end
print(report)
print(("[nav] done: %d chars%s"):format(#report, setclipboard and ", copied to clipboard" or ""))
